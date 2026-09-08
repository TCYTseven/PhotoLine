# Architecture

PhotoCards is a thin SwiftUI client over a Postgres game engine.

## Principles

1. **Server is the source of truth.** Judge, prompt, timer, hands, submissions, scores and round number live in Postgres and change only through `SECURITY DEFINER` functions (`supabase/schema.sql`). Clients cannot write game tables.
2. **One snapshot type.** Every RPC returns `get_game_state()`; the client decodes it into `GameState` and renders whichever screen the `phase` calls for. No client-side state machine to drift.
3. **Realtime is a hint, not a transport.** The app subscribes to UPDATEs on its `games` row (`version` bumps on every transition) and re-fetches. A 4 s poll and a 1 s clock tick cover missed events and drive timers.
4. **Guests only.** An anonymous Supabase session is created on first launch and reused. Deleting the account creates a fresh guest.

## Layers (app target)

```
Views (Features/**)            SwiftUI screens, no networking
   │  @EnvironmentObject
GameSessionStore (Game/Session) @MainActor ObservableObject: snapshot, timers, polling, actions
   │  protocol
GameService (Game/Core)        async API the UI depends on
   │
SupabaseGameService (Game/Data) RPC calls + Realtime channel, JSON → GameModels
```

`GameModels.swift` mirrors the JSON emitted by the SQL functions (snake_case → camelCase, ISO timestamps → `Date`).

## Screen flow

```
RootView
 ├─ LaunchStatusView            loading / unconfigured / failed
 └─ NavigationStack
     └─ HomeView                name, Create, Join, Browse, Prompts, Settings
         ├─ CreateGameView      mode, rules, packs, custom prompts   → session.createGame
         ├─ JoinGameView        6-char code                          → session.joinGame
         ├─ BrowseGamesView     public lobbies                       → session.joinGame
         ├─ PromptPacksView
         └─ SettingsView        name, dark mode, legal, blocked, delete account
 fullScreenCover (session.isInGame)
     └─ GameSessionView         header (leave, code / round, timer) + by phase:
         ├─ LobbyView           code, share, players, settings, ready / start
         ├─ ChoosingView        prompt card, 16-photo grid, refresh, submit (WaitingView for judge / submitted)
         ├─ JudgingView         anonymous grid, judge picks or everyone votes
         ├─ RoundResultsView    winner, all photos, leaderboard, countdown
         └─ FinalResultsView    winner, leaderboard, highlights, play again / home
```

## Timers

`games.phase_ends_at` is set by the server. The store computes a server-clock offset from `server_time` in each snapshot, shows a countdown, and when the deadline passes calls `advance_game` (host after 0.3 s, others after 2.5 s). The function is idempotent: whoever arrives first moves the game on, everyone else gets the new snapshot.

## Reconnect

`get_my_active_game()` runs on launch and on foreground. A player who closed the app is still a member of the room (rows are only marked left on explicit *Leave*), so they land straight back in the current phase.

## Frameworks from the starter kit

`Common` (theme, config), `Authentication` (Supabase client, guest / Apple / Google sign-in, account deletion sheet) and `Events` are used. `Repositories`, `FileHandler` and `Subscription` are built and linked but unused by the game; remove them from the workspace if you don't plan to use them.
