# Complete Setup Guide

Get PhotoCards running end to end in about **20 minutes**.

**Requirements**: macOS, Xcode 16+, an Apple Developer account for device builds.

| # | Task | Time | Guide |
|---|------|------|-------|
| 1 | Supabase backend | 5 min | [→ Guide](./SUPABASE_SETUP_GUIDE.md) |
| 2 | App configuration | 2 min | [→ Guide](./setup/APP_CONFIGURATION.md) |
| 3 | Apple Developer + Xcode signing | 10 min | [→ Apple](./setup/APPLE_DEVELOPER.md) · [→ Xcode](./setup/XCODE_CONFIG.md) |
| 4 | Build & run | 2 min | below |
| 5 | Website (privacy / terms / support) | 2 min | below |

## Build & run

```bash
git clone https://github.com/TCYTseven/PhotoLine.git
cd PhotoLine
open PhotoCards.xcworkspace   # always the workspace, not the .xcodeproj
```

Select the `PhotoCards` scheme and run. To play a full game you need **three** players: run on a device plus two simulators (each gets its own guest identity).

### Renaming / bundle ID

The scripts from the starter kit still work:

```bash
./scripts/rename_app.sh PhotoCards YourName
./scripts/change_bundle_id.sh app.photocards com.yourcompany
```

## Website

`.github/workflows/pages.yml` deploys `web/` to GitHub Pages on every push to `main`. Enable **Settings → Pages → Build and deployment → Source: GitHub Actions** once. The privacy policy, terms and support pages linked from the app live there.

## Verify

- [ ] Home screen shows the PhotoCards logo (not "Backend not configured")
- [ ] Create room → lobby shows a six-letter code
- [ ] Join from two more clients → host can start
- [ ] Round runs: hand of 16 → submit → reveal → judge picks → results → next round
- [ ] Settings → Privacy Policy opens the website
- [ ] Settings → Delete account & data works and returns you home as a new guest
