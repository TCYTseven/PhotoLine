-- =====================================================================
--  PhotoCards — backend hardening (2026-09-24)
-- =====================================================================
--  Brings a database built from the 2026-09-08 schema up to the current
--  supabase/schema.sql. Idempotent; safe to run more than once. No RPC
--  changes its name, parameters or return shape; get_game_state only
--  gains one additive key ("blocked_user_ids").
--
--  Contents
--    A. Columns, constraints, indexes (FK covering indexes, presence)
--    B. Moderation: stronger banned-word filter, username sanitising
--    C. Engine: presence (last_seen_at / is_connected), host hand-off in
--       finished games, idle-player aware round advancement, server-side
--       sweep (pg_cron) that advances overdue rounds, restart_game fixes
--    D. join_game / list_public_games honour blocks with ANY room member
--    E. delete_my_account hands rooms off instead of destroying them
--    F. report_content rate limit, custom prompt caps
--    G. RLS policies use (select auth.uid()) (advisor 0003)
--    H. Privileges: no direct DML/TRUNCATE for clients, cleanup RPC is
--       server-only
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Columns, constraints, indexes
-- ---------------------------------------------------------------------
alter table public.players add column if not exists last_seen_at timestamptz not null default now();
alter table public.banned_words add column if not exists whole_word boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'players_username_len') then
    alter table public.players add constraint players_username_len
      check (char_length(username) between 1 and 24);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'game_custom_prompts_text_len') then
    alter table public.game_custom_prompts add constraint game_custom_prompts_text_len
      check (char_length(text) between 3 and 140);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'reports_reason_len') then
    alter table public.reports add constraint reports_reason_len
      check (char_length(reason) between 2 and 80);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'reports_details_len') then
    alter table public.reports add constraint reports_details_len
      check (details is null or char_length(details) <= 1000);
  end if;
end $$;

-- Covering indexes for every foreign key (advisor 0001). Account deletion
-- and room cleanup cascade through these.
create index if not exists blocked_users_blocked_idx          on public.blocked_users (blocked_id);
create index if not exists game_prompt_packs_pack_idx         on public.game_prompt_packs (pack_id);
create index if not exists games_current_judge_idx            on public.games (current_judge_player_id);
create index if not exists games_host_idx                     on public.games (host_id);
create index if not exists games_winner_idx                   on public.games (winner_player_id);
create index if not exists games_playing_deadline_idx         on public.games (phase_ends_at) where status = 'playing';
create index if not exists hands_game_idx                     on public.hands (game_id);
create index if not exists hands_photo_idx                    on public.hands (photo_id);
create index if not exists player_photo_history_photo_idx     on public.player_photo_history (photo_id);
create index if not exists reports_game_idx                   on public.reports (game_id);
create index if not exists reports_photo_idx                  on public.reports (photo_id);
create index if not exists reports_reported_user_idx          on public.reports (reported_user_id);
create index if not exists reports_reporter_idx               on public.reports (reporter_id, created_at desc);
create index if not exists rounds_custom_prompt_idx           on public.rounds (custom_prompt_id);
create index if not exists rounds_judge_idx                   on public.rounds (judge_player_id);
create index if not exists rounds_prompt_idx                  on public.rounds (prompt_id);
create index if not exists rounds_winner_submission_idx       on public.rounds (winner_submission_id);
create index if not exists submissions_game_idx               on public.submissions (game_id);
create index if not exists submissions_photo_idx              on public.submissions (photo_id);
create index if not exists submissions_player_idx             on public.submissions (player_id);
create index if not exists votes_submission_idx               on public.votes (submission_id);
create index if not exists votes_voter_idx                    on public.votes (voter_player_id);

-- Short words that are also parts of harmless words ("grape", "pinkys",
-- "flame retardant", "Ashkenazi") only match as whole words.
update public.banned_words set whole_word = true
where word in ('rape', 'kys', 'retard', 'nazi') and not whole_word;

