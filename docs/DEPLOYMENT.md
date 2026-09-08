# Deployment Guide

TestFlight and App Store submission for PhotoCards.

## Pre-flight checklist

### Code & configuration
- [ ] Release `Supabase.url` / `Supabase.anonKey` set in `AppConfiguration.swift`
- [ ] `supabase/schema.sql` applied to the **production** project, anonymous sign-ins enabled
- [ ] Starter photo library replaced with rights-cleared images (or you are comfortable shipping Unsplash-licensed Picsum photos)
- [ ] Bundle identifier and team set in Xcode (`app.photocards.ios` is a placeholder)
- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` bumped
- [ ] Website deployed (`.github/workflows/pages.yml`) and the four links open: privacy, terms, support, licenses
- [ ] `docs/APP_STORE_COMPLIANCE.md` re-checked

### App Store Connect
- [ ] App created, name **PhotoCards**, primary category **Games › Party**, secondary **Games › Casual**
- [ ] Support URL: `https://tcytseven.github.io/PhotoLine/support/`
- [ ] Privacy Policy URL: `https://tcytseven.github.io/PhotoLine/privacy/`
- [ ] Screenshots for 6.9" and 6.5" iPhones (home, lobby, hand, reveal, results)
- [ ] Age rating: answer the questionnaire honestly. Unrestricted web access: **No** (links open fixed pages). User-generated content: **Yes** (display names, custom prompts) — the app has reporting, blocking and a word filter.

### App Privacy (nutrition label)
Declare exactly what `PrivacyInfo.xcprivacy` declares, all **linked to the user**, **not used for tracking**, purpose **App Functionality**:

| Data type | Detail |
|-----------|--------|
| User ID | anonymous guest ID |
| Name | display name |
| Gameplay content | rooms, submissions, votes, scores |
| Other user content | custom prompts, reports |

No data is used for tracking. No third-party analytics or ads.

## Archive & upload

1. Xcode → scheme `PhotoCards` → *Any iOS Device (arm64)*
2. **Product → Archive**
3. Organizer → **Distribute App → App Store Connect → Upload**
4. Export compliance is answered by `ITSAppUsesNonExemptEncryption = false` in `Info.plist` (HTTPS only).

## TestFlight

- Add internal testers, then an external group.
- Testers need **three** devices/accounts to play a full round; mention it in the "What to test" notes.
- Beta App Review needs the same privacy policy link.

## App Review notes (paste into "Notes")

> PhotoCards is a multiplayer party game. No login is required (guest accounts are created automatically).
> To test a full game you need three sessions: install on two devices plus a third device or a second tester.
> 1. Device A: enter a name, tap **Create game**, tap **Create room**. Note the six-letter code.
> 2. Devices B and C: enter a name, tap **Join game**, enter the code.
> 3. Device A: tap **Start game**. B and C pick a photo; A (the judge) picks the winner.
> Account deletion: **Settings → Delete account & data**. Reporting: open any photo and tap the flag.
> Privacy policy: https://tcytseven.github.io/PhotoLine/privacy/

## CI

`.github/workflows/ios.yml` builds the `PhotoCards` scheme for the simulator on every push/PR to `main`. For signed TestFlight uploads from CI, add your certificate and provisioning profile as secrets and extend the workflow with `xcodebuild -exportArchive` or fastlane; nothing in the app requires extra config files (no Firebase plist).

## Post-submission

- Watch the Supabase dashboard **Reports** table after launch.
- `cleanup_expired_games()` runs every 30 minutes when pg_cron is available; otherwise run it from the SQL editor now and then.
- To force players onto a new version, ship a **major** version bump: the update checker blocks older majors with an "Update required" screen once the new build is live on the App Store.
