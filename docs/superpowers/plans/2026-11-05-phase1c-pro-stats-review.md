# Phase 1c: Pro Unlock, Local Stats, App Review Package

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The store app sells a one-time Pro unlock through StoreKit (with Restore Purchases), keeps reading stats on the device for Komga sources, allows plain-http servers, and has everything App Review needs written down: demo server, review notes, listing copy.

**Architecture:** `proProvider` (Riverpod `Notifier<bool>`) is the single entitlement; the personal flavor is always Pro. A small `ProStore` interface wraps `in_app_purchase` so tests use a fake. Gates read `proProvider` and open one `ProSheet` paywall. Reading sessions on Komga sources append to a per-source JSON file (`LocalSessionStore`), and the stats providers compute `StatsSummary` from it plus mirror metadata when the source isn't a Gutter server.

**Tech Stack:** Flutter, Riverpod 3, `in_app_purchase` (new dependency, named by the spec), drift mirror, shared_preferences.

**Spec:** `docs/superpowers/specs/2026-11-05-app-store-launch-design.md` (Decisions → Pricing, Free vs Pro, Stats; Architecture → Pro gating; Constraints → App Review; audit findings).

## Global Constraints

- Pro is a **non-consumable** IAP, product id `com.ryanhaines.gutter.pro`, price set in App Store Connect at **$12.99**. No subscriptions, no external payment links.
- **Free:** one server, stream and read, two-way progress sync, basic fit modes. **Pro:** offline downloads, guided panel + spread zoom, multiple servers, stats.
- Restore Purchases is visible in the paywall and in Settings.
- Personal flavor (`!isStore`) is always Pro and never touches StoreKit.
- ATS: `NSAllowsArbitraryLoads = true` only (on iOS 10+ any other ATS key next to it makes it ignored, so `NSAllowsLocalNetworking` goes).
- No personal hostnames, IPs, credentials or reviewer passwords in the repo; review credentials live in App Store Connect only.
- Don't `dart format` whole files. Tests run as personal; store tests set `isStore = true` and reset it.

## Review Focus

- A purchase that completes while the app is closed (or on another device) must unlock after Restore or on next launch (`purchaseStream` restored/purchased events), and pending purchases must be completed (`completePurchase`) or StoreKit re-delivers them forever.
- Pro must survive offline launches (cached flag), but a refunded/revoked purchase need not be detected in v1.
- Already-downloaded comics stay readable after Pro is lost (e.g. reinstall before restore): only *new* downloads are gated.
- Stats from a Komga source must not mix with another source's sessions (per-source file).
- The personal build's stats, downloads and zoom must be unchanged.

---

### Task 1: Entitlement

**Files:**
- Create: `lib/services/pro_store.dart`, `lib/providers/pro_provider.dart`
- Modify: `pubspec.yaml` (`in_app_purchase`)
- Test: `test/providers/pro_provider_test.dart`

**Interfaces:**
- Produces: `const proProductId = 'com.ryanhaines.gutter.pro';` `abstract class ProStore { Stream<List<PurchaseDetails>> get purchases; Future<ProductDetails?> product(); Future<void> buy(ProductDetails p); Future<void> restore(); Future<void> complete(PurchaseDetails p); }` with `InAppPurchaseProStore` (real) and `proStoreProvider`; `final proProvider = NotifierProvider<ProNotifier, bool>`; `ProNotifier.buy()`, `ProNotifier.restore()`, `ProNotifier.product` (`Future<ProductDetails?>`, for the price); prefs key `pro_unlocked`.
- Behavior: `!isStore` → `true`, no store calls. Store → initial state from `pro_unlocked`; on a `purchased`/`restored` event for `proProductId`: state true, persist, `complete()` when `pendingCompletePurchase`; `error`/`canceled` events: complete if pending, state unchanged.