-- ---------------------------------------------------------------------
-- B-F. Functions (identical to supabase/schema.sql)
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    left(coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name'), 40)
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- Matches against a normalised copy of the text: lower case, common
-- leetspeak undone ("5h1t"), and separators removed ("f.u.c.k"). Words
-- flagged whole_word only match on their own ("rape" but not "grape").
create or replace function public._contains_banned_word(p_text text)
returns boolean
language sql
stable
as $$
  with t as (
    select translate(lower(coalesce(p_text, '')), '013457@$!|', 'oieastasii') as leet
  ),
  n as (
    -- Separators inside a word are dropped (f.u.c.k), but spaces stay word
    -- boundaries so "Push it" doesn't read as one word containing a slur.
    select ' ' || regexp_replace(regexp_replace(t.leet, '[^a-z[:space:]]', '', 'g'), '[[:space:]]+', ' ', 'g') || ' ' as squashed,
           ' ' || regexp_replace(t.leet, '[^a-z]+', ' ', 'g') || ' ' as spaced
    from t
  )
  select exists (
    select 1
    from public.banned_words b, n
    where (not b.whole_word and n.squashed like '%' || b.word || '%')
       or (b.whole_word and (n.spaced like '% ' || b.word || ' %'
                             or n.spaced like '% ' || b.word || 's %'))
  );
$$;

create or replace function public._clean_username(p_name text)
returns text
language plpgsql
stable
as $$
declare
  v_name text;
begin
  -- Drop control and invisible formatting characters (zero-width spaces,
  -- bidi overrides) that could fake an empty or look-alike name.
  v_name := regexp_replace(coalesce(p_name, ''),
                           '[[:cntrl:]\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]', '', 'g');
  v_name := btrim(regexp_replace(v_name, '\s+', ' ', 'g'));
  if length(v_name) < 1 then
    raise exception 'Please enter a name first.';
  end if;
  if length(v_name) > 20 then
    v_name := btrim(left(v_name, 20));
  end if;
  if public._contains_banned_word(v_name) then
    raise exception 'That name is not allowed. Please pick another one.';
  end if;
  return v_name;
end $$;

-- ---- Game state snapshot --------------------------------------------
-- Everything a client needs to render any screen. Submissions are only
-- included once judging starts, and their owners only once the round is
-- over, which keeps the reveal anonymous.
--
-- Also the presence heartbeat: every client polls this every few seconds
-- while the app is open, so it stamps players.last_seen_at. The sweep
-- (_sweep_games) marks players it hasn't heard from as disconnected, and
-- the next call here reconnects them.
create or replace function public.get_game_state(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  g            public.games%rowtype;
  me           public.players%rowtype;
  r            public.rounds%rowtype;
  v_show_subs  boolean;
  v_show_owner boolean;
  v_players    jsonb;
  v_hand       jsonb;
  v_subs       jsonb;
  v_highlights jsonb;
  v_packs      jsonb;
begin
  select * into g from public.games where id = p_game_id;
  if not found then
    raise exception 'Game not found.';
  end if;

  select * into me from public.players where game_id = p_game_id and user_id = v_uid;
  if not found then
    raise exception 'You are not in this game.';
  end if;

  if me.left_at is null then
    if not me.is_connected then
      -- Coming back: lock the game first (same order as every RPC) and
      -- bump the version so the others see the player return.
      perform 1 from public.games where id = p_game_id for update;
      update public.players set is_connected = true, last_seen_at = now() where id = me.id;
      perform public._touch_game(p_game_id);
      select * into g from public.games where id = p_game_id;
      select * into me from public.players where id = me.id;
    elsif me.last_seen_at < now() - interval '10 seconds' then
      update public.players set last_seen_at = now() where id = me.id;
    end if;
  end if;

  select * into r from public.rounds where game_id = p_game_id and round_number = g.current_round;

  v_show_subs  := g.phase in ('judging', 'round_results', 'game_over');
  v_show_owner := g.phase in ('round_results', 'game_over');

  select coalesce(jsonb_agg(jsonb_build_object(
      'id',            p.id,
      'user_id',       p.user_id,
      'username',      p.username,
      'score',         p.score,
      'is_ready',      p.is_ready,
      'is_host',       p.is_host,
      'is_connected',  p.is_connected,
      'is_judge',      coalesce(p.id = g.current_judge_player_id, false),
      'joined_at',     p.joined_at,
      'has_submitted', (r.id is not null and exists (
                          select 1 from public.submissions s where s.round_id = r.id and s.player_id = p.id)),
      'has_voted',     (r.id is not null and exists (
                          select 1 from public.votes v where v.round_id = r.id and v.voter_player_id = p.id))
    ) order by p.joined_at), '[]'::jsonb)
  into v_players
  from public.players p
  where p.game_id = g.id and p.left_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id',            h.id,
      'photo_id',      ph.id,
      'image_url',     ph.image_url,
      'thumbnail_url', coalesce(ph.thumbnail_url, ph.image_url),
      'position',      h.position
    ) order by h.position), '[]'::jsonb)
  into v_hand
  from public.hands h
  join public.photos ph on ph.id = h.photo_id
  where h.player_id = me.id;

  if v_show_subs and r.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
        'id',            s.id,
        'photo_id',      ph.id,
        'image_url',     ph.image_url,
        'thumbnail_url', coalesce(ph.thumbnail_url, ph.image_url),
        'is_winner',     s.is_winner,
        'is_mine',       (s.player_id = me.id),
        'player_id',     case when v_show_owner then s.player_id else null end,
        'username',      case when v_show_owner then p.username else null end,
        'vote_count',    case when v_show_owner
                              then (select count(*) from public.votes v where v.submission_id = s.id)
                              else null end
      ) order by md5(s.id::text || r.id::text)), '[]'::jsonb)
    into v_subs
    from public.submissions s
    join public.photos ph on ph.id = s.photo_id
    join public.players p on p.id = s.player_id
    where s.round_id = r.id;
  else
    v_subs := '[]'::jsonb;
  end if;

  if g.phase = 'game_over' then
    select coalesce(jsonb_agg(jsonb_build_object(
        'round_number',  rr.round_number,
        'prompt_text',   rr.prompt_text,
        'image_url',     ph.image_url,
        'thumbnail_url', coalesce(ph.thumbnail_url, ph.image_url),
        'username',      p.username
      ) order by rr.round_number), '[]'::jsonb)
    into v_highlights
    from public.rounds rr
    join public.submissions s on s.id = rr.winner_submission_id
    join public.photos ph on ph.id = s.photo_id
    join public.players p on p.id = s.player_id
    where rr.game_id = g.id;
  else
    v_highlights := '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(pp.name order by pp.sort_order), '[]'::jsonb)
  into v_packs
  from public.game_prompt_packs gpp
  join public.prompt_packs pp on pp.id = gpp.pack_id
  where gpp.game_id = g.id;

  return jsonb_build_object(
    'game', jsonb_build_object(
      'id',                      g.id,
      'room_code',               g.room_code,
      'host_id',                 g.host_id,
      'status',                  g.status,
      'phase',                   g.phase,
      'mode',                    g.mode,
      'is_public',               g.is_public,
      'max_players',             g.max_players,
      'max_rounds',              g.max_rounds,
      'target_score',            g.target_score,
      'round_timer_seconds',     g.round_timer_seconds,
      'judge_timer_seconds',     g.judge_timer_seconds,
      'results_seconds',         g.results_seconds,
      'hand_size',               g.hand_size,
      'refreshes_per_player',    g.refreshes_per_player,
      'current_round',           g.current_round,
      'current_judge_player_id', g.current_judge_player_id,
      'winner_player_id',        g.winner_player_id,
      'phase_ends_at',           g.phase_ends_at,
      'server_time',             now(),
      'version',                 g.version,
      'created_at',              g.created_at,
      'prompt_packs',            v_packs,
      'prompt_pack_slugs',       (select coalesce(jsonb_agg(pp.slug order by pp.sort_order), '[]'::jsonb)
                                    from public.game_prompt_packs gpp
                                    join public.prompt_packs pp on pp.id = gpp.pack_id
                                    where gpp.game_id = g.id),
      'custom_prompts',          (select coalesce(jsonb_agg(c.text order by c.created_at), '[]'::jsonb)
                                    from public.game_custom_prompts c where c.game_id = g.id),
      'custom_prompt_count',     (select count(*) from public.game_custom_prompts c where c.game_id = g.id)
    ),
    'me', jsonb_build_object(
      'player_id',             me.id,
      'user_id',               me.user_id,
      'username',              me.username,
      'is_host',               me.is_host,
      'is_judge',              coalesce(g.current_judge_player_id = me.id, false),
      'refreshes_used',        me.refreshes_used,
      'has_submitted',         (r.id is not null and exists (
                                  select 1 from public.submissions s where s.round_id = r.id and s.player_id = me.id)),
      'my_vote_submission_id', (select v.submission_id from public.votes v
                                  where v.round_id = r.id and v.voter_player_id = me.id)
    ),
    'players', v_players,
    'round', case when r.id is null then null else jsonb_build_object(
      'id',                   r.id,
      'round_number',         r.round_number,
      'judge_player_id',      r.judge_player_id,
      'judge_username',       (select p.username from public.players p where p.id = r.judge_player_id),
      'prompt_text',          r.prompt_text,
      'winner_submission_id', r.winner_submission_id,
      'started_at',           r.started_at,
      'submission_count',     (select count(*) from public.submissions s where s.round_id = r.id),
      'vote_count',           (select count(*) from public.votes v where v.round_id = r.id)
    ) end,
    'hand',        v_hand,
    'submissions', v_subs,
    'highlights',  v_highlights,
    -- Additive: user ids the caller has blocked, so the client can hide
    -- their names / photos in the room.
    'blocked_user_ids', (select coalesce(jsonb_agg(b.blocked_id), '[]'::jsonb)
                           from public.blocked_users b where b.blocker_id = v_uid)
  );
