# App Store / Google Play Compliance Audit

**Scope**: the whole repository as of this branch. **Role**: release manager acting as a strict App Store / Play reviewer.
**Platform note**: this repository contains an **iOS app only**. There is no Android project, so no `AndroidManifest.xml` exists to audit; Google Play items are covered by the shared web pages (privacy policy, terms, support) and data-deletion flow, which Play's Data Safety form also requires.

Legend: ✅ compliant · 🔧 fixed in this branch · ⚠️ action needed by you before submission

---

## 1. Account deletion (Guideline 5.1.1(v))

| Check | Status | Where |
|-------|--------|-------|
| Does the app create accounts? | Yes: anonymous guest accounts via Supabase | `RootViewModel.bootstrap()` |
| In-app deletion, easy to find | 🔧 **Settings → Account → Delete account & data**, with a confirmation dialog and a clear description of what is removed | `Features/Settings/SettingsView.swift` |
| Deletes server-side data, not just sign-out | 🔧 `delete_my_account()` deletes the `auth.users` row; every table cascades (profile, players, submissions, votes, reports, blocks) | `supabase/schema.sql` §6, `AuthRemoteDataSourceImpl.deleteAccount` |
| Local data wiped too | 🔧 Keychain session cleared, display name reset, session cleared; a new guest is created | `RootView.onChange(accountDeletionCount)` |
| Web instructions | 🔧 Privacy policy and support page describe the in-app path | `web/privacy/`, `web/support/` |

Before: the starter kit called a `delete-user` Edge Function that does not exist in this repo (would fail at runtime), and the button lived on a "Settings Coming Soon" placeholder.

## 2. Privacy policy & terms (5.1.1, 1.2, Play Policy Center)

| Check | Status | Where |
|-------|--------|-------|
| Privacy policy accessible in-app | 🔧 Settings → Legal → Privacy Policy (in-app Safari) and a footer link on the Home screen | `SettingsView`, `HomeView.legalFooter` |
| Terms accessible in-app | 🔧 Settings → Legal → Terms of Service, Home footer | same |
| Live web pages | 🔧 `web/privacy/`, `web/terms/`, `web/support/`, `web/licenses/` deployed by `.github/workflows/pages.yml` to `https://tcytseven.github.io/PhotoLine/…` | `web/`, `AppConfiguration.App` |
| Policy content matches actual data practices | 🔧 Written for this app: guest ID, display name, gameplay, custom prompts, reports; no camera roll, no tracking, retention and deletion described | `web/privacy/index.html` |
| Support URL for App Store Connect | 🔧 `/support/` with FAQ and a real contact channel (GitHub issues) | `web/support/` |

Before: links pointed at `iosjumpstart.com` and `yourapp.com` placeholders; "Contact Us" opened a mail composer to `support@iosjumpstart.com`; the auth page's "Terms / Privacy" text was not tappable.

⚠️ **You**: enable GitHub Pages (Settings → Pages → Source: GitHub Actions) or host `web/` elsewhere and update the URLs. Add the same URLs to App Store Connect.

## 3. Permissions & usage strings (5.1.1(i))

| Permission | Used? | Status |
|------------|-------|--------|
| Camera / Photo library | **No** – photos come from a curated library; the profile photo picker was removed | ✅ no `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` needed; none present (declaring unused ones is a rejection risk) |
| Location, contacts, microphone, Bluetooth, health, motion | No | ✅ none declared |
| Push notifications | **No** – removed. The starter kit requested notification permission from onboarding and a showcase tab with no user benefit, which reviewers reject under 4.5.4 / 5.1.1 | 🔧 `NotificationService`, Firebase Messaging, onboarding "Enable notifications" page removed |
| App Tracking Transparency | Not needed – no tracking, no IDFA | ✅ |
| Arbitrary loads (`NSAllowsArbitraryLoads = true`) | Was enabled with no justification | 🔧 removed; all traffic is HTTPS |
| Export compliance | 🔧 `ITSAppUsesNonExemptEncryption = false` added |

`Info.plist` now contains only: URL scheme (`photocards`), fonts, launch screen colour, encryption flag. Android: not applicable (no manifest).

## 4. Privacy manifest & required-reason APIs

| Check | Status | Where |
|-------|--------|-------|
| `PrivacyInfo.xcprivacy` in the app bundle | 🔧 added (was missing) | `Src/PhotoCards/PhotoCards/PrivacyInfo.xcprivacy` |
| `NSPrivacyTracking` | `false`, no tracking domains | ✅ |
| Collected data types | User ID, Name, Gameplay Content, Other User Content; all linked, not tracking, purpose App Functionality | ✅ mirrors the SQL schema |
| Required-reason APIs | UserDefaults `CA92.1` (`@AppStorage`), file timestamp `C617.1` and disk space `E174.1` (image cache), system boot time `35F9.1` (networking) | ✅ |
| Third-party SDK manifests | supabase-swift, Nuke and Factory ship their own manifests. Firebase (Analytics/Messaging) was linked but unused, which would have added Google's data-collection declarations to your label | 🔧 Firebase package removed from the app target |
| App Privacy label | ⚠️ **You**: declare the same four data types in App Store Connect (see `docs/DEPLOYMENT.md`) |

