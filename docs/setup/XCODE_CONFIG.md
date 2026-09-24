# Xcode Configuration

**Time**: 5 min

## 1. Open the workspace

```bash
open PhotoCards.xcworkspace
```

Always open the **workspace**, not `Src/PhotoCards/PhotoCards.xcodeproj`: the feature frameworks and the pinned package versions (`PhotoCards.xcworkspace/xcshareddata/swiftpm/Package.resolved`) live at workspace level. Select the `PhotoCards` target.

## 2. Bundle identifier and version

**Targets** → **PhotoCards** → **General**

- **Bundle Identifier**: `app.photocards.ios` by default. Change it to one you own; it must match the App ID in the developer portal.
- **Version** (`MARKETING_VERSION`): `1.0` for the first release.
- **Build** (`CURRENT_PROJECT_VERSION`): increase for every upload to App Store Connect.
- **Minimum Deployments**: iOS 18.0. **Supported Destinations**: iPhone only (portrait). The app still runs on iPad in iPhone compatibility mode, and App Review may test it there.

## 3. Signing

**Signing & Capabilities** tab:

- **Team**: your Apple Developer account
- **Automatically manage signing**: ✅

## 4. Capabilities

There should be **none** listed. `PhotoCards.entitlements` is intentionally empty: the app signs players in as anonymous guests, so Sign in with Apple, Push Notifications and In-App Purchase are not needed. If you later add one of those features, add the capability then.

## 5. URL scheme

**Info** tab → **URL Types** contains the scheme `photocards` (for `photocards://join?code=ABC123` links from the website's join page). It is already configured in `Info.plist`.

## ✅ Checklist

- [ ] Bundle identifier matches the App ID
- [ ] Team selected, automatic signing on
- [ ] No capabilities listed
- [ ] URL type `photocards` present
- [ ] Build succeeds (⌘B)

## Next Step

→ [Set up Supabase](../SUPABASE_SETUP_GUIDE.md)
