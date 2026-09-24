# App Store Compliance Audit

**Scope**: the whole repository. **Role**: release manager acting as a strict App Review reviewer.
**Last verified**: 24 September 2026, against the code rather than the previous version of this file.
**Platform**: iOS only (iPhone). There is no Android project; Google Play items are out of scope.

Legend: ✅ verified compliant · 🔧 fixed on this branch · ⚠️ action needed before submission

The first pass (commit `3e64b5e`) got most of the product-level work right. The second pass found that several of its claims were not true in the code or the project file; those are called out as **Correction** below.

---

## 1. Build settings (`Src/PhotoCards/PhotoCards.xcodeproj`)

| Setting | Value | Status |
|---------|-------|--------|
| Bundle ID | `app.photocards.ios` (tests `.tests` / `.uitests`) | ⚠️ replace with an identifier you own, then register it |
| `DEVELOPMENT_TEAM` | not set | ⚠️ select your team in Xcode |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `1.0` / `1` on every target | ✅ bump the build number for every upload |
| `IPHONEOS_DEPLOYMENT_TARGET` | Was **18.1** at project level and on the test targets but **18** on the app. | 🔧 `18.0` everywhere in the app project (the feature frameworks' targets are already 18) |
| `TARGETED_DEVICE_FAMILY` | `1` (iPhone) | ✅ app; 🔧 test targets were `1,2` |
| Orientations | Portrait on iPhone. The project also set `UISupportedInterfaceOrientations_iPad` (all four) even though the app does not target iPad | 🔧 iPad key removed. `UIRequiresFullScreen` is not needed because there is no iPad target |
| Swift | `SWIFT_VERSION = 5.0` (Swift 5 language mode on the current toolchain) | ✅ |
| Required device capabilities | none declared (arm64 is implicit) | ✅ |
| Display name / category | `PhotoCards`, `public.app-category.games` | ✅ |
| Launch screen | `UILaunchScreen` → `LaunchBackground` colour (asset exists) | ✅ |
| `ITSAppUsesNonExemptEncryption` | `false`: HTTPS only. The CryptoKit SHA-256 in `Authentication` is hashing, which is exempt | ✅ |
| Mac / visionOS "Designed for iPhone" | disabled | ✅ |
| Linked frameworks | App linked **and embedded** `Subscription` (which bundles RevenueCat + RevenueCatUI), `FileHandler`, `Repositories` and `VideoSubscriberAccount`, and imports none of them. There were also 24 stale file references (`FirebaseSdkContainer`, `GoogleSigninLib`, `KFImageContainer`, …) | 🔧 unlinked/unembedded; stale references removed (every removed ID checked to have no remaining reference, and the file re-parsed). `Repositories`, `FileHandler` and `Subscription` were also dropped from `PhotoCards.xcworkspace`, and the `purchases-ios` pin was removed from the workspace `Package.resolved`. The app now links `Common`, `Authentication`, `Events` + Supabase, NukeUI, Factory. **Correction**: the first pass said RevenueCat was "unused". It was unused but still shipped, with a privacy manifest that declares *Purchase History* |

## 2. Entitlements & capabilities

| Check | Status |
|-------|--------|
| `com.apple.developer.applesignin` was in `PhotoCards.entitlements` | 🔧 removed; the file is now an empty dict. Nothing presents `AuthenticationSheet`/`AuthenticationPage`: the app calls only `signInAnonymously()` (`RootViewModel`) and `deleteAccountSheet()` (`RootView`). The `ASAuthorization` and `GIDSignIn` code in `Features/Authentication` can't be reached |
| Push, IAP, background modes, App Groups, associated domains | none | ✅ |
| 4.8 Sign in with Apple | not required: no third-party or social login is offered | ✅ |
| Setup docs told you to enable Sign in with Apple, Push and IAP | 🔧 `docs/setup/APPLE_DEVELOPER.md`, `XCODE_CONFIG.md` rewritten: no capabilities |

## 3. App icon (`Assets.xcassets/AppIcon.appiconset`)

| Check | Status |
|-------|--------|
| Every PNG: RGB (no alpha channel), 8-bit, sRGB, pixel size equal to its slot | ✅ checked with Pillow (all 19 files) |
| 1024 px marketing icon: opaque, full-bleed square, no pre-rounded corners | ✅ |
| `Contents.json` was an icon-generator export (no `info` block, non-standard keys, iPad and legacy iOS 6 slots in an iPhone-only iOS 18 app) | 🔧 replaced with Xcode's single-size format (one universal 1024 × 1024 image). Xcode generates every size from it. The 18 derived PNGs were deleted |

## 4. Swift packages

| Check | Status |
|-------|--------|
| Every `XCRemoteSwiftPackageReference` in the workspace's projects (app, Common, Events, Authentication: Factory, Nuke, supabase-swift, GoogleSignIn-iOS) is pinned in `PhotoCards.xcworkspace/xcshareddata/swiftpm/Package.resolved`, together with its transitive dependencies (AppAuth, GTMAppAuth, gtm-session-fetcher, GoogleUtilities, app-check, promises, swift-crypto/asn1/http-types, pointfree libraries) | ✅ nothing is missing or dangling |
| The last commit removed 92 lines from the workspace `Package.resolved` | ✅ they were the Firebase dependency tree (firebase-ios-sdk, GoogleAppMeasurement, abseil, gRPC, leveldb, nanopb, swift-protobuf, …), which nothing references any more |
| `Src/PhotoCards/PhotoCards.xcodeproj/project.xcworkspace/.../Package.resolved` still pinned Firebase and a different gtm-session-fetcher major | 🔧 deleted. The workspace file is the only source of truth (CI and the docs both use the workspace) |
| `Features/Authentication` statically bundles **GoogleSignIn 9**. Its privacy manifest declares Name, Email, Phone, Coarse Location, User ID, Device ID and Other Usage Data (some for Analytics). The app never initialises it, but Xcode's privacy report aggregates it, and it contradicts the App Privacy answers below | ⚠️ **Swift change**: remove `GoogleAuthProviderImpl.swift`, the Google path in `AuthRepository`/`AuthenticationViewModel`, and the GoogleSignIn package from `Authentication.xcodeproj`. The same goes for the unreachable Apple sign-in path. Until then, `web/licenses/` credits the Google libraries |

## 5. Privacy manifest (`PrivacyInfo.xcprivacy`)

| Check | Status |
|-------|--------|
| Valid plist; `NSPrivacyTracking = false`, no tracking domains | ✅ |
| Collected: User ID, Name (display name), Gameplay Content, Other User Content (custom prompts, report text). All linked, not tracking, App Functionality | ✅ matches `supabase/schema.sql` and the app's RPC calls |
| `UserDefaults` `CA92.1`: `@AppStorage` (name, dark mode, tutorial flag, prompt packs) and `ReviewManager` | ✅ |
| File timestamp `C617.1`, disk space `E174.1`, boot time `35F9.1` | ✅ kept. **Correction**: none of these are called by PhotoCards' own code. They cover statically linked SDK code (Nuke disk cache, Supabase networking); the comments now say so. The claim that supabase-swift and Nuke ship their own manifests could not be verified offline |

## 6. Account deletion (5.1.1(v))

| Check | Status |
|-------|--------|
| Settings → Account → **Delete account & data**, with confirmation | ✅ `SettingsView` → `RootView` → `DeleteAccountSheet` |
| Deletes server-side: `delete_my_account()` deletes `auth.users`; profile, players, reports filed and blocks cascade; games you host cascade | ✅ `supabase/schema.sql` |
| Web instructions | ✅ `web/privacy/`, `web/support/` |

## 7. User-generated content (1.2)

Display names and custom prompts are UGC. The photos come from Picsum/Unsplash and are not user-uploaded.

| Requirement | Status |
|-------------|--------|
| EULA / terms with **zero tolerance** for objectionable content and abusive users | 🔧 `web/terms/` §3 now says so explicitly, plus the 13+ eligibility and Apple's standard EULA terms. **Correction**: the previous text only said "we may remove content" |
| Filter | ✅ server-side `banned_words` on names and custom prompts |
| Report | ⚠️ **Correction**: in the committed code, both `PhotoDetailOverlay` call sites passed `reportUserId: nil`. Only curated photos could be reported, and the actual UGC (names, prompts) could not |
| Block abusive users | ⚠️ **Correction**: because of that nil, the "Also block this player" toggle never appeared, so **no player could be blocked from the UI**. Settings could only *unblock*. A Swift change on this branch (`Features/Game/GameModeration.swift`) adds player and prompt reports and blocking. Verify on device before submitting, and update `SettingsView`'s footer ("Block someone from a photo's report menu…") to match |
| Act on reports within 24 h | ⚠️ you: check the `reports` table daily (Supabase dashboard); remove content, ban accounts. Terms and support now promise 24 h |

## 8. Website (`web/`, deployed by `.github/workflows/pages.yml`)

| Check | Status |
|-------|--------|
| Paths `/`, `/privacy/`, `/terms/`, `/support/`, `/licenses/`, `/join/?code=` exist and match `AppConfiguration.App` (`https://tcytseven.github.io/PhotoLine/…`) | ✅ no mismatch |
| HTML well formed; every relative link and the `#get-the-app` anchor resolve | ✅ checked with a parser |
| Join page → `photocards://join?code=XXXXXX`, handled by `DeepLinkCoordinator` (`join` host, `code` query) | ✅ |
| Privacy policy matches the data | 🔧 date; report text and prompt-pack preference added; retention made specific (finished rooms about 2 h, abandoned rooms at most 12 h); no payments or crash reporting |
| Support page has a real contact method | ✅ public GitHub issues (the repo is public). ⚠️ **Recommended**: add a support **email** address. App Review accepts an issue tracker, but some users can't use one and privacy requests don't belong in public |
| Licenses page listed only 3 of the libraries that ship | 🔧 added the pointfree, Apple and Google/AppAuth libraries (Apache 2.0 needs attribution) |
| Pages deploys | ✅ on push to `main` touching `web/**`, or run manually. ⚠️ `configure-pages` `enablement: true` cannot enable Pages with the default token: turn it on once in *Settings → Pages → Source: GitHub Actions*. The site could not be fetched from this environment, so check that it is live |
| Retention claim depends on `pg_cron` | ⚠️ confirm `photocards_cleanup_expired_games` exists in `cron.job` on the production project |

## 9. Repository hygiene

| Check | Status |
|-------|--------|
| `xcuserdata/` committed in 8 projects (including a leftover `Src/iOSJumpstart`) | 🔧 removed from the index. The `.gitignore` pattern `*.xcodeproj/xcuserdata/` contains a slash, so it only matched at the repo root and never matched these folders; it is now `xcuserdata/` |
| CI only ran on `main` | 🔧 `ios.yml` also runs on pushes to `claude/**`, on manual `workflow_dispatch`, and cancels superseded runs |

## 10. Other guideline checks

| Guideline | Status |
|-----------|--------|
| 2.1 Completeness: full game loop, no placeholders reachable | ✅ The `API.baseURL`, `Google.clientID` and `RevenueCat.apiKey` placeholders in `AppConfiguration` are unreachable. ⚠️ A game **needs 3 players**, see the review notes below |
| 2.3 Accurate metadata: screenshots must show real gameplay | ⚠️ |
| 2.5.4 Background modes | ✅ none |
| 3.1 Payments | ✅ none; RevenueCat no longer shipped |
| 4.0 Design on iPad: iPhone-only apps are reviewed on iPad in compatibility mode | ⚠️ run once on an iPad simulator |
| 5.1.1 Permissions | ✅ no camera, photos, location, contacts, microphone, notifications or ATT prompts; no `NS…UsageDescription` keys |
| 5.1.2 No tracking, no third-party analytics | ✅ (subject to the GoogleSignIn removal in §4) |
| Content rights | ⚠️ starter photos are Picsum/Unsplash by numeric id. Review the seeded ids for anything you would not want rated 12+, or ship your own library |

---

## Submission checklist

### Before archiving
- [ ] Your bundle ID and team in Xcode; App ID registered with **no** capabilities
- [ ] Build number incremented (`CURRENT_PROJECT_VERSION`)
- [ ] Production Supabase: `schema.sql` applied, anonymous sign-ins **on**, `pg_cron` cleanup job scheduled
- [ ] Swift follow-ups landed: player/prompt report + block (§7), GoogleSignIn removed from `Authentication` (§4)
- [ ] CI green on this branch (Actions → iOS build)
- [ ] GitHub Pages enabled; `/privacy/`, `/terms/`, `/support/` load on a phone
- [ ] Product → Archive → Validate App passes, and the Xcode privacy report shows only the four data types below

### App Store Connect: App Information
- **Name**: PhotoCards · **Subtitle** (optional): e.g. "The photo party game"
- **Category**: Games. Subcategories: **Card** and **Family** (or Casual). There is no "Party" subcategory
- **Content rights**: third-party content is present (Unsplash-licensed photos), and you have the rights to use it
- **Age rating questionnaire**:
  - User-generated content: **Yes**. Messaging and chat: **No** (no free-text chat; names and prompts are filtered, reportable and blockable)
  - Unrestricted web access: **No**. The app opens only its own fixed pages in Safari View Controller
  - Violence, sexual content, profanity/crude humour, horror, drugs, gambling, contests: **None**, unless your prompt packs contain crude humour. If they do, answer **Infrequent/Mild**
  - Advertising: **No** · In-app purchases: **No** · Parental controls / age assurance: **No**
  - Expected result: **13+** (UGC between strangers, via public rooms). Keep the terms' 13+ minimum consistent with it
- **Privacy Policy URL**: `https://tcytseven.github.io/PhotoLine/privacy/`

### App Privacy (nutrition label)
Data is collected: **Yes**. For each type below: **Linked to the user: Yes**, **Used for tracking: No**, purpose **App Functionality** only.

| Category → type | What it is |
|-----------------|------------|
| Identifiers → **User ID** | anonymous Supabase guest ID |
| Contact Info → **Name** | display name shown to other players |
| User Content → **Gameplay Content** | rooms, submissions, votes, scores |
| User Content → **Other User Content** | custom prompts, report reasons/details |

Not collected: contact details, location, photos, device ID, usage data, diagnostics, purchases.

### Version page
- **Screenshots**: iPhone **6.9"** (1320 × 2868 or 1290 × 2796, portrait) is required. **6.5"** (1242 × 2688 or 1284 × 2778) is needed only if you don't rely on automatic scaling. Up to 10 each, showing home, lobby, hand, reveal/judging and results. No iPad screenshots (iPhone only)
- **Support URL**: `https://tcytseven.github.io/PhotoLine/support/` · **Marketing URL** (optional): `https://tcytseven.github.io/PhotoLine/`
- **Copyright**: `2026 <your name>`
- **Sign-in required**: **No** (guest accounts are created automatically), so no demo account is needed

### App Review notes (paste into Notes)

> PhotoCards is a real-time multiplayer party game. There is no login: a guest account is created automatically on first launch.
>
> A round needs **three players on three separate devices** (simulators work too). This is a server rule: the host can't start with fewer than 3.
> 1. Device A: enter a name → **Create game** → **Create room**. Note the six-letter code.
> 2. Devices B and C: enter a name → **Join game** → enter the code (or tap *Browse* for public rooms).
> 3. Device A: **Start game**. B and C each pick a photo; the judge picks a winner. Play continues until the target score.
>
> If you only have one device, the attached screen recording shows a complete game from all three devices.
> [Optionally: "We will keep two devices in a public room named 'App Review' from <date/time, time zone> to <…>; open *Join game → Browse* to join as the third player."]
>
> Safety (Guideline 1.2): names and custom prompts pass a server-side word filter. Photos, players and prompts can be reported in-game, and players can be blocked from the report sheet. Settings → Blocked players lists them. We review reports within 24 hours. Terms (zero-tolerance policy): https://tcytseven.github.io/PhotoLine/terms/
> Account deletion: **Settings → Delete account & data**.
> The app has no purchases, no ads, no tracking, and does not access the camera or photo library.

- [ ] Attach a screen recording (App Review accepts a video link or attachment) of a full three-device game, including report and block. This is the most likely point of friction for a multiplayer-only app
- [ ] Consider a solo way in for future versions (a practice round against bots), which removes the three-device requirement for review

### After approval
- [ ] Set `AppConfiguration.App.appStoreID` (update checker) and link the App Store page from `web/support/#get-the-app`
- [ ] Check the `reports` table daily
