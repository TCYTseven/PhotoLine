# Troubleshooting

## "Backend not configured" on launch
`AppConfiguration.Supabase.url` / `anonKey` still contain the `YOUR_SUPABASE_…` placeholders. Fill them in for the active build configuration (Debug and Release are separate).

## "Couldn't connect" on launch
The app could not create a guest session.
- Anonymous sign-ins are disabled → Supabase → Authentication → Providers → Anonymous sign-ins → ON.
- Wrong URL / key → compare with Project Settings → API.
- No network → the red banner at the top shows offline state.

## "Room not found"
- The code is six characters from `A–Z` (no I, O) and `2–9`.
- Rooms expire 12 h after creation in the lobby, 6 h after start, 2 h after finishing.
- The host left an empty lobby, which closes the room.

## "You need at least 3 players to start"
Classic needs a judge plus two players. Each simulator/device is its own guest.

## Nothing updates until I pull / wait
Realtime is not delivering.
- Database → Replication: `games` must be in the `supabase_realtime` publication (the schema adds it).
- The app polls every 4 s regardless, so the game still progresses; check the network.

## "The photo library is empty"
`public.photos` has fewer than `hand_size` approved rows. Re-run the seed section of `supabase/schema.sql` or insert your own photos.

## Photos don't load
The starter library uses `https://picsum.photos`. If that host is blocked on your network, replace the library (see README).

## Account deletion fails with "permission denied for table users"
Your Supabase project doesn't let the `postgres` role delete from `auth.users`. Deploy a `delete-user` Edge Function that calls `auth.admin.deleteUser` with the service-role key and call it from `AuthRemoteDataSourceImpl.deleteAccount` instead of the RPC.

## Build errors after pulling
- Always open `PhotoCards.xcworkspace`, not the `.xcodeproj`.
- File → Packages → Resolve Package Versions.
- Clean build folder (⇧⌘K) if a framework module is stale.

## CI fails on `xcodebuild`
The workflow builds the `PhotoCards` scheme on the latest macOS runner. Package resolution needs network; re-run if GitHub had a transient failure. No secrets or config files are required for a simulator build.
