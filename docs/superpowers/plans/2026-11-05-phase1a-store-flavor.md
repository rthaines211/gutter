# Phase 1a: Store Flavor, Onboarding & Review Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One codebase builds two apps: `personal` (today's app, unchanged on the owner's iPad) and `store` (the default). The store app has no default server, onboards a stranger to their own Go backend, hides personal-only features, and clears the App Review blockers that don't depend on Komga or StoreKit.

**Architecture:** A runtime flavor flag (`isStore`, from `--dart-define=FLAVOR=personal`, store by default) gates Dart code, following the existing `builtInApiKey` pattern so tests can flip it. The native side gets its bundle ID, display name and entitlements from a small xcconfig that the Makefile writes before every build, so the two flavors install side by side. First launch with no server URL shows `OnboardingScreen` in place of `AppShell`.

**Tech Stack:** Flutter/Dart, flutter_riverpod 3, Xcode xcconfig, Make.

**Spec:** `docs/superpowers/specs/2026-11-05-app-store-launch-design.md` (sections "Architecture", "App Review audit findings", "Anti-goals").

**Scope:** This is plan 1 of 3 for Phase 1. **1b** adds the Komga adapter (and Komga as an onboarding choice). **1c** adds StoreKit Pro, local settings/stats for Komga sources, the demo server and the review notes. Not in 1a: lowering the iOS 26 deployment target (the spec says "consider"; skip it), Go backend auth (Phase 3), the stale `ios/Pods/UnrarKit` (it disappears on the next `pod install` and isn't tracked).

## Global Constraints

- Store is the default flavor. Personal = `--dart-define=FLAVOR=personal`, passed only by the Makefile's personal targets.
- Personal bundle ID stays `com.ryanhaines.comicReaderApp` so `make ipad` upgrades in place and keeps the mirror DB, downloads and server URL. Store bundle ID: `com.ryanhaines.gutter`.
- Display names: personal `Longbox`, store `Gutter`.
- The repo is public: no hostnames, Tailscale IPs, UDIDs or keys in tracked files.
- Store build: no default server, no `PUSH_API_KEY`, no `aps-environment` entitlement.
- Don't `dart format` whole files (the repo isn't format-clean).
- No device or simulator builds by the implementer. This Mac is the homelab. The owner runs `make ipad` and `make store-ipad` at the end.
- Gate every task on `flutter analyze --no-fatal-infos` and `flutter test` passing.

## Review Focus

1. **Server URL typed without a scheme or with a trailing slash** (`192.168.1.5:8080`, `comics.example.com/`): connect should work, not fail on `Uri.parse`. Covered by Task 4's `normalizeServerUrl` tests.
2. **Plain-http LAN server** (`http://nas.local:8080`): ATS must not block it. Covered by Task 5's `NSAllowsLocalNetworking` plus a `plutil` check.
3. **A deep link or banner that navigates to a hidden destination** (scan banner → Review, push tap → Creators): it must land on Read, not a blank screen. Covered by Task 2's `NavigationNotifier.go` redirect test.
4. **Personal build regression**: a personal build must keep its bundle ID, its push key and the volume-key default the server stored. Covered by Task 1's build-settings check and Task 3's `fromJson` personal test.
5. **Unreachable server at onboarding** (wrong port, device offline): show an error and stay on onboarding, without saving the bad URL. Covered by Task 4's failing-probe widget test.

---

### Task 1: Flavor flag and native flavor config

**Files:**
- Create: `lib/config/flavor.dart`
- Create: `ios/Runner/Store.entitlements` (a plist with an empty `<dict/>`)
- Modify: `ios/Flutter/Release.xcconfig`, `ios/Flutter/Debug.xcconfig` (append `#include? "Flavor.xcconfig"`)
- Modify: `ios/Runner.xcodeproj/project.pbxproj`, the three Runner target configs only (lines ~486/495, ~673/682, ~697/706): `PRODUCT_BUNDLE_IDENTIFIER = "$(GUTTER_BUNDLE_ID)";` and `CODE_SIGN_ENTITLEMENTS = "$(GUTTER_ENTITLEMENTS)";`. Leave the RunnerTests configs alone.
- Modify: `ios/Runner/Info.plist`: `CFBundleDisplayName` → `$(GUTTER_DISPLAY_NAME)`, `CFBundleName` → `Gutter`
- Modify: `Makefile`, `.gitignore` (add `ios/Flutter/Flavor.xcconfig`)
- Modify: `lib/app.dart:23` (`title: appName`)
- Create: `test/flutter_test_config.dart` (`testExecutable` sets `isStore = false`, then runs the test file). `flutter test` passes no FLAVOR, so without this every existing test would suddenly run as the store app. Store tests opt in with `isStore = true` and reset it to `false` in `tearDown`.
- Test: `test/config/flavor_test.dart`

