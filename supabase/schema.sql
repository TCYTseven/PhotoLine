-- =====================================================================
--  PhotoCards — Supabase master schema
-- =====================================================================
--  Run this whole file ONCE in the Supabase SQL editor of a fresh project
--  (Dashboard → SQL Editor → New query → paste → Run). It is written to be
--  re-runnable: every statement is guarded with IF NOT EXISTS / OR REPLACE.
--
--  What it sets up
--    0. Extensions
--    1. Enums
--    2. Tables (profiles, photo library, prompt packs, games, players,
--       rounds, hands, submissions, votes, reports, blocks)
--    3. Triggers (auto profile on sign-up, updated_at)
--    4. Row Level Security — clients can only READ their own game data;
--       every WRITE goes through a SECURITY DEFINER function below, so the
--       server is the single source of truth for judge, prompt, timer,
--       submissions, scores and round number.
--    5. Game engine RPCs (create_game, join_game, start_game, submit_photo,
--       pick_winner, cast_vote, advance_game, restart_game, ...)
--    6. Account, moderation & maintenance RPCs (delete_my_account,
--       report_content, block_user, cleanup_expired_games)
--    7. Realtime publication + storage bucket + privileges
--    8. Seed data (prompt packs, prompts, starter photo library)
--
--  After running it, also enable in the Dashboard:
--    • Authentication → Providers → Anonymous sign-ins → ON
--      (the app plays as accountless guests)
--    • Database → Replication → make sure "games" is in supabase_realtime
--      (this file adds it, the toggle just confirms it)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Enums
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'game_status') then
    create type public.game_status as enum ('lobby', 'playing', 'finished');
  end if;
  if not exists (select 1 from pg_type where typname = 'game_mode') then
    create type public.game_mode as enum ('classic', 'vote', 'rapid');
  end if;
  if not exists (select 1 from pg_type where typname = 'game_phase') then
    create type public.game_phase as enum ('lobby', 'choosing', 'judging', 'round_results', 'game_over');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- One row per auth user (guests included). Keeps the last used display name.
create table if not exists public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  email         text,
  display_name  text,
  avatar_url    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Words that are not allowed inside usernames or custom prompts.
create table if not exists public.banned_words (
  word text primary key
);

-- Curated photo library. Replace / extend the seed rows with your own
-- images (Supabase Storage bucket "photos" is created further down).
create table if not exists public.photos (
  id            uuid primary key default gen_random_uuid(),
  image_url     text not null,
  thumbnail_url text,
  category      text not null default 'general',
  credit        text,
  approved      boolean not null default true,
  created_at    timestamptz not null default now()
);
create unique index if not exists photos_image_url_idx on public.photos (image_url);
create index if not exists photos_approved_idx on public.photos (approved);

