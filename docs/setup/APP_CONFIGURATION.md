# App Configuration

**Time**: 2 min | **File**: `Src/Features/Common/Common/Configuration/AppConfiguration.swift`

| Key | Required | Where to find it |
|-----|----------|------------------|
| `Supabase.url` / `Supabase.anonKey` (Debug + Release) | **Yes** | Supabase → Project Settings → API |
| `DeepLink.urlScheme` | already set (`photocards`) | Must match `CFBundleURLSchemes` in `Info.plist` |
| `DeepLink.universalLinkDomains` | optional | Your domain, once it serves an `apple-app-site-association` file |
| `App.websiteURL`, `privacyPolicyURL`, `termsOfServiceURL`, `supportURL`, `licensesURL` | already set | Point at the GitHub Pages site in `web/`; change if you host elsewhere |
| `App.appStoreID` | optional | App Store Connect → App Information; used by the update checker |
| `Google.clientID`, `RevenueCat.apiKey` | not used by the game | Only needed if you re-enable those starter-kit modules |

The app refuses to start into the game (shows a "Backend not configured" screen) while the Supabase placeholders are in place, so a build with missing keys can never reach reviewers.

## Next step

→ [Build & run](../SETUP.md)
