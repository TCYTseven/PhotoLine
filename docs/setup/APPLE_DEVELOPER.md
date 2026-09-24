# Apple Developer Setup

**Time**: 15 min | **Cost**: $99/year

## 1. Enroll in the Apple Developer Program

1. Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll)
2. Sign in → **Start Your Enrollment**, choose **Individual** or **Organization**, pay
3. Wait for the approval email (usually 24–48 hours)

## 2. Create the App ID

1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers** → **(+)**
2. **App IDs** → **App** → **Continue**
3. Fill in:
   - **Description**: `PhotoCards`
   - **Bundle ID** (explicit): the identifier you set in Xcode. `app.photocards.ios` is the repository default; change it to one you own, e.g. `com.yourname.photocards`
   - **Capabilities**: **none**. PhotoCards uses guest sign-in only, sends no push notifications and has no purchases, so it needs no Sign in with Apple, Push Notifications or In-App Purchase capability. Leave them off: an entitlement the app never uses complicates provisioning and invites review questions.
4. **Continue** → **Register**

With automatic signing (step 3 of the [Xcode guide](./XCODE_CONFIG.md)) Xcode can create the App ID for you instead.

## 3. Create the app in App Store Connect

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **(+)** → **New App**
2. Platform **iOS**, name **PhotoCards** (must be unique on the store), primary language, the Bundle ID above, SKU e.g. `PHOTOCARDS1`
3. Continue with the [submission checklist](../APP_STORE_COMPLIANCE.md#submission-checklist)

## ✅ Checklist

- [ ] Apple Developer enrollment approved
- [ ] App ID registered, no extra capabilities
- [ ] App Store Connect app created

## Next Step

→ [Configure Xcode](./XCODE_CONFIG.md)