## 5. Broken flows, placeholders, dummy logins (2.1, 2.3, 4.2)

| Finding | Status |
|---------|--------|
| "Settings Coming Soon" placeholder screen | 🔧 replaced by a real Settings screen |
| "Showcase" tab demonstrating paywall / notification permission with placeholder RevenueCat key (paywall would show an error) | 🔧 removed; the game has no purchases |
| Five-page template onboarding ("Welcome to iOSJumpstart", "Start building your next great app", **EARLY ACCESS** badge) | 🔧 replaced with a four-page *How to play* that explains the actual game |
| Auth gate with Apple + Google buttons; Google client ID was `YOUR_GOOGLE_CLIENT_ID` (crash/failed sign-in), URL scheme placeholder in `Info.plist` | 🔧 the game uses guest sign-in only; the Google URL scheme placeholder removed. Apple/Google code remains in the `Authentication` framework but is not reachable from the UI |
| `FirebaseApp.configure()` at launch without `GoogleService-Info.plist` → **crash on launch** | 🔧 Firebase removed entirely |
| "Rate App" / "Share App" built App Store URLs from `YOUR_APP_STORE_ID` (dead links) | 🔧 Rate uses the native `SKStoreReviewController` prompt; Share shares the website; the update checker uses Apple's `trackViewUrl` |
| Launch screen referenced a non-existent `LogoWhite` image | 🔧 colour-only launch screen (`LaunchBackground`) |
| Bundle ID `com.mosal.SYNAPSEApp` and the template author's `DEVELOPMENT_TEAM` | 🔧 neutral bundle ID, team removed (select yours) |
| App category "Productivity" | 🔧 Games |
| Unconfigured backend would show cryptic network errors | 🔧 explicit "Backend not configured" and "Couldn't connect / Try again" screens; guest sign-in never leaves the user on a blank screen |
| Every in-game error surfaces to the user | 🔧 server messages ("Room not found…", "This room is full", "Only the judge can pick…") are shown in alerts |
| Empty states | 🔧 Browse (no rooms / offline), blocked list, prompt packs, dealing hand |

No debug bypasses, hidden test menus or "coming soon" buttons remain. `grep -rn "coming soon\|TODO\|placeholder" Src/PhotoCards` returns nothing user-facing.

## 6. User-generated content & safety (1.2)

Display names and custom prompts are user-generated and visible to other players, so 1.2 applies.

| Requirement | Status |
|-------------|--------|
| Filter objectionable content | 🔧 `banned_words` filter on names and custom prompts (server-side) |
| Report mechanism | 🔧 flag button on every enlarged photo → reason, details, optional block → `reports` table |
| Block abusive users | 🔧 `block_user` / `unblock_user`; blocked users cannot join rooms you host; Settings → Blocked players |
| Act on reports | ⚠️ **You**: review the `reports` table in the Supabase dashboard; set `photos.approved = false` to pull an image |
| Terms prohibit abuse and describe removal | 🔧 `web/terms/` §3–4 |

## 7. Other guideline checks

| Guideline | Status |
|-----------|--------|
| 2.1 Completeness – app runs a full game loop, no test content | ✅ (needs 3 testers; see review notes in `docs/DEPLOYMENT.md`) |
| 2.5.1 Public APIs only; no private frameworks | ✅ |
| 2.5.4 Background modes | ✅ none declared |
| 3.1 Payments | ✅ no purchases (RevenueCat module unused) |
| 4.0 Design – native controls, Dynamic-Type-friendly fonts, accessibility labels on icon buttons and tiles | ✅ |
| 4.8 Sign in with Apple | ✅ not required: no third-party login is offered |
| 5.1.2 Data use – no sharing with third parties beyond the hosting provider | ✅ |
| 5.1.4 Kids – not a Kids Category app; age rating from the questionnaire | ✅ |
| Content licensing – starter photos under the Unsplash License, credited in `web/licenses/` | ✅ (⚠️ replace with your own library for a real launch, see README) |

## Remaining actions before submission

1. Fill in Supabase URL/key; run `supabase/schema.sql`; enable anonymous sign-ins.
2. Enable GitHub Pages so the privacy/terms/support links resolve (or host `web/` and update `AppConfiguration.App`).
3. Set your team and bundle identifier in Xcode.
4. Fill in the App Privacy questionnaire exactly as in section 4.
5. Decide on the photo library (keep Picsum or upload your own).
6. Optionally remove the unused `Subscription`, `FileHandler` and `Repositories` frameworks from the workspace to shrink the binary.
