# PhotoCards

<div align="center">
  <p><strong>A multiplayer party game where every answer is a photo.</strong></p>

  ![iOS 18+](https://img.shields.io/badge/iOS-18%2B-blue)
  ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)
  ![Xcode 16+](https://img.shields.io/badge/Xcode-16%2B-blue)
  ![License](https://img.shields.io/badge/License-MIT-green)
</div>

A prompt appears ("My face when someone says *trust me*"). Everyone except the judge picks the best answer from a hand of **16 random photos**. Photos are revealed anonymously, the judge picks a winner (or everyone votes), the winner gets a point, and the next judge is up. First to the target score, or best after the last round, wins.

Native **SwiftUI** client, **Supabase** backend (Postgres + Realtime + Auth), no accounts (guests only), no camera-roll access.

---

## What's in the box

| Area | Highlights |
|------|------------|
| **Gameplay** | Classic (judge), Vote and Rapid Fire modes · 16-photo hands with limited refreshes · judge rotation · round timers · anonymous reveal · scores, leaderboard, winning-photo highlights · Play again |
| **Rooms** | Six-letter codes · private or public (browse list) · share / deep link (`photocards://join?code=…`) · reconnect after the app is closed · host hand-off when the host leaves |
| **Content** | Six curated prompt packs (115 prompts) · host-written custom prompts · starter photo library (Lorem Picsum) that you swap for your own |
| **Safety** | Report any photo / player / prompt · block players · username and prompt word filter · in-app **Delete account & data** |
| **Backend** | One SQL file sets up everything: tables, RLS, SECURITY DEFINER game engine RPCs, Realtime, storage bucket, seeds |
| **Compliance** | Privacy manifest, no tracking, privacy policy / terms / support pages in `web/` (deployed to GitHub Pages), audit in [docs/APP_STORE_COMPLIANCE.md](./docs/APP_STORE_COMPLIANCE.md) |

---

## Quick start

### 1. Backend (5 minutes)

1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor → New query**, paste the whole of [`supabase/schema.sql`](./supabase/schema.sql), run it.
3. **Authentication → Providers → Anonymous sign-ins → enable.**
4. Copy the **Project URL** and **anon key** from *Project Settings → API*.

Full walkthrough: [docs/SUPABASE_SETUP_GUIDE.md](./docs/SUPABASE_SETUP_GUIDE.md)

### 2. App

```bash
git clone https://github.com/TCYTseven/PhotoLine.git
cd PhotoLine
open PhotoCards.xcworkspace
```

Open `Src/Features/Common/Common/Configuration/AppConfiguration.swift` and fill in:

| Placeholder | Value |
|-------------|-------|
| `YOUR_SUPABASE_URL` | Project URL, e.g. `https://abcd.supabase.co` |
| `YOUR_SUPABASE_ANON_KEY` | anon / public key |

Select your team under *Signing & Capabilities*, pick a bundle identifier, and run on three devices or simulators to play a full game.

Until the placeholders are replaced the app shows a "Backend not configured" screen instead of crashing.

### 3. Website (privacy policy, terms, support)

The static site in [`web/`](./web) is deployed by `.github/workflows/pages.yml` to GitHub Pages at `https://tcytseven.github.io/PhotoLine/`. Enable **Settings → Pages → Source: GitHub Actions** in the repository once; the workflow enables it automatically on the first run when permissions allow. The in-app links point at:

- `/privacy/` – Privacy Policy
- `/terms/` – Terms of Service
- `/support/` – Help & support (App Store "Support URL")
- `/licenses/` – photo and open-source credits
- `/join/?code=ABC123` – invite page that deep-links into the app

If you host the site elsewhere, change the URLs in `AppConfiguration.App`.

---

## Architecture

```
Src/
├── PhotoCards/PhotoCards/           # App target (file-system synced: drop files in, they build)
│   ├── Main/PhotoCardsApp.swift
│   ├── App/RootView.swift           # guest sign-in, navigation, full-screen game
│   ├── Game/
│   │   ├── Core/                    # GameModels, GameService protocol (UI-independent)
│   │   ├── Data/                    # SupabaseGameService (RPC + Realtime)
│   │   └── Session/                 # GameSessionStore (snapshot, timers, polling)
│   ├── Features/
│   │   ├── Home/                    # Home, Create, Join, Browse
│   │   ├── Game/                    # Lobby, Choosing, Judging, Results, Final, Report
│   │   ├── Settings/                # Settings, blocked players, prompt packs
│   │   ├── HowToPlay/, Legal/, Components/
│   ├── Services/                    # Deep links, network monitor, update check, reviews
│   ├── Info.plist · PrivacyInfo.xcprivacy
└── Features/                        # Reusable frameworks from the starter kit
    ├── Common/                      # Theme, AppConfiguration, UI primitives
    ├── Authentication/              # Supabase client, guest/Apple/Google sign-in, account deletion
    ├── Events/                      # In-app event bus
    └── Repositories/ FileHandler/ Subscription/   # Optional, not used by the game
supabase/schema.sql                  # The whole backend
web/                                 # Landing page, privacy, terms, support
```

**The server is the source of truth.** Clients never write game tables directly. Every action is a Postgres function (`create_game`, `join_game`, `start_game`, `submit_photo`, `pick_winner`, `cast_vote`, `advance_game`, `restart_game`, …) that validates the caller, mutates state and returns the full `get_game_state()` snapshot. Timers are `phase_ends_at` timestamps; clients call `advance_game` when one expires and the server decides what happens. Realtime is a single subscription on the game row (`games.version` bumps on every change) with polling as a fallback.

Read more: [docs/reference/ARCHITECTURE.md](./docs/reference/ARCHITECTURE.md)

---

## Replacing the photo library

The seed inserts 154 Lorem Picsum images so the game is playable immediately. For a real launch:

1. Upload your curated, rights-cleared images to the public `photos` storage bucket (created by the schema).
2. Insert rows into `public.photos` with the public URLs (`image_url`, optional `thumbnail_url`, `category`, `credit`).
3. Optionally delete the seed rows: `delete from public.photos where credit = 'Lorem Picsum / Unsplash';`

Hands are dealt only from `approved = true` rows.

---

## Documentation

| Guide | Description |
|-------|-------------|
| [Supabase setup](./docs/SUPABASE_SETUP_GUIDE.md) | Backend in five minutes, plus how the schema is organised |
| [App configuration](./docs/setup/APP_CONFIGURATION.md) | Keys and URLs in `AppConfiguration.swift` |
| [Apple Developer](./docs/setup/APPLE_DEVELOPER.md) · [Xcode](./docs/setup/XCODE_CONFIG.md) | Signing, bundle ID, capabilities |
| [Deployment](./docs/DEPLOYMENT.md) | TestFlight and App Store |
| [App Store compliance audit](./docs/APP_STORE_COMPLIANCE.md) | Review-guideline checklist and what was fixed |
| [Architecture](./docs/reference/ARCHITECTURE.md) · [Navigation](./docs/guides/NAVIGATION.md) · [Events](./docs/guides/EVENTS.md) · [DI](./docs/guides/DEPENDENCY_INJECTION.md) | Code patterns |
| [Troubleshooting](./docs/TROUBLESHOOTING.md) | Common issues |

---

## Roadmap (not in v1)

Friends, direct messages, user-uploaded photos (with moderation), ranked mode, achievements, cosmetics, caption mode, spectator mode, team mode, Android.

## License

MIT. See [LICENSE](./LICENSE). Photos in the starter library are Unsplash-licensed via Lorem Picsum; Poppins is under the SIL Open Font License.