**Interfaces:**
- Produces: `bool isStore` (top-level, `@visibleForTesting`, mutable, defaults to `const String.fromEnvironment('FLAVOR') != 'personal'`) and `String get appName` (`'Gutter'` / `'Longbox'`), both in `lib/config/flavor.dart`. Every later store test sets `isStore = true` and resets it to `false` in `tearDown`.

- [ ] **Step 1: Write the failing test**

```dart
// test/config/flavor_test.dart
tearDown(() => isStore = false);
test('tests run as the personal app by default', () => expect(isStore, isFalse)); // flutter_test_config
test('appName follows the flavor', () {
  expect(appName, 'Longbox');
  isStore = true;
  expect(appName, 'Gutter');
});
```

- [ ] **Step 2:** Run `flutter test test/config/flavor_test.dart`. Expected: FAIL, `flavor.dart` not found.
- [ ] **Step 3:** Create `lib/config/flavor.dart` with the two symbols above, plus `test/flutter_test_config.dart`. Copy the doc-comment style from `builtInApiKey` in `lib/providers/source_provider.dart`. Point `MaterialApp.title` at `appName`.
- [ ] **Step 4:** Run the test. Expected: PASS.
- [ ] **Step 5: Makefile.** Add a `flavor-xcconfig` helper that writes `ios/Flutter/Flavor.xcconfig` with three lines, `GUTTER_BUNDLE_ID`, `GUTTER_DISPLAY_NAME` and `GUTTER_ENTITLEMENTS`. Values:
  - personal: `$(BUNDLE_ID)` / `Longbox` / `Runner/Runner.entitlements`
  - store: `com.ryanhaines.gutter` / `Gutter` / `Runner/Store.entitlements`

  Wiring:
  - Every existing `ipad-*` / `iphone-*` build target writes the personal file first and adds `--dart-define=FLAVOR=personal` to `DART_DEFINES`.
  - New `store-ipad` target: `check unlock`, write the store file, `flutter build ios --release` with no `DART_DEFINES`, then `$(call install_to,$(IPAD_DEVICE_ID))`.
  - New `store-ipa` target: write the store file, then `flutter build ipa --release`.
  - Add both to `.PHONY`.
  - The Makefile writes the file before every build. A missing file must fail loudly: the pbxproj has no fallback value, so an empty `GUTTER_BUNDLE_ID` breaks signing at once and can't silently ship the wrong ID.
- [ ] **Step 6: Verify the native wiring (cheap, no build).** Write the personal file by hand, then run `xcodebuild -project ios/Runner.xcodeproj -target Runner -configuration Release -showBuildSettings 2>/dev/null | grep -E 'PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_ENTITLEMENTS|GUTTER_DISPLAY_NAME'`. Expected: `com.ryanhaines.comicReaderApp`, `Runner/Runner.entitlements`, `Longbox`. Write the store file, run it again, and expect `com.ryanhaines.gutter`, `Runner/Store.entitlements`, `Gutter`. Then `plutil -lint ios/Runner/Info.plist ios/Runner/Store.entitlements` should print OK.
- [ ] **Step 7:** Run `flutter analyze --no-fatal-infos && flutter test`, then commit (`feat: personal/store build flavors`).

### Task 2: Hide personal-only features in the store flavor

**Files:**
- Modify: `lib/providers/navigation_provider.dart` (add `storeHiddenDestinations`; `go` and `setTabIndex` redirect hidden destinations to `read`)
- Modify: `lib/widgets/icon_rail.dart:62` (also skip `storeHiddenDestinations` when `isStore`)
- Modify: `lib/widgets/floating_tab_bar.dart:47` (hide tabs 2 and 3 when `offline || isStore`; the offline dot still keys on `offline` only)
- Modify: `lib/widgets/sidebar_v2.dart:75` (skip the Creators row when `isStore`)
- Modify: `lib/screens/more_screen.dart:121` (Remote row: `if (online && !isStore)`)
- Modify: `lib/screens/settings_screen.dart:207` (Label pages row) and `:336` (Diagnostics section): both `if (!isStore)`
- Modify: `lib/screens/reader_screen.dart`: `onRecap` (:1755) and `onClaude` (:2179) are null when `isStore`; `_flaggablePage()` (:1789) returns null when `isStore` (that removes both the flag button and the two-finger flag)
- Modify: `lib/main.dart:77`: skip the whole `PushService` post-frame block when `isStore`
- Test: `test/providers/navigation_provider_test.dart`, `test/widgets/icon_rail_test.dart`, `test/widgets/floating_tab_bar_test.dart`

**Interfaces:**
- Consumes: `isStore` (Task 1).
- Produces: `const storeHiddenDestinations = {NavDestination.creators, NavDestination.review};` in `navigation_provider.dart`.