- [ ] **Step 1: Tests** (fake `ProStore` with a `StreamController`): `personal build is always Pro`; `store starts locked, unlocks on purchased and persists`; `restored event unlocks`; `pending purchases are completed`; `cached unlock survives a restart without store events`.
- [ ] **Step 2: Run** `flutter test test/providers/pro_provider_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** + `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: Pro entitlement backed by StoreKit`.

### Task 2: Paywall sheet and Settings row

**Files:** Create `lib/widgets/pro_sheet.dart`; modify `lib/screens/settings_screen.dart` (store only: "Gutter Pro" row → sheet; shows "Unlocked" when Pro), test `test/widgets/pro_sheet_test.dart`.

**Interfaces:** `Future<void> showProSheet(BuildContext context, {String? reason})` — title "Gutter Pro", optional `reason` line ("Downloads are part of Pro."), the four Pro features, Buy button labelled with `ProductDetails.price` (disabled with "Unavailable" when the product doesn't load), "Restore Purchases" text button, closes itself when `proProvider` turns true. `bool requirePro(BuildContext, WidgetRef, {required String reason})` returns true when Pro, else opens the sheet and returns false.

- [ ] **Step 1: Tests:** sheet shows price and Restore; tapping Restore calls the fake store's `restore`; sheet pops when Pro flips true; `requirePro` true for personal without opening anything.
- [ ] **Step 2–4:** RED, implement, GREEN + `flutter test`.
- [ ] **Step 5: Commit** `feat: Pro paywall sheet with Restore Purchases`.

### Task 3: Gates

**Files:** download entry points (`DownloadButton` tap in `issue_list_view.dart`, series download in `series_detail_panel.dart`), zoom mode picker (panels/bubbles options in the reader settings panel) and the spread step sequence (`reader_screen.dart:716` passes `isSpread` only when Pro), Stats destination/screen (non-Pro shows a Pro card instead of data), source sheet add (second source needs Pro; gains a **Komga** type with the onboarding fields).
- Test: `test/widgets/pro_gates_test.dart` (download tap without Pro opens the sheet and enqueues nothing; with Pro enqueues), zoom picker locked rows, source sheet Komga type saves auth.

- [ ] **Step 1–4:** tests RED, implement, GREEN + `flutter test` (reader suite runs as personal = Pro, unchanged).
- [ ] **Step 5: Commit** `feat: downloads, guided zoom, extra servers and stats need Pro`.

### Task 4: Local stats for Komga sources

**Files:** Create `lib/services/local_session_store.dart` (`append(LocalSession)`, `all()`; JSON list at `cache/<sourceId>/sessions.json`), `lib/services/local_stats.dart` (`StatsSummary computeLocalStats(List<LocalSession> sessions, Map<String, MirrorSeries> library, DateTime now)` and history paging); modify `KomgaClient` (constructor takes `LocalSessionStore?`; `postReadingSession` appends), `apiClientProvider`/`clientFor` (pass the store for komga), `stats_provider.dart` and `read_tab_provider.dart:43` (non-Gutter sources compute locally).
- Test: `test/services/local_stats_test.dart`: totals for all-time/this week/this month, pages per day (last 30 days), top series with names and cover from the library, streak current/longest across a gap, hour histogram, avg session; empty input gives zeroes.

- [ ] **Step 1–4:** RED, implement, GREEN + `flutter test`.
- [ ] **Step 5: Commit** `feat: reading stats on the device for Komga sources`.

### Task 5: Plain-http servers allowed

**Files:** `ios/Runner/Info.plist` (`NSAppTransportSecurity` = `{NSAllowsArbitraryLoads: true}` only), test `test/config/info_plist_test.dart` (reads the plist: arbitrary loads true, no `NSAllowsLocalNetworking`).

- [ ] **Step 1–4:** RED, edit, GREEN.
- [ ] **Step 5: Commit** `fix: allow plain-http self-hosted servers`.

### Task 6: App Review package (docs + demo server definition)

**Files:** Create `docs/app-store/review-notes.md` (what the app is; demo server URL placeholder `<demo-url>` and "credentials in App Store Connect"; how to reach Pro features — sandbox purchase; volume keys opt-in explanation for 2.5.9; why arbitrary loads: user's own self-hosted server), `docs/app-store/listing.md` (name, subtitle, description, keywords, support + privacy URLs, privacy label answers = Data Not Collected, age rating notes, IAP display name/description, screenshot checklist with public-domain content), `docs/app-store/demo-komga.md` (compose service block for the homelab stack, public-domain sources such as Digital Comic Museum, reviewer account steps). No hostnames or secrets.
- Verification: the docs name every audit finding as handled or where it lives; `listing-accuracy` check of the description against the code.

- [ ] **Step 1:** Write the three docs.
- [ ] **Step 2: Commit** `docs: App Review notes, listing and demo server`.

### Out of plan (needs the owner)

Standing up the demo Komga on the homelab (compose up behind NPM, after the owner confirms), App Store Connect setup (Paid Apps agreement, banking/tax, app record, IAP product, privacy label), screenshots, `make store-ipa` upload and TestFlight.
