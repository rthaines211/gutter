# Google Play setup

What the Android build expects in Play Console. Keep it true to the build.

## App

- Package name: `com.ryanhaines.gutter` (same as the iOS store bundle id).
  Play never lets you change it after the first upload.
- App name: Gutter. Category: Comics. Free, with an in-app product.
- Data safety: no data collected by the developer; the app talks only to the
  user's own servers (match `PRIVACY.md`).

## Pro product

- Monetize → Products → **In-app products** → Create product (a one-time
  product, *not* a subscription).
- Product ID: `com.ryanhaines.gutter.pro`, exactly the iOS id
  (`proProductId` in `lib/services/pro_store.dart`). Play allows lowercase,
  digits, `_` and `.`, so the id is valid as is.
- Name "Gutter Pro"; price to match the App Store ($12.99 tier); activate it.
- It is non-consumable in practice: the app never consumes it. `ProNotifier`
  acknowledges it (`completePurchase`) on delivery and calls
  `restorePurchases` at every launch on Android, because Play does not
  re-deliver purchases at launch like StoreKit and refunds purchases left
  unacknowledged for 3 days.
- Products only load for builds installed from Play (internal or closed
  testing track) and signed with the upload key; a sideloaded debug APK shows
  "Unavailable" on the Pro sheet. Add testers as license testers (Setup →
  License testing) to buy without being charged.

## Release path for a new personal developer account

1. Upload an AAB (`flutter build appbundle`) to **Internal testing** first to
   check purchases.
2. **Closed testing** with at least 12 opted-in testers for 14 consecutive
   days. Production access can be requested only after that.
3. Then production.

## Signing

- Create an upload key (`keytool -genkey -v -keystore ~/gutter-upload.jks
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload`), keep it out of
  the repo (`*.jks` and `key.properties` are gitignored in `android/`), and
  enrol in Play App Signing.
- `android/app/build.gradle.kts` still signs release with the debug key; wire
  it to `key.properties` before the first upload.