- [ ] **Step 1: Write the failing tests** (each sets `isStore = true` and resets it to `false` in `tearDown`, so existing tests keep testing the personal app):

```dart
// navigation_provider_test.dart
test('store: going to a hidden destination lands on Read', () {
  isStore = true;
  final c = ProviderContainer(); addTearDown(c.dispose);
  c.read(navigationProvider.notifier).go(NavDestination.review);
  expect(c.read(navigationProvider), NavDestination.read);
  c.read(navigationProvider.notifier).setTabIndex(2);
  expect(c.read(navigationProvider), NavDestination.read);
});

// icon_rail_test.dart — pump IconRail the way the existing test does
testWidgets('store: no Creators or Review in the rail', (t) async {
  isStore = true; /* pump */
  expect(find.text('Creators'), findsNothing);
  expect(find.text('Review'), findsNothing);
  expect(find.text('Library'), findsOneWidget);
});

// floating_tab_bar_test.dart
testWidgets('store: three tabs, Read Library More', (t) async {
  isStore = true; /* pump FloatingTabBar(currentIndex: 0, onTap: (_) {}) */
  expect(find.text('Creators'), findsNothing);
  expect(find.text('Review'), findsNothing);
  expect(find.text('More'), findsOneWidget);
});
```

- [ ] **Step 2:** Run those three files. Expected: the new tests FAIL, the existing ones pass.
- [ ] **Step 3:** Make the edits listed under **Files**. The redirect in `go` is the one root-cause guard, covering the scan banner, push taps and anything else that calls `go`. The rail, tab bar and sidebar changes only hide the visible entries.
- [ ] **Step 4:** Run the three files. Expected: all PASS.
- [ ] **Step 5:** Run `flutter analyze --no-fatal-infos && flutter test`, then commit (`feat: hide personal-only features in the store flavor`).

### Task 3: Volume keys default off in the store flavor

**Files:**
- Modify: `lib/models/reader_settings.dart:32` (constructor default `false`) and `:63` (`json['volume_keys'] as bool? ?? !isStore`)
- Test: `test/models/reader_settings_test.dart`

**Interfaces:** Consumes `isStore`.

- [ ] **Step 1: Write the failing tests**

```dart
tearDown(() => isStore = false);
test('volume keys default off (const and store fromJson)', () {
  isStore = true;
  expect(const ReaderSettings().volumeKeys, isFalse);
  expect(ReaderSettings.fromJson({}).volumeKeys, isFalse);
});
test('personal: a server with no stored volume_keys still means on', () {
  expect(ReaderSettings.fromJson({}).volumeKeys, isTrue);
});
test('a stored value always wins', () {
  expect(ReaderSettings.fromJson({'volume_keys': true}).volumeKeys, isTrue);
});
```

- [ ] **Step 2:** Run the test file. Expected: the first test FAILS.
- [ ] **Step 3:** Make the two edits. Fallback `const ReaderSettings()` call sites (shown while settings load) now read volume keys as off; that's intended.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit (`fix: volume keys opt-in in the store flavor (guideline 2.5.9)`).

### Task 4: First-run onboarding

**Files:**
- Create: `lib/screens/onboarding_screen.dart`
- Modify: `lib/app.dart` (`home:` watches `activeSourceProvider`; empty `baseUrl` → `OnboardingScreen()`, else `AppShell()`)
- Test: `test/screens/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.checkConnection()` (`lib/services/api_client.dart:503`), `SourceListNotifier.updateDefaultUrl(String)`, `serverConfigProvider.deviceId`, `appName`.
- Produces:
  - `String normalizeServerUrl(String input)`, top-level in `onboarding_screen.dart`.
  - `OnboardingScreen({Key? key, Future<bool> Function(String url)? probe})`. `probe` defaults to `ApiClient(baseUrl: url, deviceId: …).checkConnection()`. 1b adds a server-type choice to this screen.

- [ ] **Step 1: Write the failing tests**

```dart
test('normalizeServerUrl', () {
  expect(normalizeServerUrl(' comics.example.com/ '), 'https://comics.example.com');
  expect(normalizeServerUrl('192.168.1.5:8080'), 'https://192.168.1.5:8080');
  expect(normalizeServerUrl('http://nas.local:8080/'), 'http://nas.local:8080');
  expect(normalizeServerUrl('https://x.example.com/api//'), 'https://x.example.com/api');
});

testWidgets('unreachable server: error shown, URL not saved', (t) async {
  // pump OnboardingScreen(probe: (_) async => false) in a ProviderScope with the
  // shared-prefs + secure-storage mocks from app_shell_test.dart
  await t.enterText(find.byType(TextField), 'nope.example.com');
  await t.tap(find.text('Connect')); await t.pump();
  expect(find.textContaining("Couldn't reach"), findsOneWidget);
  expect(container.read(activeSourceProvider).baseUrl, isEmpty);
});

testWidgets('reachable server: saved as the default source', (t) async {
  // same, probe: (_) async => true
  expect(container.read(activeSourceProvider).baseUrl, 'https://comics.example.com');
});
```

