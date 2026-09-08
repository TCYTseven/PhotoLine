# Supabase Setup Guide

**Time**: 5 min | **For**: the whole PhotoCards backend (database, auth, realtime, storage)

## 1. Create the project

1. [supabase.com](https://supabase.com) → **New project**
2. Pick a name, the region closest to your players, and a database password.
3. Wait for provisioning (~2 min).

## 2. Run the schema

1. **SQL Editor → New query**
2. Paste the entire contents of [`supabase/schema.sql`](../supabase/schema.sql)
3. **Run**. The last statement prints the seed counts (`photos`, `prompt_packs`, `prompts`).

The file is idempotent: running it again is safe (it uses `IF NOT EXISTS` / `CREATE OR REPLACE`).

## 3. Enable anonymous sign-ins

**Authentication → Providers → Anonymous sign-ins → ON**

Players are guests; the app creates an anonymous session on first launch. (Apple / Google sign-in code is still present in the `Authentication` framework but is not part of the game flow.)

## 4. Keys

**Project Settings → API**: copy the **Project URL** and **anon public key** into `Src/Features/Common/Common/Configuration/AppConfiguration.swift` (`Supabase.url` / `Supabase.anonKey`, for both Debug and Release).

## 5. Check Realtime

**Database → Replication** (or *Realtime* in newer dashboards): the `games` table should be part of the `supabase_realtime` publication. The schema adds it; this step just confirms it. Realtime is only used as a "something changed" signal; the app polls every four seconds as a fallback.

---

## What the schema creates

| Section | Contents |
|---------|----------|
| Enums | `game_status`, `game_mode` (classic / vote / rapid), `game_phase` (lobby / choosing / judging / round_results / game_over) |
| Tables | `profiles`, `banned_words`, `photos`, `prompt_packs`, `prompts`, `games`, `players`, `game_prompt_packs`, `game_custom_prompts`, `rounds`, `hands`, `player_photo_history`, `submissions`, `votes`, `reports`, `blocked_users` |
| Triggers | profile auto-created for every auth user, `updated_at` maintenance |
| RLS | Players can only **read** rooms they are in, only their **own** hand, submission and vote. Nobody writes game tables directly. Anonymous (not signed in) can read nothing. |
| Engine RPCs | `create_game`, `update_game_settings`, `join_game`, `get_my_active_game`, `get_game_state`, `leave_game`, `set_ready`, `start_game`, `submit_photo`, `refresh_hand`, `pick_winner`, `cast_vote`, `advance_game`, `restart_game`, `list_public_games`, `list_prompt_packs`, `list_prompts` |
| Account & moderation | `delete_my_account`, `update_display_name`, `report_content`, `block_user`, `unblock_user`, `list_blocked_users`, `cleanup_expired_games` (scheduled with pg_cron when available) |
| Realtime | `games` in `supabase_realtime`, `REPLICA IDENTITY FULL` |
| Storage | public bucket `photos` with a read policy |
| Seeds | word filter, 6 prompt packs / 115 prompts, 154 starter photos |

### How a round flows on the server

```
start_game → _start_round
              • judge = players ordered by join time, index (round-1) mod n (none in vote mode)
              • prompt = unused custom prompt → unused pack prompt → any pack prompt
              • _fill_hands tops every hand up to hand_size, avoiding repeats per player
              • phase = choosing, phase_ends_at = now + round_timer
submit_photo  • validates phase / judge / hand, removes the photo from the hand
              • last submission → _to_judging (0 submissions → round with no winner)
pick_winner / cast_vote / advance_game (timer) → _end_round → round_results
advance_game (timer) → _next_round → game_over or _start_round
```

`advance_game` is idempotent and server-checked, so any client can call it when the countdown ends; the host nudges first.

### Account deletion

`delete_my_account()` deletes the caller's row from `auth.users`; every table cascades from it. If your project's `postgres` role cannot delete from `auth.users` (it can on standard Supabase projects), deploy the equivalent as an Edge Function using the service-role key and call it from `AuthRemoteDataSourceImpl.deleteAccount`.

### Replacing the photo library

Upload images to the `photos` bucket, then:

```sql
insert into public.photos (image_url, thumbnail_url, category, credit)
values ('https://<project>.supabase.co/storage/v1/object/public/photos/cat-01.jpg', null, 'animals', 'Your name');
-- optional: remove the starter photos
delete from public.photos where credit = 'Lorem Picsum / Unsplash';
```

### Reviewing reports

**Table editor → reports**. Set `status` to `reviewed`, and set `approved = false` on any photo you want out of rotation.

## ✅ Checklist

- [ ] Project created
- [ ] `supabase/schema.sql` run without errors
- [ ] Anonymous sign-ins enabled
- [ ] URL + anon key in `AppConfiguration.swift`
- [ ] `games` in the realtime publication

## Next step

→ [App configuration](./setup/APP_CONFIGURATION.md)
