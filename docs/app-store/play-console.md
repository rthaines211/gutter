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

- The upload key is `~/gutter-upload.jks` (alias `upload`). Its password is
  only in `android/key.properties` (untracked; `*.jks` and `key.properties`
  are gitignored in `android/`). Back up both files: with Play App Signing a
  lost upload key can be reset by Google, but only through support.
- `android/app/build.gradle.kts` signs release builds with that key when
  `key.properties` exists, and with the debug key when it does not.
- Build the upload with `flutter build appbundle --release`; the file is
  `build/app/outputs/bundle/release/app-release.aab`. Enrol in Play App
  Signing at the first upload.
- A git worktree has no `key.properties` (gitignored): copy it in from the
  main checkout, or the bundle is debug-signed and Play rejects it.
- Check the signer: `keytool -printcert -jarfile <aab>` must show the
  `upload` key's SHA-256. macOS has no system Java; set
  `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`.

## Play requirements (checked 2026-11-25)

- Target API: 36 (Flutter's default). Play requires 36 for new apps and
  updates from 2026-08-31.
- Billing: `in_app_purchase_android` 0.5.0 bundles Play Billing 8.0.0,
  supported until 2027-08-31. Billing 7 stops on 2026-08-31.
- 16 KB pages: every `.so` in the bundle has LOAD alignment of 16 KB or more
  (NDK 28, AGP 8.11).
- Merged release manifest permissions: INTERNET, ACCESS_NETWORK_STATE,
  WAKE_LOCK, RECEIVE_BOOT_COMPLETED and FOREGROUND_SERVICE (WorkManager /
  background_downloader), BILLING. No runtime (dangerous) permissions and no
  typed `FOREGROUND_SERVICE_*` permission, so there is no foreground-service
  declaration to file. If Play Console asks anyway: downloads the user starts
  (data sync).
- Data safety: Play Billing pulls in Google's `datatransport` (billing
  telemetry that Google sends). The app itself sends nothing to the developer.
- Privacy policy URL: `https://getgutter.app/privacy`.