- [ ] **Step 2:** Run the test file. Expected: FAIL, file not found.
- [ ] **Step 3: Implement.**
  - `normalizeServerUrl`: trim, add `https://` when there's no `scheme://`, strip trailing slashes.
  - Screen layout: the `LongboxMark`, the title `appName`, one line of copy ("Connect to your Gutter server"), a URL `TextField` (`keyboardType: url`, `autocorrect: false`) and a **Connect** button. The button shows a progress indicator while probing and is disabled while the field is empty.
  - Success: `updateDefaultUrl(url)`. `app.dart` then rebuilds to `AppShell`; the screen does not push.
  - Failure: `Couldn't reach a server at <url>. Check the address and that the server is running.`
- [ ] **Step 4:** Run the test file. Expected: PASS.
- [ ] **Step 5:** Run `flutter analyze --no-fatal-infos && flutter test` (the personal path is unchanged: the `DEFAULT_SERVER_URL` seed keeps `baseUrl` non-empty), then commit (`feat: first-run onboarding (no default server)`).

### Task 5: App Review package: privacy manifest, Info.plist, icon, privacy policy

**Files:**
- Create: `ios/Runner/PrivacyInfo.xcprivacy`, then register it in `project.pbxproj`: a `PBXFileReference`, a `PBXBuildFile`, an entry in the Runner group's `children` and an entry in the Runner target's Resources build phase. Copy how `Info.plist`/`Assets.xcassets` appear there.
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
- Create: `PRIVACY.md` (repo root)
- Modify: `lib/screens/more_screen.dart` (a "Privacy" row in the last group, opening a bottom sheet with the policy text and the GitHub URL)

**Values (from the spec's audit):**
- `PrivacyInfo.xcprivacy`:
  - `NSPrivacyTracking` false, `NSPrivacyTrackingDomains` empty, `NSPrivacyCollectedDataTypes` empty.
  - `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, and `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`.
- `Info.plist` additions:
  - `ITSAppUsesNonExemptEncryption` = false.
  - `NSLocalNetworkUsageDescription` = "Gutter connects to comic servers on your local network."
  - `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = true. This lets plain-http `.local`/LAN servers through and keeps ATS everywhere else.
- `PRIVACY.md`: Gutter collects no data. It talks only to servers you add, stores settings and downloads on your device, and has no analytics, ads or tracking. Contact: GitHub issues at `https://github.com/rthaines211/gutter/issues`. The More row shows the same text and links to `https://github.com/rthaines211/gutter/blob/main/PRIVACY.md`, which is also the URL for App Store Connect.

- [ ] **Step 1:** Flatten the icon. Run `sips -s format jpeg -s formatOptions 100 <icon> --out "$TMPDIR/icon.jpg" && sips -s format png "$TMPDIR/icon.jpg" --out <icon>`. Verify `sips -g hasAlpha <icon>` prints `hasAlpha: no`, and look at the result to check that no edge colour changed.
- [ ] **Step 2:** Add the plist keys and the privacy manifest. Verify `plutil -lint ios/Runner/Info.plist ios/Runner/PrivacyInfo.xcprivacy` prints OK and `xcodebuild -project ios/Runner.xcodeproj -list` still parses.
- [ ] **Step 3: Write the failing widget test** in `test/screens/more_screen_privacy_test.dart`: pump `MoreScreen` (with the mocks from `app_shell_test.dart`), tap `find.text('Privacy')`, then expect `find.textContaining('collects no data')` to find one widget.
- [ ] **Step 4:** Run it. Expected: FAIL.
- [ ] **Step 5:** Write `PRIVACY.md` and the More row and sheet. Keep the policy text in one Dart const so the sheet and the test share it.
- [ ] **Step 6:** Run `flutter analyze --no-fatal-infos && flutter test`. Expected: PASS. Commit (`chore: App Review package: privacy manifest, ATS, icon, privacy policy`).

### Task 6: Owner check on device

Not for the implementer (it needs the keychain and devices).

- [ ] `make ipad`: the personal app upgrades in place, the library is intact, push still registers, and Creators/Review/Remote/Claude are present.
- [ ] `make store-ipad`: a second app named "Gutter" installs alongside it. It opens to onboarding. Entering the backend URL lands on the Library. No Creators/Review/Remote/Label/Claude/Recap, and volume keys are off.
- [ ] Update `CLAUDE.md` Build & Run with the `store-ipad` / `store-ipa` targets and the `isStore` flag.