create table if not exists public.prompt_packs (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  description text,
  is_default  boolean not null default false,
  sort_order  int not null default 0,
  approved    boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.prompts (
  id         uuid primary key default gen_random_uuid(),
  pack_id    uuid not null references public.prompt_packs (id) on delete cascade,
  text       text not null,
  category   text not null default 'random',
  approved   boolean not null default true,
  created_at timestamptz not null default now(),
  unique (pack_id, text)
);

create table if not exists public.games (
  id                      uuid primary key default gen_random_uuid(),
  room_code               text not null,
  host_id                 uuid not null references auth.users (id) on delete cascade,
  status                  public.game_status not null default 'lobby',
  phase                   public.game_phase  not null default 'lobby',
  mode                    public.game_mode   not null default 'classic',
  is_public               boolean not null default false,
  max_players             int not null default 8  check (max_players between 3 and 12),
  max_rounds              int not null default 8  check (max_rounds between 1 and 30),
  target_score            int not null default 5  check (target_score between 1 and 30),
  round_timer_seconds     int not null default 60 check (round_timer_seconds between 10 and 300),
  judge_timer_seconds     int not null default 45 check (judge_timer_seconds between 10 and 300),
  results_seconds         int not null default 9  check (results_seconds between 3 and 60),
  hand_size               int not null default 16 check (hand_size between 4 and 16),
  refreshes_per_player    int not null default 2  check (refreshes_per_player between 0 and 10),
  current_round           int not null default 0,
  current_judge_player_id uuid,
  winner_player_id        uuid,
  phase_ends_at           timestamptz,
  version                 bigint not null default 0,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  started_at              timestamptz,
  finished_at             timestamptz,
  expires_at              timestamptz not null default now() + interval '12 hours'
);
-- Room codes only need to be unique among games that are still alive.
create unique index if not exists games_room_code_active_idx
  on public.games (room_code) where status <> 'finished';
create index if not exists games_public_lobby_idx on public.games (is_public, status, created_at desc);

create table if not exists public.players (
  id             uuid primary key default gen_random_uuid(),
  game_id        uuid not null references public.games (id) on delete cascade,
  user_id        uuid not null references auth.users (id) on delete cascade,
  username       text not null,
  score          int not null default 0,
  is_ready       boolean not null default false,
  is_host        boolean not null default false,
  is_connected   boolean not null default true,
  refreshes_used int not null default 0,
  joined_at      timestamptz not null default now(),
  left_at        timestamptz,
  unique (game_id, user_id)
);
create index if not exists players_user_idx on public.players (user_id);
create index if not exists players_game_idx on public.players (game_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'games_current_judge_fk') then
    alter table public.games
      add constraint games_current_judge_fk
      foreign key (current_judge_player_id) references public.players (id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'games_winner_fk') then
    alter table public.games
      add constraint games_winner_fk
      foreign key (winner_player_id) references public.players (id) on delete set null;
  end if;
end $$;

create table if not exists public.game_prompt_packs (
  game_id uuid not null references public.games (id) on delete cascade,
  pack_id uuid not null references public.prompt_packs (id) on delete cascade,
  primary key (game_id, pack_id)
);

create table if not exists public.game_custom_prompts (
  id         uuid primary key default gen_random_uuid(),
  game_id    uuid not null references public.games (id) on delete cascade,
  text       text not null,
  used       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists game_custom_prompts_game_idx on public.game_custom_prompts (game_id);

create table if not exists public.rounds (
  id                   uuid primary key default gen_random_uuid(),
  game_id              uuid not null references public.games (id) on delete cascade,
  round_number         int not null,
  judge_player_id      uuid references public.players (id) on delete set null,
  prompt_id            uuid references public.prompts (id) on delete set null,
  custom_prompt_id     uuid references public.game_custom_prompts (id) on delete set null,
  prompt_text          text not null,
  winner_submission_id uuid,
  started_at           timestamptz not null default now(),
  ended_at             timestamptz,
  unique (game_id, round_number)
);

-- A player's current hand. Rows are removed when a photo is submitted and
-- topped back up to hand_size at the start of every round.
create table if not exists public.hands (
  id        uuid primary key default gen_random_uuid(),
  game_id   uuid not null references public.games (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  photo_id  uuid not null references public.photos (id) on delete cascade,
  position  int not null,
  dealt_at  timestamptz not null default now(),
  unique (player_id, photo_id)
);
create index if not exists hands_player_idx on public.hands (player_id);

-- Every photo a player has been dealt in a game, so hands don't repeat.
create table if not exists public.player_photo_history (
  player_id uuid not null references public.players (id) on delete cascade,
  photo_id  uuid not null references public.photos (id) on delete cascade,
  primary key (player_id, photo_id)
);

create table if not exists public.submissions (
  id           uuid primary key default gen_random_uuid(),
  game_id      uuid not null references public.games (id) on delete cascade,
  round_id     uuid not null references public.rounds (id) on delete cascade,
  player_id    uuid not null references public.players (id) on delete cascade,
  photo_id     uuid not null references public.photos (id) on delete cascade,
  is_winner    boolean not null default false,
  submitted_at timestamptz not null default now(),
  unique (round_id, player_id)
);
create index if not exists submissions_round_idx on public.submissions (round_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rounds_winner_submission_fk') then
    alter table public.rounds
      add constraint rounds_winner_submission_fk
      foreign key (winner_submission_id) references public.submissions (id) on delete set null;
  end if;
end $$;

create table if not exists public.votes (
  id              uuid primary key default gen_random_uuid(),
  round_id        uuid not null references public.rounds (id) on delete cascade,
  voter_player_id uuid not null references public.players (id) on delete cascade,
  submission_id   uuid not null references public.submissions (id) on delete cascade,
  created_at      timestamptz not null default now(),
  unique (round_id, voter_player_id)
);

-- User reports (photos, usernames, custom prompts). Review them in the
-- Dashboard table editor; nothing is auto-actioned.
create table if not exists public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references auth.users (id) on delete cascade,
  game_id          uuid references public.games (id) on delete set null,
  reported_user_id uuid references auth.users (id) on delete set null,
  photo_id         uuid references public.photos (id) on delete set null,
  reason           text not null,
  details          text,
  status           text not null default 'open',
  created_at       timestamptz not null default now()
);

create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- ---------------------------------------------------------------------
-- 3. Triggers
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Every new auth user (anonymous guests included) gets a profile row.
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
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------------------
-- Helper predicates run as the function owner so policies can look at
-- "players" without recursing into their own policy.
create or replace function public.is_game_member(p_game_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.players p
    where p.game_id = p_game_id and p.user_id = auth.uid()
  );
$$;

create or replace function public.is_my_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.players p
    where p.id = p_player_id and p.user_id = auth.uid()
  );
$$;

alter table public.profiles             enable row level security;
alter table public.banned_words         enable row level security;
alter table public.photos               enable row level security;
alter table public.prompt_packs         enable row level security;
alter table public.prompts              enable row level security;
alter table public.games                enable row level security;
alter table public.players              enable row level security;
alter table public.game_prompt_packs    enable row level security;
alter table public.game_custom_prompts  enable row level security;
alter table public.rounds               enable row level security;
alter table public.hands                enable row level security;
alter table public.player_photo_history enable row level security;
alter table public.submissions          enable row level security;
alter table public.votes                enable row level security;
alter table public.reports              enable row level security;
alter table public.blocked_users        enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

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
    host_id = auth.uid()
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
  for select to authenticated using (reporter_id = auth.uid());
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert to authenticated with check (reporter_id = auth.uid());

drop policy if exists blocked_users_select_own on public.blocked_users;
create policy blocked_users_select_own on public.blocked_users
  for select to authenticated using (blocker_id = auth.uid());
drop policy if exists blocked_users_insert_own on public.blocked_users;
create policy blocked_users_insert_own on public.blocked_users
  for insert to authenticated with check (blocker_id = auth.uid());
drop policy if exists blocked_users_delete_own on public.blocked_users;
create policy blocked_users_delete_own on public.blocked_users
  for delete to authenticated using (blocker_id = auth.uid());

-- banned_words and player_photo_history: RLS on, no policies → server only.

-- ---------------------------------------------------------------------
-- 5. Game engine
-- ---------------------------------------------------------------------
-- Naming: functions starting with "_" are internal (no client execute
-- privilege). Everything else is a public RPC callable with
-- supabase.rpc("name", params: ...). All public RPCs return jsonb.
-- Errors are raised with human readable messages; the app shows them.

create or replace function public._require_uid()
returns uuid
language plpgsql
stable
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'You need to be signed in.';
  end if;
  return v_uid;
end $$;

-- Bumps games.version so Realtime listeners refetch the state.
create or replace function public._touch_game(p_game_id uuid)
returns void
language sql
as $$
  update public.games
  set version = version + 1, updated_at = now()
  where id = p_game_id;
$$;

create or replace function public._generate_room_code()
returns text
language plpgsql
as $$
declare
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_i int;
begin
  loop
    v_code := '';
    for v_i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (
      select 1 from public.games g where g.room_code = v_code and g.status <> 'finished'
    );
  end loop;
  return v_code;
end $$;

create or replace function public._contains_banned_word(p_text text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.banned_words b
    where lower(coalesce(p_text, '')) like '%' || b.word || '%'
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
  v_name := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  if length(v_name) < 1 then
    raise exception 'Please enter a name first.';
  end if;
  if length(v_name) > 20 then
    v_name := left(v_name, 20);
  end if;
  if public._contains_banned_word(v_name) then
    raise exception 'That name is not allowed. Please pick another one.';
  end if;
  return v_name;
end $$;

-- Makes a username unique inside one room ("Sam", "Sam 2", "Sam 3").
create or replace function public._unique_username(p_game_id uuid, p_name text)
returns text
language plpgsql
stable
as $$
declare
  v_candidate text := p_name;
  v_n int := 2;
begin
  while exists (
    select 1 from public.players p
    where p.game_id = p_game_id and p.left_at is null and lower(p.username) = lower(v_candidate)
  ) loop
    v_candidate := left(p_name, 17) || ' ' || v_n;
    v_n := v_n + 1;
  end loop;
  return v_candidate;
end $$;

-- ---- Game state snapshot --------------------------------------------
-- Everything a client needs to render any screen. Submissions are only
-- included once judging starts, and their owners only once the round is
-- over, which keeps the reveal anonymous.
create or replace function public.get_game_state(p_game_id uuid)
returns jsonb
language plpgsql
stable
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
    'highlights',  v_highlights
  );
end $$;

-- ---- Hands -------------------------------------------------------------
create or replace function public._fill_hand(p_game_id uuid, p_player_id uuid)
returns void
language plpgsql
as $$
declare
  v_size    int;
  v_have    int;
  v_pos     int;
  v_need    int;
  v_added   int;
  v_attempt int := 0;
begin
  select hand_size into v_size from public.games where id = p_game_id;

  loop
    v_attempt := v_attempt + 1;

    select count(*), coalesce(max(position), 0)
    into v_have, v_pos
    from public.hands where player_id = p_player_id;

    v_need := v_size - v_have;
    exit when v_need <= 0 or v_attempt > 2;

    with picked as (
      select ph.id
      from public.photos ph
      where ph.approved
        and not exists (select 1 from public.player_photo_history h
                        where h.player_id = p_player_id and h.photo_id = ph.id)
        and not exists (select 1 from public.hands hd
                        where hd.player_id = p_player_id and hd.photo_id = ph.id)
      order by random()
      limit v_need
    ),
    inserted as (
      insert into public.hands (game_id, player_id, photo_id, position)
      select p_game_id, p_player_id, picked.id, v_pos + row_number() over ()
      from picked
      returning photo_id
    )
    insert into public.player_photo_history (player_id, photo_id)
    select p_player_id, photo_id from inserted
    on conflict do nothing;

    get diagnostics v_added = row_count;

    -- Pool exhausted: forget what this player has already seen (except the
    -- photos still in their hand) and deal again.
    if v_added < v_need then
      delete from public.player_photo_history h
      where h.player_id = p_player_id
        and not exists (select 1 from public.hands hd
                        where hd.player_id = p_player_id and hd.photo_id = h.photo_id);
    end if;
  end loop;
end $$;

create or replace function public._fill_hands(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  p record;
begin
  for p in select id from public.players where game_id = p_game_id and left_at is null loop
    perform public._fill_hand(p_game_id, p.id);
  end loop;
end $$;

-- ---- Round lifecycle -----------------------------------------------
create or replace function public._finish_game(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  v_winner uuid;
begin
  select p.id into v_winner
  from public.players p
  where p.game_id = p_game_id and p.left_at is null
  order by p.score desc, p.joined_at asc
  limit 1;

  update public.games
  set status = 'finished',
      phase = 'game_over',
      winner_player_id = v_winner,
      phase_ends_at = null,
      finished_at = now(),
      expires_at = now() + interval '2 hours'
  where id = p_game_id;

  perform public._touch_game(p_game_id);
end $$;

create or replace function public._start_round(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g              public.games%rowtype;
  v_round        int;
  v_judge        uuid;
  v_player_count int;
  v_prompt_id    uuid;
  v_custom_id    uuid;
  v_prompt_text  text;
begin
  select * into g from public.games where id = p_game_id for update;
  v_round := g.current_round + 1;

  select count(*) into v_player_count
  from public.players where game_id = g.id and left_at is null;
  if v_player_count < 3 then
    perform public._finish_game(g.id);
    return;
  end if;

  -- Judge rotates through players in join order (vote mode has no judge).
  if g.mode <> 'vote' then
    select p.id into v_judge
    from public.players p
    where p.game_id = g.id and p.left_at is null
    order by p.joined_at
    offset ((v_round - 1) % v_player_count)
    limit 1;
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

create or replace function public._end_round(p_game_id uuid, p_winner_submission_id uuid)
returns void
language plpgsql
as $$
declare
  g public.games%rowtype;
  r public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;

  if p_winner_submission_id is not null then
    update public.submissions set is_winner = true where id = p_winner_submission_id;
    update public.players
    set score = score + 1
    where id = (select player_id from public.submissions where id = p_winner_submission_id);
  end if;

  update public.rounds
  set winner_submission_id = p_winner_submission_id, ended_at = now()
  where id = r.id;

  update public.games
  set phase = 'round_results',
      phase_ends_at = now() + make_interval(secs => results_seconds)
  where id = g.id;

  perform public._touch_game(g.id);
end $$;

create or replace function public._random_submission(p_round_id uuid)
returns uuid
language sql
stable
as $$
  select s.id from public.submissions s where s.round_id = p_round_id order by random() limit 1;
$$;

create or replace function public._resolve_votes(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g        public.games%rowtype;
  r        public.rounds%rowtype;
  v_winner uuid;
begin
  select * into g from public.games where id = p_game_id for update;
  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;

  select s.id into v_winner
  from public.submissions s
  left join public.votes v on v.submission_id = s.id
  where s.round_id = r.id
  group by s.id, s.submitted_at
  order by count(v.id) desc, s.submitted_at asc
  limit 1;

  perform public._end_round(g.id, v_winner);
end $$;

create or replace function public._to_judging(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g            public.games%rowtype;
  r            public.rounds%rowtype;
  v_count      int;
  v_judge_here boolean;
begin
  select * into g from public.games where id = p_game_id for update;
  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;

  select count(*) into v_count from public.submissions where round_id = r.id;

  if v_count = 0 then
    perform public._end_round(g.id, null);
    return;
  end if;

  if g.mode = 'vote' then
    if v_count = 1 then
      perform public._end_round(g.id, public._random_submission(r.id));
    else
      update public.games
      set phase = 'judging',
          phase_ends_at = now() + make_interval(secs => judge_timer_seconds)
      where id = g.id;
      perform public._touch_game(g.id);
    end if;
    return;
  end if;

  select exists (
    select 1 from public.players p
    where p.id = g.current_judge_player_id and p.left_at is null and p.is_connected
  ) into v_judge_here;

  if not v_judge_here then
    -- Judge is gone: the round is decided at random so the game keeps moving.
    perform public._end_round(g.id, public._random_submission(r.id));
    return;
  end if;

  update public.games
  set phase = 'judging',
      phase_ends_at = now() + make_interval(secs => judge_timer_seconds)
  where id = g.id;
  perform public._touch_game(g.id);
end $$;

create or replace function public._next_round(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g           public.games%rowtype;
  v_top       int;
  v_connected int;
begin
  select * into g from public.games where id = p_game_id for update;

  select coalesce(max(score), 0), count(*) into v_top, v_connected
  from public.players where game_id = g.id and left_at is null;

  if v_top >= g.target_score or g.current_round >= g.max_rounds or v_connected < 3 then
    perform public._finish_game(g.id);
  else
    perform public._start_round(g.id);
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
  v_pending   int;
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

  if g.status = 'finished' then
    update public.players set left_at = now(), is_connected = false where id = me.id;
    perform public._touch_game(g.id);
    return;
  end if;

  -- status = playing
  update public.players
  set left_at = now(), is_connected = false, is_ready = false
  where id = me.id;

  select count(*) into v_connected
  from public.players where game_id = g.id and left_at is null;

  if me.is_host and v_connected > 0 then
    select * into v_new_host from public.players
    where game_id = g.id and left_at is null
    order by joined_at limit 1;
    update public.players set is_host = true where id = v_new_host.id;
    update public.games set host_id = v_new_host.user_id where id = g.id;
  end if;

  if v_connected < 3 then
    perform public._finish_game(g.id);
    return;
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;

  if g.phase = 'judging' then
    if g.mode = 'vote' then
      select count(*) into v_pending
      from public.players p
      where p.game_id = g.id and p.left_at is null
        and not exists (select 1 from public.votes v where v.round_id = r.id and v.voter_player_id = p.id);
      if v_pending = 0 then
        perform public._resolve_votes(g.id);
        return;
      end if;
    elsif g.current_judge_player_id = me.id then
      perform public._end_round(g.id, public._random_submission(r.id));
      return;
    end if;
  elsif g.phase = 'choosing' then
    select count(*) into v_pending
    from public.players p
    where p.game_id = g.id and p.left_at is null
      and p.id is distinct from g.current_judge_player_id
      and not exists (select 1 from public.submissions s where s.round_id = r.id and s.player_id = p.id);
    if v_pending = 0 then
      perform public._to_judging(g.id);
      return;
    end if;
  end if;

  perform public._touch_game(g.id);
end $$;

create or replace function public._leave_all_active_games(p_uid uuid)
returns void
language plpgsql
as $$
declare
  p record;
begin
  for p in
    select pl.id, pl.game_id
    from public.players pl
    join public.games g on g.id = pl.game_id
    where pl.user_id = p_uid and pl.left_at is null and g.status <> 'finished'
  loop
    perform public._player_leaves(p.game_id, p.id);
  end loop;
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
    where pp.slug = any (p_pack_slugs) and pp.approved
    on conflict do nothing;
  end if;
  if not exists (select 1 from public.game_prompt_packs where game_id = p_game_id) then
    insert into public.game_prompt_packs (game_id, pack_id)
    select p_game_id, pp.id from public.prompt_packs pp where pp.is_default and pp.approved
    on conflict do nothing;
  end if;

  delete from public.game_custom_prompts where game_id = p_game_id;
  if p_custom_prompts is not null then
    foreach v_prompt in array p_custom_prompts loop
      v_prompt := btrim(regexp_replace(coalesce(v_prompt, ''), '\s+', ' ', 'g'));
      if length(v_prompt) between 3 and 140 and not public._contains_banned_word(v_prompt) then
        insert into public.game_custom_prompts (game_id, text) values (p_game_id, v_prompt);
      end if;
    end loop;
  end if;
end $$;

-- ---- Public RPCs -------------------------------------------------------
create or replace function public.create_game(
  p_username            text,
  p_mode                public.game_mode default 'classic',
  p_is_public           boolean default false,
  p_max_players         int default 8,
  p_max_rounds          int default 8,
  p_target_score        int default 5,
  p_round_timer_seconds int default 60,
  p_pack_slugs          text[] default null,
  p_custom_prompts      text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := public._require_uid();
  v_name    text := public._clean_username(p_username);
  v_game_id uuid;
begin
  perform public._leave_all_active_games(v_uid);

  insert into public.games (room_code, host_id)
  values (public._generate_room_code(), v_uid)
  returning id into v_game_id;

  insert into public.players (game_id, user_id, username, is_host, is_ready)
  values (v_game_id, v_uid, v_name, true, true);

  perform public._apply_game_settings(
    v_game_id, p_mode, p_is_public, p_max_players, p_max_rounds,
    p_target_score, p_round_timer_seconds, p_pack_slugs, p_custom_prompts
  );

  update public.profiles set display_name = v_name where id = v_uid;

  perform public._touch_game(v_game_id);
  return public.get_game_state(v_game_id);
end $$;

create or replace function public.update_game_settings(
  p_game_id             uuid,
  p_mode                public.game_mode default 'classic',
  p_is_public           boolean default false,
  p_max_players         int default 8,
  p_max_rounds          int default 8,
  p_target_score        int default 5,
  p_round_timer_seconds int default 60,
  p_pack_slugs          text[] default null,
  p_custom_prompts      text[] default null
)
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
  if g.host_id <> v_uid then raise exception 'Only the host can change the settings.'; end if;
  if g.status <> 'lobby' then raise exception 'Settings can only be changed in the lobby.'; end if;

  perform public._apply_game_settings(
    g.id, p_mode, p_is_public, p_max_players, p_max_rounds,
    p_target_score, p_round_timer_seconds, p_pack_slugs, p_custom_prompts
  );
  perform public._touch_game(g.id);
  return public.get_game_state(g.id);
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
      -- Rejoin a game in progress.
      update public.players
      set left_at = null, is_connected = true
      where id = me.id;
      perform public._touch_game(g.id);
    end if;
    return public.get_game_state(g.id);
  end if;

  if g.status <> 'lobby' then
    raise exception 'This game has already started.';
  end if;
  if exists (select 1 from public.blocked_users b where b.blocker_id = g.host_id and b.blocked_id = v_uid) then
    raise exception 'You can''t join this room.';
  end if;
  if exists (select 1 from public.blocked_users b where b.blocker_id = v_uid and b.blocked_id = g.host_id) then
    raise exception 'You have blocked the host of this room.';
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
create or replace function public.get_my_active_game()
returns jsonb
language plpgsql
stable
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

create or replace function public.leave_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
  me    public.players%rowtype;
begin
  select * into me from public.players where game_id = p_game_id and user_id = v_uid;
  if found then
    perform public._player_leaves(p_game_id, me.id);
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.set_ready(p_game_id uuid, p_ready boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
begin
  update public.players
  set is_ready = coalesce(p_ready, true)
  where game_id = p_game_id and user_id = v_uid and left_at is null;
  if not found then raise exception 'You are not in this game.'; end if;
  perform public._touch_game(p_game_id);
  return public.get_game_state(p_game_id);
end $$;

create or replace function public.start_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := public._require_uid();
  g       public.games%rowtype;
  v_count int;
  v_photos int;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if g.host_id <> v_uid then raise exception 'Only the host can start the game.'; end if;
  if g.status <> 'lobby' then raise exception 'This game has already started.'; end if;

  select count(*) into v_count from public.players where game_id = g.id and left_at is null;
  if v_count < 3 then raise exception 'You need at least 3 players to start.'; end if;

  select count(*) into v_photos from public.photos where approved;
  if v_photos < g.hand_size then raise exception 'The photo library is empty. Add photos first.'; end if;

  update public.games
  set status = 'playing', started_at = now(), expires_at = now() + interval '6 hours'
  where id = g.id;

  perform public._start_round(g.id);
  return public.get_game_state(g.id);
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
  v_pending int;
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

  select count(*) into v_pending
  from public.players p
  where p.game_id = g.id and p.left_at is null
    and p.id is distinct from g.current_judge_player_id
    and not exists (select 1 from public.submissions s where s.round_id = r.id and s.player_id = p.id);

  if v_pending = 0 then
    perform public._to_judging(g.id);
  else
    perform public._touch_game(g.id);
  end if;

  return public.get_game_state(g.id);
end $$;

create or replace function public.refresh_hand(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
  g     public.games%rowtype;
  me    public.players%rowtype;
  r     public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if g.status <> 'playing' or g.phase <> 'choosing' then
    raise exception 'You can only refresh your hand while choosing a photo.';
  end if;

  select * into me from public.players where game_id = g.id and user_id = v_uid and left_at is null;
  if not found then raise exception 'You are not in this game.'; end if;
  if me.refreshes_used >= g.refreshes_per_player then
    raise exception 'No refreshes left this game.';
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;
  if exists (select 1 from public.submissions s where s.round_id = r.id and s.player_id = me.id) then
    raise exception 'You already submitted a photo this round.';
  end if;

  delete from public.hands where player_id = me.id;
  update public.players set refreshes_used = refreshes_used + 1 where id = me.id;
  perform public._fill_hand(g.id, me.id);

  perform public._touch_game(g.id);
  return public.get_game_state(g.id);
end $$;

create or replace function public.pick_winner(p_game_id uuid, p_submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
  g     public.games%rowtype;
  me    public.players%rowtype;
  r     public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if g.status <> 'playing' or g.phase <> 'judging' then
    raise exception 'It''s not time to pick a winner.';
  end if;
  if g.mode = 'vote' then
    raise exception 'This game uses voting instead of a judge.';
  end if;

  select * into me from public.players where game_id = g.id and user_id = v_uid and left_at is null;
  if not found then raise exception 'You are not in this game.'; end if;
  if me.id is distinct from g.current_judge_player_id then
    raise exception 'Only the judge can pick the winner.';
  end if;

  select * into r from public.rounds where game_id = g.id and round_number = g.current_round;
  if not exists (select 1 from public.submissions s where s.id = p_submission_id and s.round_id = r.id) then
    raise exception 'That photo isn''t part of this round.';
  end if;

  perform public._end_round(g.id, p_submission_id);
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
  v_pending int;
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

  select count(*) into v_pending
  from public.players p
  where p.game_id = g.id and p.left_at is null
    and not exists (select 1 from public.votes v where v.round_id = r.id and v.voter_player_id = p.id);

  if v_pending = 0 then
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
  r     public.rounds%rowtype;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then raise exception 'Game not found.'; end if;
  if not exists (select 1 from public.players p where p.game_id = g.id and p.user_id = v_uid) then
    raise exception 'You are not in this game.';
  end if;

  if g.status = 'playing' and g.phase_ends_at is not null and g.phase_ends_at <= now() then
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
  end if;

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
  update public.players set score = 0, refreshes_used = 0, is_ready = is_host, is_connected = true
  where game_id = g.id;
  update public.game_custom_prompts set used = false where game_id = g.id;

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

-- Browse open public lobbies.
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
    select coalesce(jsonb_agg(jsonb_build_object(
        'id',            g.id,
        'room_code',     g.room_code,
        'mode',          g.mode,
        'max_players',   g.max_players,
        'player_count',  (select count(*) from public.players p where p.game_id = g.id and p.left_at is null),
        'host_username', (select p.username from public.players p where p.game_id = g.id and p.is_host limit 1),
        'created_at',    g.created_at
      ) order by g.created_at desc), '[]'::jsonb)
    from public.games g
    where g.is_public
      and g.status = 'lobby'
      and g.expires_at > now()
      and (select count(*) from public.players p where p.game_id = g.id and p.left_at is null) < g.max_players
      and not exists (select 1 from public.blocked_users b
                      where (b.blocker_id = g.host_id and b.blocked_id = v_uid)
                         or (b.blocker_id = v_uid and b.blocked_id = g.host_id))
    limit 50
  );
end $$;

create or replace function public.list_prompt_packs()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'slug',         pp.slug,
      'name',         pp.name,
      'description',  pp.description,
      'is_default',   pp.is_default,
      'prompt_count', (select count(*) from public.prompts p where p.pack_id = pp.id and p.approved)
    ) order by pp.sort_order, pp.name), '[]'::jsonb)
  from public.prompt_packs pp
  where pp.approved;
$$;

create or replace function public.list_prompts(p_pack_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('text', p.text, 'category', p.category) order by p.text), '[]'::jsonb)
  from public.prompts p
  join public.prompt_packs pp on pp.id = p.pack_id
  where pp.slug = p_pack_slug and p.approved and pp.approved;
$$;

-- ---------------------------------------------------------------------
-- 6. Account, moderation & maintenance
-- ---------------------------------------------------------------------

-- In-app account deletion (App Store Review Guideline 5.1.1(v)).
-- Removes the auth user; every table above cascades from auth.users, so
-- the profile, players, submissions, votes, reports and blocks go too.
create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
begin
  perform public._leave_all_active_games(v_uid);
  delete from public.games where host_id = v_uid and status <> 'playing';
  delete from auth.users where id = v_uid;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.update_display_name(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := public._require_uid();
  v_name text := public._clean_username(p_name);
begin
  insert into public.profiles (id, display_name) values (v_uid, v_name)
  on conflict (id) do update set display_name = excluded.display_name;
  return jsonb_build_object('display_name', v_name);
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
  insert into public.reports (reporter_id, game_id, reported_user_id, photo_id, reason, details)
  values (v_uid, p_game_id, p_reported_user_id, p_photo_id, left(btrim(p_reason), 80), left(p_details, 1000));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.block_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
begin
  if p_user_id is null or p_user_id = v_uid then
    raise exception 'You can''t block yourself.';
  end if;
  insert into public.blocked_users (blocker_id, blocked_id) values (v_uid, p_user_id)
  on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.unblock_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public._require_uid();
begin
  delete from public.blocked_users where blocker_id = v_uid and blocked_id = p_user_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.list_blocked_users()
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
    select coalesce(jsonb_agg(jsonb_build_object(
        'user_id',    b.blocked_id,
        'username',   coalesce(pr.display_name, 'Player'),
        'blocked_at', b.created_at
      ) order by b.created_at desc), '[]'::jsonb)
    from public.blocked_users b
    left join public.profiles pr on pr.id = b.blocked_id
    where b.blocker_id = v_uid
  );
end $$;

-- Removes stale rooms. Scheduled with pg_cron below when the extension is
-- available; safe to call by hand from the SQL editor as well.
create or replace function public.cleanup_expired_games()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  delete from public.games
  where expires_at < now()
     or (status = 'finished' and finished_at < now() - interval '2 hours');
  get diagnostics v_deleted = row_count;
  return v_deleted;
end $$;

do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron not available (%): schedule cleanup_expired_games() manually if you want it.', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'photocards_cleanup_expired_games') then
      perform cron.schedule('photocards_cleanup_expired_games', '*/30 * * * *', 'select public.cleanup_expired_games();');
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7. Realtime, storage, privileges
-- ---------------------------------------------------------------------

-- Clients subscribe to UPDATEs on their game row (games.version changes on
-- every state transition) and refetch get_game_state().
alter table public.games replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'games'
  ) then
    alter publication supabase_realtime add table public.games;
  end if;
end $$;

-- Public bucket for your own curated photo library. Upload images there
-- and insert rows into public.photos pointing at their public URLs.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public)
    values ('photos', 'photos', true)
    on conflict (id) do nothing;

    begin
      drop policy if exists "photos_bucket_public_read" on storage.objects;
      create policy "photos_bucket_public_read" on storage.objects
        for select using (bucket_id = 'photos');
    exception when others then
      raise notice 'Could not create storage policy (%). Add a public read policy for bucket "photos" in the dashboard.', sqlerrm;
    end;
  end if;
end $$;

-- Table privileges: signed-in users can read (RLS filters rows); nobody
-- writes game tables directly; anonymous (not signed in) gets nothing.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
grant usage on schema public to authenticated;
grant select on
  public.profiles, public.photos, public.prompt_packs, public.prompts, public.games,
  public.players, public.game_prompt_packs, public.game_custom_prompts, public.rounds,
  public.hands, public.submissions, public.votes, public.reports, public.blocked_users
to authenticated;
grant insert, update on public.profiles to authenticated;
grant insert on public.reports to authenticated;
grant insert, delete on public.blocked_users to authenticated;
revoke all on public.banned_words, public.player_photo_history from authenticated;

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
    if f.name in ('handle_new_user', 'set_updated_at') then
      execute format('grant execute on function %s to supabase_auth_admin, authenticated, service_role', f.signature);
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

-- ---------------------------------------------------------------------
-- 8. Seed data
-- ---------------------------------------------------------------------

-- Username / custom prompt filter (lowercase substrings). Extend freely.
insert into public.banned_words (word) values
  ('fuck'), ('shit'), ('bitch'), ('cunt'), ('nigg'), ('fagg'), ('retard'),
  ('nazi'), ('hitler'), ('kys'), ('rape'), ('whore'), ('slut'), ('porn')
on conflict do nothing;

-- Prompt packs -----------------------------------------------------------
insert into public.prompt_packs (slug, name, description, is_default, sort_order) values
  ('party-mix',   'Party Mix',        'A little bit of everything. The default pack.',        true,  0),
  ('school',      'School Life',      'Group projects, pop quizzes and hallway drama.',       false, 1),
  ('reactions',   'Reactions',        '"My face when…" and other big feelings.',              false, 2),
  ('internet',    'Internet Culture', 'Group chats, memes and main-character energy.',        false, 3),
  ('pov',         'POV',              'Point-of-view prompts. You are the main character.',   false, 4),
  ('awkward',     'Awkward Moments',  'Cringe, mild disasters and things that did not go to plan.', false, 5)
on conflict (slug) do update
  set name = excluded.name,
      description = excluded.description,
      is_default = excluded.is_default,
      sort_order = excluded.sort_order;

insert into public.prompts (pack_id, text, category)
select pp.id, v.text, v.category
from (values
  -- Party Mix
  ('party-mix', 'This is what success looks like', 'random'),
  ('party-mix', 'The last thing you see before disaster', 'situations'),
  ('party-mix', 'Explain Monday using one image', 'random'),
  ('party-mix', 'My face when someone says "trust me"', 'reactions'),
  ('party-mix', 'When the group project is due tomorrow', 'school'),
  ('party-mix', 'This person definitely knows something we don''t', 'random'),
  ('party-mix', 'The vibe of this weekend', 'random'),
  ('party-mix', 'My energy at 7am', 'reactions'),
  ('party-mix', 'My energy at 11pm', 'reactions'),
  ('party-mix', 'Me pretending to listen', 'reactions'),
  ('party-mix', 'The most expensive mistake', 'situations'),
  ('party-mix', 'What my brain does at 3am', 'random'),
  ('party-mix', 'The plot twist nobody saw coming', 'random'),
  ('party-mix', 'How it feels to find money in an old jacket', 'reactions'),
  ('party-mix', 'The real reason I''m late', 'situations'),
  ('party-mix', 'My last two brain cells', 'random'),
  ('party-mix', 'Me after one compliment', 'reactions'),
  ('party-mix', 'The best day of my life', 'random'),
  ('party-mix', 'A perfectly normal Tuesday', 'random'),
  ('party-mix', 'What I think I look like dancing', 'random'),
  ('party-mix', 'What I actually look like dancing', 'random'),
  ('party-mix', 'This is the "one more episode" feeling', 'reactions'),
  ('party-mix', 'Me when the food arrives', 'reactions'),
  ('party-mix', 'The most dramatic exit', 'situations'),
  ('party-mix', 'This photo is my weekend plans', 'random'),
  ('party-mix', 'The face I make when the WiFi drops', 'reactions'),
  ('party-mix', 'Peak adulting', 'random'),
  ('party-mix', 'My relationship with my alarm clock', 'random'),
  ('party-mix', 'A villain origin story', 'random'),
  ('party-mix', 'How it started', 'random'),
  ('party-mix', 'How it''s going', 'random'),
  ('party-mix', 'Me trying to save money', 'situations'),
  ('party-mix', 'This could be an album cover', 'random'),
  ('party-mix', 'What "I''m fine" actually looks like', 'reactions'),
  ('party-mix', 'The first day of vacation', 'random'),
  ('party-mix', 'The last day of vacation', 'random'),
  ('party-mix', 'My spirit animal', 'animals'),
  ('party-mix', 'The most chaotic road trip', 'situations'),
  ('party-mix', 'A picture that says "I have a plan"', 'random'),
  ('party-mix', 'A picture that says "I do not have a plan"', 'random'),
  -- School Life
  ('school', 'My reaction when the teacher says this is graded', 'school'),
  ('school', 'When the group project is due tomorrow and nobody started', 'school'),
  ('school', 'Me during a pop quiz', 'school'),
  ('school', 'The one person who did the whole group project', 'school'),
  ('school', 'Cafeteria food, but make it fancy', 'school'),
  ('school', 'When the substitute teacher shows up', 'school'),
  ('school', 'Five minutes before the bell', 'school'),
  ('school', 'The first day back after summer', 'school'),
  ('school', 'Me explaining why my homework is late', 'school'),
  ('school', 'The teacher''s face when the class goes quiet', 'school'),
  ('school', 'What my notes look like by December', 'school'),
  ('school', 'Me finding out the test is today', 'school'),
  ('school', 'The class group chat at 11:59pm', 'school'),
  ('school', 'When the teacher says "pick a partner"', 'school'),
  ('school', 'Field trip energy', 'school'),
  -- Reactions
  ('reactions', 'My face when I hear my own voice on a recording', 'reactions'),
  ('reactions', 'When someone says "we need to talk"', 'reactions'),
  ('reactions', 'When the plans get cancelled and I''m secretly happy', 'reactions'),
  ('reactions', 'My reaction to a surprise party', 'reactions'),
  ('reactions', 'When my song comes on', 'reactions'),
  ('reactions', 'Me hearing a spoiler', 'reactions'),
  ('reactions', 'My face when the check arrives', 'reactions'),
  ('reactions', 'Me trying to keep a secret', 'reactions'),
  ('reactions', 'When someone takes the last slice', 'reactions'),
  ('reactions', 'Me winning an argument I was wrong about', 'reactions'),
  ('reactions', 'When the elevator door opens on the wrong floor', 'reactions'),
  ('reactions', 'When my phone hits 1%', 'reactions'),
  ('reactions', 'Hearing "surprise, we''re going hiking"', 'reactions'),
  ('reactions', 'Me realising it''s Sunday night', 'reactions'),
  ('reactions', 'When the GPS says "recalculating"', 'reactions'),
  -- Internet Culture
  ('internet', 'POV: you opened the wrong group chat', 'internet'),
  ('internet', 'Main character energy', 'internet'),
  ('internet', 'This is my "seen, no reply" face', 'internet'),
  ('internet', 'The comment section right now', 'internet'),
  ('internet', 'When the meme is too accurate', 'internet'),
  ('internet', 'My screen time report', 'internet'),
  ('internet', 'Me after reading one article: expert', 'internet'),
  ('internet', 'The friend who never checks the group chat', 'internet'),
  ('internet', 'Delete this immediately', 'internet'),
  ('internet', 'When someone replies with just "k"', 'internet'),
  ('internet', 'An influencer''s "candid" photo', 'internet'),
  ('internet', 'When the video buffers at the best part', 'internet'),
  ('internet', 'Me typing and deleting the same message', 'internet'),
  ('internet', 'This is what "I''ll be there in 5" looks like', 'internet'),
  ('internet', 'The plot of every reality show', 'internet'),
  -- POV
  ('pov', 'POV: you just realised you left the stove on', 'pov'),
  ('pov', 'POV: you''re the last one to arrive', 'pov'),
  ('pov', 'POV: you walked into the wrong classroom', 'pov'),
  ('pov', 'POV: the waiter says "enjoy your meal" and you say "you too"', 'pov'),
  ('pov', 'POV: you''re the designated driver', 'pov'),
  ('pov', 'POV: your alarm didn''t go off', 'pov'),
  ('pov', 'POV: it''s your turn to pick the movie', 'pov'),
  ('pov', 'POV: you''re hiding from your responsibilities', 'pov'),
  ('pov', 'POV: you found the perfect parking spot', 'pov'),
  ('pov', 'POV: someone says your name in a meeting', 'pov'),
  ('pov', 'POV: you''re the only one who read the instructions', 'pov'),
  ('pov', 'POV: the pizza is here', 'pov'),
  ('pov', 'POV: you have a big test tomorrow and it''s 2am', 'pov'),
  ('pov', 'POV: you''re on hold for the third hour', 'pov'),
  ('pov', 'POV: you accidentally liked a photo from 2014', 'pov'),
  -- Awkward Moments
  ('awkward', 'Waving back at someone who wasn''t waving at you', 'awkward'),
  ('awkward', 'Realising your mic was on the whole time', 'awkward'),
  ('awkward', 'Calling the teacher "mom"', 'awkward'),
  ('awkward', 'Pushing a door that says pull', 'awkward'),
  ('awkward', 'Laughing at the wrong moment', 'awkward'),
  ('awkward', 'Forgetting someone''s name mid-sentence', 'awkward'),
  ('awkward', 'The moment right after a bad joke', 'awkward'),
  ('awkward', 'Saying "you too" to the cinema ticket person', 'awkward'),
  ('awkward', 'Getting caught singing in the car', 'awkward'),
  ('awkward', 'Tripping and pretending it was on purpose', 'awkward'),
  ('awkward', 'The silence after "so… any questions?"', 'awkward'),
  ('awkward', 'Both walking the same way for way too long', 'awkward'),
  ('awkward', 'Texting the wrong person', 'awkward'),
  ('awkward', 'When the whole room turns to look at you', 'awkward'),
  ('awkward', 'Holding the door for someone slightly too far away', 'awkward')
) as v(slug, text, category)
join public.prompt_packs pp on pp.slug = v.slug
on conflict (pack_id, text) do nothing;

-- Starter photo library ---------------------------------------------------
-- Uses Lorem Picsum (free Unsplash-licensed photos) so the game is playable
-- immediately. Replace these with your own curated images by uploading
-- them to the "photos" bucket and inserting their public URLs here.
insert into public.photos (image_url, thumbnail_url, category, credit)
select
  format('https://picsum.photos/id/%s/800/800', i),
  format('https://picsum.photos/id/%s/300/300', i),
  'general',
  'Lorem Picsum / Unsplash'
from generate_series(1, 160) as i
where i not in (86, 97, 105, 138, 148, 150)
on conflict (image_url) do nothing;

-- ---------------------------------------------------------------------
-- Done. Quick self-check:
-- ---------------------------------------------------------------------
select
  (select count(*) from public.photos)       as photos,
  (select count(*) from public.prompt_packs) as prompt_packs,
  (select count(*) from public.prompts)      as prompts;
