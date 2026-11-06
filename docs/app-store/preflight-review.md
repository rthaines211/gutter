# Preflight review: Gutter store flavor (2026-11-06)

Audited `origin/main` at `a0771cf` against the App Store Review Guidelines
(`appstore-review` skill) and for 4.3 similarity (`app-similarity` skill).
This covers the store flavor only: `isStore`, bundle `com.ryanhaines.gutter`.

## Fixed in this PR

- **5.1.1 / ITMS-91053: privacy manifest had no DiskSpace reason.**
  `AppDelegate.swift` reads `volumeAvailableCapacityForImportantUsageKey`
  (the `freeSpace` channel). `series_download_sheet.dart` shows the value
  ("N free on this iPad") and blocks a download that does not fit. Added
  `NSPrivacyAccessedAPICategoryDiskSpace` with `E174.1` (check space before
  writing) and `85F4.1` (show to the user).

## Remaining, ranked by rejection risk

1. **2.1 / 4.2: no server for the reviewer (blocker).** The store build has
   no default server. The demo Komga (`docs/app-store/demo-komga.md`) must be
   live, HTTPS, public-domain only, and up for the whole review. Put the URL in
   `review-notes.md` → `<demo-url>` and the login in Sign-In Information.
   Check it from outside the LAN (cellular) before you submit.
2. **2.1 / 3.1.1: the IAP must load in review (blocker).** The Pro sheet
   shows "Unavailable" when `com.ryanhaines.gutter.pro` does not load. In ASC:
   create the non-consumable, give it a review screenshot, attach it to 1.0
   and submit it with the version. The code is fine: StoreKit only, Restore
   Purchases on the sheet, localized price, no external payment links.
3. **5.2.1: risk of a piracy reading (judgment call).** A reader for any
   server can look like a piracy tool. Use only public-domain comics in
   screenshots, on the demo server and in the listing. Say "works with Komga",
   never put Komga in the name.
4. **1.6 / ATS: `NSAllowsArbitraryLoads = true` (judgment call, not changed).**
   This is needed for self-hosted HTTP servers on public hostnames, and
   `review-notes.md` already gives the reason. Do NOT add
   `NSAllowsLocalNetworking` beside it: on iOS 10+ that key makes iOS ignore
   `NSAllowsArbitraryLoads`, which breaks plain HTTP to non-local hosts. Optional
   later: warn when the user types a non-LAN `http://` URL (Basic auth in
   clear text).
5. **2.5.9: volume keys (low).** The default is off in store builds
   (`reader_settings.dart:66`, test-covered) and the reason is in the review
   notes. Edge case: a Gutter server that already has `volume_keys: true` saved
   turns it on, but that is the user's own earlier choice.
6. **5.1 privacy policy (process).** The in-app link is present (More/Settings
   → Privacy → `PRIVACY.md` on GitHub). Put the same URL in the ASC Privacy
   Policy URL field and the Issues URL as the Support URL. The App Privacy
   label is "Data Not Collected". That matches the manifest (no tracking, no
   collected types).
7. **2.3.1 / ITMS-90078 (info).** The store binary still contains personal
   code (push bridge, Claude webview, Recap, labeller). A compile-time
   `isStore` gates all of it: push registration (`main.dart`), Claude
   (`onClaude: !isStore`), Recap (`onRecap: … && !isStore`), Diagnostics/log
   viewer, Remote, and the store-hidden nav destinations (`NavigationNotifier.go`
   sends them to Read). There is no runtime toggle. Expect an email warning
   about `registerForRemoteNotifications` without `aps-environment`. It does
   not block.
8. **Archive with `make store-ipa` only (process).** Without the Makefile,
   `Flavor.xcconfig` is missing or personal, and the bundle ID and display name
   are wrong.

## Checked and fine

- `ITSAppUsesNonExemptEncryption = false` (HTTPS only, exempt).
- `NSLocalNetworkUsageDescription` is present and specific. No other usage
  strings are needed (no camera, photos, location or contacts). There are no
  Bonjour services, so no `NSBonjourServices`.
- No background modes are declared. `background_downloader` uses a
  background URLSession, which needs none.
- No ads, analytics, ATT, third-party login (Sign in with Apple N/A), or
  account creation (account deletion N/A).
- Personal-only name strings are gated: `appName` gives Gutter, and the
  tagline gives "Your comics, your server." in store builds.
- The bedtime row opens an iCloud Shortcut only when the user taps it. That
  is fine.
- The flavor gating tests (14 files with `isStore = true`) pass.

## 4.3 similarity

- **Personal flavor (`com.ryanhaines.comicReaderApp`, "Longbox").** It is the
  same codebase, icon and assets on the same developer account, but it is
  never submitted to the App Store. It installs through a development profile
  and `devicectl`. It is not an App Store app, so 4.3 does not apply. Keep it
  that way: do not submit it, and do not distribute it through TestFlight
  external testing under a separate listing.
- **`~/projects/_archive/comic_reader_app`** (the predecessor repo) shares 86%
  of its source and 22 of 23 assets. It is the same app and was never
  submitted. No risk unless someone submits it.
- **LCS reference app (`com.localcomicserver.lcs`)** shares 0 source and 0
  assets.
- Unmeasured: store metadata and screenshots (no fastlane layout) and the
  icon look (Pillow is not installed). The two flavors use the same AppIcon,
  which only matters if the personal one ever ships.
- **Account check (do this by hand in ASC):** confirm that Gutter is the only
  app on the account with a submitted or live version, and that no earlier
  comic-reader record was rejected under 4.3.