end $$;

-- Players the current round is still waiting on: active, connected,
-- not the judge, and without a submission yet. Disconnected players
-- (app closed for 45s+) are not waited for; the round timer covers them.
create or replace function public._pending_submitters(p_game_id uuid)
returns int
language sql
stable
as $$
  select count(*)::int
  from public.games g
  join public.rounds r on r.game_id = g.id and r.round_number = g.current_round
  join public.players p on p.game_id = g.id
  where g.id = p_game_id
    and p.left_at is null
    and p.is_connected
    and p.id is distinct from g.current_judge_player_id
    and not exists (select 1 from public.submissions s where s.round_id = r.id and s.player_id = p.id);
$$;

create or replace function public._pending_voters(p_game_id uuid)
returns int
language sql
stable
as $$
  select count(*)::int
  from public.games g
  join public.rounds r on r.game_id = g.id and r.round_number = g.current_round
  join public.players p on p.game_id = g.id
  where g.id = p_game_id
    and p.left_at is null
    and p.is_connected
    and not exists (select 1 from public.votes v where v.round_id = r.id and v.voter_player_id = p.id);
$$;

create or replace function public._start_round(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g              public.games%rowtype;
  v_round        int;
  v_judge        uuid;
  v_player_count int;
  v_connected    int;
  v_prompt_id    uuid;
  v_custom_id    uuid;
  v_prompt_text  text;
begin
  select * into g from public.games where id = p_game_id for update;
  v_round := g.current_round + 1;

  select count(*), count(*) filter (where is_connected)
  into v_player_count, v_connected
  from public.players where game_id = g.id and left_at is null;
  if v_player_count < 3 then
    perform public._finish_game(g.id);
    return;
  end if;

  -- Judge rotates through connected players in join order (vote mode has
  -- no judge). Falls back to everyone if nobody is currently connected.
  if g.mode <> 'vote' then
    select p.id into v_judge
    from public.players p
    where p.game_id = g.id and p.left_at is null and p.is_connected
    order by p.joined_at
    offset ((v_round - 1) % greatest(v_connected, 1))
    limit 1;

    if v_judge is null then
      select p.id into v_judge
      from public.players p
      where p.game_id = g.id and p.left_at is null
      order by p.joined_at
      offset ((v_round - 1) % v_player_count)
      limit 1;
    end if;
  else
    v_judge := null;
  end if;

  -- Prompt: unused custom prompts first, then unused pack prompts, then any.
  select c.id, c.text into v_custom_id, v_prompt_text
  from public.game_custom_prompts c
  where c.game_id = g.id and not c.used
  order by random()
  limit 1;

  if v_custom_id is not null then
    update public.game_custom_prompts set used = true where id = v_custom_id;
  else
    select p.id, p.text into v_prompt_id, v_prompt_text
    from public.prompts p
    join public.game_prompt_packs gpp on gpp.pack_id = p.pack_id
    where gpp.game_id = g.id
      and p.approved
      and not exists (select 1 from public.rounds rr where rr.game_id = g.id and rr.prompt_id = p.id)
    order by random()
    limit 1;

    if v_prompt_id is null then
      select p.id, p.text into v_prompt_id, v_prompt_text
      from public.prompts p
      join public.game_prompt_packs gpp on gpp.pack_id = p.pack_id
      where gpp.game_id = g.id and p.approved
      order by random()
      limit 1;
    end if;
  end if;

  if v_prompt_text is null then
    raise exception 'No prompts are available for this game.';
  end if;

  insert into public.rounds (game_id, round_number, judge_player_id, prompt_id, custom_prompt_id, prompt_text)
  values (g.id, v_round, v_judge, v_prompt_id, v_custom_id, v_prompt_text);

  perform public._fill_hands(g.id);

  update public.games
  set status = 'playing',
      phase = 'choosing',
      current_round = v_round,
      current_judge_player_id = v_judge,
      phase_ends_at = now() + make_interval(secs => round_timer_seconds),
      expires_at = greatest(expires_at, now() + interval '6 hours')
  where id = g.id;

  perform public._touch_game(g.id);
end $$;

-- Moves a game on when its phase timer has run out. Caller-agnostic and
-- idempotent: it re-checks the deadline under the row lock, so a client
-- nudge and the server sweep can race without double-advancing.
create or replace function public._advance(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g public.games%rowtype;
  r public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found or g.status <> 'playing' or g.phase_ends_at is null or g.phase_ends_at > now() then
    return;
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;
  if g.phase = 'choosing' then
    perform public._to_judging(g.id);
  elsif g.phase = 'judging' then
    if g.mode = 'vote' then
      perform public._resolve_votes(g.id);
    else
      perform public._end_round(g.id, public._random_submission(r.id));
    end if;
  elsif g.phase = 'round_results' then
    perform public._next_round(g.id);
  end if;
end $$;

-- ---- Leaving -----------------------------------------------------------
create or replace function public._player_leaves(p_game_id uuid, p_player_id uuid)
returns void
language plpgsql
as $$
declare
  g           public.games%rowtype;
  me          public.players%rowtype;
  r           public.rounds%rowtype;
  v_new_host  public.players%rowtype;
  v_connected int;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then return; end if;
  select * into me from public.players where id = p_player_id;
  if not found or me.left_at is not null then return; end if;

  if g.status = 'lobby' then
    delete from public.players where id = me.id;
    if me.is_host then
      select * into v_new_host from public.players
      where game_id = g.id and left_at is null
      order by joined_at limit 1;
      if not found then
        delete from public.games where id = g.id;
        return;
      end if;
      update public.players set is_host = true, is_ready = true where id = v_new_host.id;
      update public.games set host_id = v_new_host.user_id where id = g.id;
    end if;
    perform public._touch_game(g.id);
    return;
  end if;

  update public.players
  set left_at = now(), is_connected = false, is_ready = false, is_host = false
  where id = me.id;

  select count(*) into v_connected
  from public.players where game_id = g.id and left_at is null;

  -- Host hand-off (playing AND finished, so "Play again" stays usable).
  if me.is_host and v_connected > 0 then
    select * into v_new_host from public.players
    where game_id = g.id and left_at is null
    order by joined_at limit 1;
    update public.players set is_host = true where id = v_new_host.id;
    update public.games set host_id = v_new_host.user_id where id = g.id;
  end if;

  if g.status = 'finished' then
    if v_connected = 0 then
      -- Everyone has gone: nothing left to restart.
      delete from public.games where id = g.id;
      return;
    end if;
    perform public._touch_game(g.id);
    return;
  end if;

  -- status = playing
  if v_connected < 3 then
    perform public._finish_game(g.id);
    return;
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;

  if g.phase = 'judging' then
    if g.mode = 'vote' then
      if public._pending_voters(g.id) = 0 then
        perform public._resolve_votes(g.id);
        return;
      end if;
    elsif g.current_judge_player_id = me.id then
      perform public._end_round(g.id, public._random_submission(r.id));
      return;
    end if;
  elsif g.phase = 'choosing' then
    if public._pending_submitters(g.id) = 0 then
      perform public._to_judging(g.id);
      return;
    end if;
  end if;

  perform public._touch_game(g.id);
end $$;

-- ---- Server-side sweep -------------------------------------------------
-- Runs every 15 seconds from pg_cron (see below). Clients still nudge
-- advance_game themselves; the sweep covers the cases they can't:
--   • marks players whose app stopped polling (45s) as disconnected, so
--     rounds stop waiting on them and they are skipped as judge;
--   • advances overdue phases, and ends a phase early when the only
--     players it is waiting on are disconnected.
-- A game where nobody is connected is left alone (everyone locked their
-- phone), so it resumes where it was instead of racing to game over.
create or replace function public._sweep_game(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g public.games%rowtype;
  r public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update skip locked;
  if not found then return; end if;  -- busy right now: next sweep

  if exists (select 1 from public.players p
             where p.game_id = g.id and p.left_at is null and p.is_connected
               and p.last_seen_at < now() - interval '45 seconds') then
    update public.players
    set is_connected = false
    where game_id = g.id and left_at is null and is_connected
      and last_seen_at < now() - interval '45 seconds';
    perform public._touch_game(g.id);
  end if;

  if g.status <> 'playing' then return; end if;
  if not exists (select 1 from public.players p
                 where p.game_id = g.id and p.left_at is null and p.is_connected) then
    return;
  end if;

  if g.phase_ends_at is not null and g.phase_ends_at <= now() - interval '2 seconds' then
    perform public._advance(g.id);
    return;
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;
  if r.id is null then return; end if;

  if g.phase = 'choosing' then
    if public._pending_submitters(g.id) = 0
       and exists (select 1 from public.submissions s where s.round_id = r.id) then
      perform public._to_judging(g.id);
    end if;
  elsif g.phase = 'judging' then
    if g.mode = 'vote' then
      if public._pending_voters(g.id) = 0 then
        perform public._resolve_votes(g.id);
      end if;
    elsif not exists (select 1 from public.players p
                      where p.id = g.current_judge_player_id and p.left_at is null and p.is_connected) then
      perform public._end_round(g.id, public._random_submission(r.id));
    end if;
  end if;
end $$;

create or replace function public._sweep_games()
returns int
language plpgsql
as $$
declare
  v_game record;
  v_n    int := 0;
begin
  for v_game in
    select g.id from public.games g
    where g.status = 'playing'
       or exists (select 1 from public.players p
                  where p.game_id = g.id and p.left_at is null and p.is_connected
                    and p.last_seen_at < now() - interval '45 seconds')
  loop
    begin
      perform public._sweep_game(v_game.id);
      v_n := v_n + 1;
    exception when others then
      raise warning 'sweep of game % failed: %', v_game.id, sqlerrm;
    end;
  end loop;
  return v_n;
end $$;

-- ---- Settings ---------------------------------------------------------
create or replace function public._apply_game_settings(
  p_game_id             uuid,
  p_mode                public.game_mode,
  p_is_public           boolean,
  p_max_players         int,
  p_max_rounds          int,
  p_target_score        int,
  p_round_timer_seconds int,
  p_pack_slugs          text[],
  p_custom_prompts      text[]
)
returns void
language plpgsql
as $$
declare
  v_mode   public.game_mode := coalesce(p_mode, 'classic');
  v_timer  int := coalesce(p_round_timer_seconds, 60);
  v_prompt text;
  v_added  int := 0;
begin
  if v_mode = 'rapid' then
    v_timer := least(v_timer, 20);
  end if;
  v_timer := greatest(10, least(v_timer, 300));

  update public.games
  set mode = v_mode,
      is_public = coalesce(p_is_public, false),
      max_players = greatest(3, least(coalesce(p_max_players, 8), 12)),
      max_rounds = greatest(1, least(coalesce(p_max_rounds, 8), 30)),
      target_score = greatest(1, least(coalesce(p_target_score, 5), 30)),
      round_timer_seconds = v_timer,
      judge_timer_seconds = greatest(20, least(v_timer, 90))
  where id = p_game_id;

  delete from public.game_prompt_packs where game_id = p_game_id;
  if p_pack_slugs is not null and array_length(p_pack_slugs, 1) > 0 then
    insert into public.game_prompt_packs (game_id, pack_id)
    select p_game_id, pp.id from public.prompt_packs pp
    where pp.slug = any (p_pack_slugs[1:50]) and pp.approved
    on conflict do nothing;
  end if;
  if not exists (select 1 from public.game_prompt_packs where game_id = p_game_id) then
    insert into public.game_prompt_packs (game_id, pack_id)
    select p_game_id, pp.id from public.prompt_packs pp where pp.is_default and pp.approved
    on conflict do nothing;
  end if;

  -- Custom prompts: at most 50 per room, 3-140 characters, filtered.
  delete from public.game_custom_prompts where game_id = p_game_id;
  if p_custom_prompts is not null then
    foreach v_prompt in array p_custom_prompts[1:200] loop
      exit when v_added >= 50;
      v_prompt := regexp_replace(coalesce(v_prompt, ''),
                                 '[[:cntrl:]\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]', '', 'g');
      v_prompt := btrim(regexp_replace(v_prompt, '\s+', ' ', 'g'));
      if length(v_prompt) between 3 and 140 and not public._contains_banned_word(v_prompt) then
        insert into public.game_custom_prompts (game_id, text) values (p_game_id, v_prompt);
        v_added := v_added + 1;
      end if;
    end loop;
  end if;
end $$;

create or replace function public.join_game(p_room_code text, p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := public._require_uid();
  v_name  text := public._clean_username(p_username);
  v_code  text := upper(btrim(coalesce(p_room_code, '')));
  g       public.games%rowtype;
  me      public.players%rowtype;
  v_count int;
begin
  select * into g from public.games
  where room_code = v_code and status <> 'finished' and expires_at > now()
  for update;
  if not found then
    raise exception 'Room not found. Check the code and try again.';
  end if;

  select * into me from public.players where game_id = g.id and user_id = v_uid;

  if found then
    if me.left_at is not null then
      -- Rejoin a game in progress (leaving any other room first).
      perform public._leave_all_active_games(v_uid);
      update public.players
      set left_at = null, is_connected = true, last_seen_at = now()
      where id = me.id;
      perform public._touch_game(g.id);
    end if;
    return public.get_game_state(g.id);
  end if;

  if g.status <> 'lobby' then
    raise exception 'This game has already started.';
  end if;
  -- Blocks work both ways, with anyone already in the room.
  if exists (
    select 1
    from public.players p
    join public.blocked_users b
      on (b.blocker_id = p.user_id and b.blocked_id = v_uid)
      or (b.blocker_id = v_uid and b.blocked_id = p.user_id)
    where p.game_id = g.id and p.left_at is null
  ) then
    raise exception 'You can''t join this room.';
  end if;

  select count(*) into v_count from public.players where game_id = g.id and left_at is null;
  if v_count >= g.max_players then
    raise exception 'This room is full.';
  end if;

  perform public._leave_all_active_games(v_uid);

  insert into public.players (game_id, user_id, username)
  values (g.id, v_uid, public._unique_username(g.id, v_name));

  update public.profiles set display_name = v_name where id = v_uid;

  perform public._touch_game(g.id);
  return public.get_game_state(g.id);
end $$;

-- Used on app launch to resume a game the player never explicitly left.
-- Not STABLE: get_game_state records presence.
create or replace function public.get_my_active_game()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := public._require_uid();
  v_game_id uuid;
begin
  select g.id into v_game_id
  from public.games g
  join public.players p on p.game_id = g.id
  where p.user_id = v_uid
    and p.left_at is null
    and g.status <> 'finished'
    and g.expires_at > now()
  order by g.created_at desc
  limit 1;

  if v_game_id is null then
    return 'null'::jsonb;
  end if;
  return public.get_game_state(v_game_id);
end $$;

create or replace function public.submit_photo(p_game_id uuid, p_photo_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := public._require_uid();
  g         public.games%rowtype;
  me        public.players%rowtype;
  r         public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if g.status <> 'playing' or g.phase <> 'choosing' then
    raise exception 'You can''t submit a photo right now.';
  end if;
  if g.phase_ends_at is not null and g.phase_ends_at < now() - interval '2 seconds' then
    raise exception 'Time is up for this round.';
  end if;

  select * into me from public.players where game_id = g.id and user_id = v_uid and left_at is null;
  if not found then raise exception 'You are not in this game.'; end if;
  if me.id = g.current_judge_player_id then
    raise exception 'The judge doesn''t submit a photo this round.';
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;

  if exists (select 1 from public.submissions s where s.round_id = r.id and s.player_id = me.id) then
    raise exception 'You already submitted a photo this round.';
  end if;
  if not exists (select 1 from public.hands h where h.player_id = me.id and h.photo_id = p_photo_id) then
    raise exception 'That photo isn''t in your hand.';
  end if;

  insert into public.submissions (game_id, round_id, player_id, photo_id)
  values (g.id, r.id, me.id, p_photo_id);

  delete from public.hands where player_id = me.id and photo_id = p_photo_id;

  if public._pending_submitters(g.id) = 0 then
    perform public._to_judging(g.id);
  else
    perform public._touch_game(g.id);
  end if;

  return public.get_game_state(g.id);
end $$;

create or replace function public.cast_vote(p_game_id uuid, p_submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := public._require_uid();
  g         public.games%rowtype;
  me        public.players%rowtype;
  r         public.rounds%rowtype;
  s         public.submissions%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if g.status <> 'playing' or g.phase <> 'judging' or g.mode <> 'vote' then
    raise exception 'Voting isn''t open right now.';
  end if;

  select * into me from public.players where game_id = g.id and user_id = v_uid and left_at is null;
  if not found then raise exception 'You are not in this game.'; end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;
  select * into s from public.submissions where id = p_submission_id and round_id = r.id;
  if not found then raise exception 'That photo isn''t part of this round.'; end if;
  if s.player_id = me.id then raise exception 'You can''t vote for your own photo.'; end if;

  insert into public.votes (round_id, voter_player_id, submission_id)
  values (r.id, me.id, s.id)
  on conflict (round_id, voter_player_id) do update set submission_id = excluded.submission_id;

  if public._pending_voters(g.id) = 0 then
    perform public._resolve_votes(g.id);
  else
    perform public._touch_game(g.id);
  end if;

  return public.get_game_state(g.id);
end $$;

-- Clients call this when a phase timer runs out. It is idempotent and
-- server-checked, so it doesn't matter who calls it or how often.
create or replace function public.advance_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
  g     public.games%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if not exists (select 1 from public.players p where p.game_id = g.id and p.user_id = v_uid) then
    raise exception 'You are not in this game.';
  end if;

  perform public._advance(g.id);

  return public.get_game_state(g.id);
end $$;

-- "Play again": same room, same players, fresh scores.
create or replace function public.restart_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
  g     public.games%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if g.host_id <> v_uid then raise exception 'Only the host can start a new game.'; end if;
  if g.status <> 'finished' then raise exception 'The game is still running.'; end if;

  delete from public.votes where round_id in (select id from public.rounds where game_id = g.id);
  delete from public.submissions where game_id = g.id;
  update public.games set current_judge_player_id = null, winner_player_id = null where id = g.id;
  delete from public.rounds where game_id = g.id;
  delete from public.hands where game_id = g.id;
  delete from public.player_photo_history
  where player_id in (select id from public.players where game_id = g.id);
  delete from public.players where game_id = g.id and left_at is not null;
  -- Players who have since moved on to another live room are not pulled
  -- back into this one (a user is only ever in one live room).
  delete from public.players p
  where p.game_id = g.id
    and p.user_id <> v_uid
    and exists (select 1 from public.players o
                join public.games og on og.id = o.game_id
                where o.user_id = p.user_id and o.game_id <> g.id
                  and o.left_at is null and og.status <> 'finished');
  update public.players
  set score = 0, refreshes_used = 0, is_host = (user_id = v_uid), is_ready = (user_id = v_uid)
  where game_id = g.id;
  update public.game_custom_prompts set used = false where game_id = g.id;

  -- The code was released when the game finished; take a fresh one if
  -- another live room has picked it up since.
  if exists (select 1 from public.games o
             where o.room_code = g.room_code and o.status <> 'finished' and o.id <> g.id) then
    update public.games set room_code = public._generate_room_code() where id = g.id;
  end if;

  update public.games
  set status = 'lobby',
      phase = 'lobby',
      current_round = 0,
      phase_ends_at = null,
      started_at = null,
      finished_at = null,
      expires_at = now() + interval '12 hours'
  where id = g.id;

  perform public._touch_game(g.id);
  return public.get_game_state(g.id);
end $$;

-- Browse open public lobbies (newest 50). Rooms containing anyone the
-- caller has blocked, or who has blocked the caller, are hidden.
create or replace function public.list_public_games()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
begin
  return (
    select coalesce(jsonb_agg(x.obj order by x.created_at desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
          'id',            g.id,
          'room_code',     g.room_code,
          'mode',          g.mode,
          'max_players',   g.max_players,
          'player_count',  (select count(*) from public.players p where p.game_id = g.id and p.left_at is null),
          'host_username', (select p.username from public.players p
                              where p.game_id = g.id and p.is_host and p.left_at is null limit 1),
          'created_at',    g.created_at
        ) as obj,
        g.created_at
      from public.games g
      where g.is_public
        and g.status = 'lobby'
        and g.expires_at > now()
        and (select count(*) from public.players p where p.game_id = g.id and p.left_at is null) < g.max_players
        and not exists (
          select 1
          from public.players p
          join public.blocked_users b
            on (b.blocker_id = p.user_id and b.blocked_id = v_uid)
            or (b.blocker_id = v_uid and b.blocked_id = p.user_id)
          where p.game_id = g.id and p.left_at is null
        )
      order by g.created_at desc
      limit 50
    ) x
  );
end $$;

-- In-app account deletion (App Store Review Guideline 5.1.1(v)).
-- Leaves every room first so hosting passes to another player (lobby,
-- playing and finished rooms alike) instead of closing the room on them,
-- then removes the auth user; every table cascades from auth.users, so
-- the profile, players, submissions, votes, reports and blocks go too.
create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
  v_p   record;
begin
  for v_p in
    select pl.id, pl.game_id from public.players pl
    where pl.user_id = v_uid and pl.left_at is null
  loop
    perform public._player_leaves(v_p.game_id, v_p.id);
  end loop;

  -- Only rooms nobody else is still in are left hosted by this user.
  delete from public.games g
  where g.host_id = v_uid
    and not exists (select 1 from public.players p
                    where p.game_id = g.id and p.left_at is null and p.user_id <> v_uid);

  delete from auth.users where id = v_uid;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.report_content(
  p_reason           text,
  p_details          text default null,
  p_game_id          uuid default null,
  p_reported_user_id uuid default null,
  p_photo_id         uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
begin
  if length(btrim(coalesce(p_reason, ''))) < 2 then
    raise exception 'Please choose a reason.';
  end if;
  if (select count(*) from public.reports
      where reporter_id = v_uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'You''ve sent a lot of reports. Please try again later.';
  end if;

  -- Dangling ids (room already cleaned up, user already deleted) are
  -- dropped rather than failing the report.
  insert into public.reports (reporter_id, game_id, reported_user_id, photo_id, reason, details)
  values (
    v_uid,
    (select id from public.games  where id = p_game_id),
    (select id from auth.users    where id = p_reported_user_id),
    (select id from public.photos where id = p_photo_id),
    left(btrim(p_reason), 80),
    left(nullif(btrim(coalesce(p_details, '')), ''), 1000)
  );
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- G. RLS policies: (select auth.uid()) is evaluated once per query
-- ---------------------------------------------------------------------
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists photos_select_approved on public.photos;
create policy photos_select_approved on public.photos
  for select to authenticated using (approved);

drop policy if exists prompt_packs_select_approved on public.prompt_packs;
create policy prompt_packs_select_approved on public.prompt_packs
  for select to authenticated using (approved);

drop policy if exists prompts_select_approved on public.prompts;
create policy prompts_select_approved on public.prompts
  for select to authenticated using (approved);

drop policy if exists games_select_member_or_public on public.games;
create policy games_select_member_or_public on public.games
  for select to authenticated
  using (
    host_id = (select auth.uid())
    or public.is_game_member(id)
    or (is_public and status = 'lobby' and expires_at > now())
  );

drop policy if exists players_select_member on public.players;
create policy players_select_member on public.players
  for select to authenticated using (public.is_game_member(game_id));

drop policy if exists game_prompt_packs_select_member on public.game_prompt_packs;
create policy game_prompt_packs_select_member on public.game_prompt_packs
  for select to authenticated using (public.is_game_member(game_id));

drop policy if exists game_custom_prompts_select_member on public.game_custom_prompts;
create policy game_custom_prompts_select_member on public.game_custom_prompts
  for select to authenticated using (public.is_game_member(game_id));

drop policy if exists rounds_select_member on public.rounds;
create policy rounds_select_member on public.rounds
  for select to authenticated using (public.is_game_member(game_id));

-- A player can only ever see their own hand.
drop policy if exists hands_select_own on public.hands;
create policy hands_select_own on public.hands
  for select to authenticated using (public.is_my_player(player_id));

-- Other players' submissions are only exposed (anonymised) through
-- get_game_state(), never through direct table reads.
drop policy if exists submissions_select_own on public.submissions;
create policy submissions_select_own on public.submissions
  for select to authenticated using (public.is_my_player(player_id));

drop policy if exists votes_select_own on public.votes;
create policy votes_select_own on public.votes
  for select to authenticated using (public.is_my_player(voter_player_id));

drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));

drop policy if exists blocked_users_select_own on public.blocked_users;
create policy blocked_users_select_own on public.blocked_users
  for select to authenticated using (blocker_id = (select auth.uid()));
drop policy if exists blocked_users_insert_own on public.blocked_users;
create policy blocked_users_insert_own on public.blocked_users
  for insert to authenticated with check (blocker_id = (select auth.uid()));
drop policy if exists blocked_users_delete_own on public.blocked_users;
create policy blocked_users_delete_own on public.blocked_users
  for delete to authenticated using (blocker_id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- H. Privileges and schedule
-- ---------------------------------------------------------------------
-- Table privileges: signed-in users can read (RLS filters rows); nobody
-- writes tables directly (every write is an RPC that validates, filters
-- and rate-limits); anonymous (not signed in) gets nothing. Supabase's
-- default privileges hand out INSERT/UPDATE/DELETE/TRUNCATE on every new
-- table, so start from nothing and grant back only what is needed.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant usage on schema public to authenticated;
grant select on
  public.profiles, public.photos, public.prompt_packs, public.prompts, public.games,
  public.players, public.game_prompt_packs, public.game_custom_prompts, public.rounds,
  public.hands, public.submissions, public.votes, public.reports, public.blocked_users
to authenticated;
grant insert, delete on public.blocked_users to authenticated;

-- Function privileges: public RPCs → authenticated only; "_internal"
-- helpers → nobody (they only run inside SECURITY DEFINER functions).
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature, p.proname as name
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
  loop
    -- Pin search_path everywhere (Supabase advisor 0011).
    execute format('alter function %s set search_path = public', f.signature);

    if f.name in ('handle_new_user', 'set_updated_at') then
      -- Trigger functions: only the auth service (and the owner) run them.
      execute format('revoke all on function %s from public, anon, authenticated', f.signature);
      execute format('grant execute on function %s to supabase_auth_admin, service_role', f.signature);
      continue;
    end if;
    if f.name = 'cleanup_expired_games' then
      -- Maintenance: pg_cron / service role only.
      execute format('revoke all on function %s from public, anon, authenticated', f.signature);
      execute format('grant execute on function %s to service_role', f.signature);
      continue;
    end if;
    execute format('revoke all on function %s from public, anon', f.signature);
    if f.name like '\_%' then
      execute format('revoke all on function %s from authenticated', f.signature);
    else
      execute format('grant execute on function %s to authenticated, service_role', f.signature);
    end if;
  end loop;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'photocards_sweep_games') then
      begin
        perform cron.schedule('photocards_sweep_games', '15 seconds', 'select public._sweep_games();');
      exception when others then
        perform cron.schedule('photocards_sweep_games', '* * * * *', 'select public._sweep_games();');
      end;
    end if;
  else
    raise notice 'pg_cron not available: rounds only advance when a client calls advance_game.';
  end if;
end $$;
