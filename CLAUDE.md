# Comic Reader App

Flutter-based comic reader for iPad that connects to a local backend API server.

## Tech Stack

- Flutter SDK ^3.11.0, Dart
- State management: flutter_riverpod ^3.3.1
- Image caching: cached_network_image ^3.4.1
- HTTP: http ^1.6.0
- Persistence: shared_preferences ^2.5.5
- Volume keys: flutter_volume_controller ^1.3.4
- Charts: fl_chart ^0.70.2

## Architecture

- **Riverpod providers** for all state management (browse, library, reader, settings, reading_list)
- **Service layer**: `ApiClient` (HTTP), `PagePrefetcher` (intelligent page preloading)
- **Models** with JSON serialization (fromJson/toJson)
- Screens → Widgets → Providers → Services → API
- **Local-first mirror**: a drift database per source (`lib/services/mirror/`) is the source of truth for Library, Read tab, and series detail — providers stream from it. `SyncEngine` does push-then-pull (outbox = `SyncQueue`) on launch, resume, online transition, refresh gestures, and after mutations. Covers sync to `<docs>/covers/<sourceId>/` and are rendered by `SeriesGridTile` with network fallback. Library filter/sort/facets are computed locally (`library_view.dart`). Progress writes are local-first: write to the mirror first, then PUT to the server, enqueue on failure.
- **Pro** (`proProvider`, `lib/providers/pro_provider.dart`): one non-consumable IAP `com.ryanhaines.gutter.pro` via `in_app_purchase` behind `ProStore` (tests fake it). Personal = always Pro. `main.dart` reads it at launch so StoreKit re-deliveries are caught. Gates call `requirePro(context, ref, reason:)` (opens `ProSheet`): new downloads, Panels/Bubbles zoom (Komga gets Panels only, found on the device by `panel_detector.dart`), spread steps, adding a server, the Stats screen. Komga sessions go to `cache/<sourceId>/sessions.json` (`LocalSessionStore`, serialized appends) and stats are computed locally (`local_stats.dart`). App Store copy lives in `docs/app-store/`; keep it true to the build.
- **Komga sources** (`SourceType.komga`): `apiClientProvider` returns `KomgaClient extends ApiClient`, which overrides only what the mirror, reader, progress and downloads call. `fetchSync` is a full pull (`POST /api/v1/series/list` + `/books/list`, unpaged) mapped into the `/sync` shape; `serverHasQueues: false` keeps local queues. Komga pages are 1-based (`pageUrl`, `SourceUrls.page`, downloads); completed progress maps to `current_page == total_pages`. `isCustomSourceProvider` now means "Gutter server" and gates server-only features (collections, rename, metadata edit, templates, rescan, chapter detect; in the reader: Chapters, Clip a panel, creator links in Credits, and panel/balloon fetches). Komga Credits come from the book's own authors (`KomgaClient.fetchIssueCredits`); `hasMirrorProvider` means "syncs into the mirror". Image loads and cover sync add credentials via `SourceAuthClient` (the global `CachedNetworkImageProvider.defaultCacheManager`), same-origin only; build cover/page URLs with `SourceUrls` (`source_url_guard_test` fails on hardcoded `/comics/$id/cover`).
- **Offline mode** (`connectivityProvider` false): online-only destinations (`onlineOnlyDestinations`: Creators, Review, Stats) hide from the rail/tab bar, as do More's Remote/Stats rows and the reader's Claude button; Library tiles dim when no issue is on the device (`onDeviceProvider`) or badge "N on iPad"; Read-tab shelves keep only on-device comics; the banner reads "Offline · N comics on this iPad" and taps to Downloads (only from root screens).
- **Intentional sort change**: local recent/recently_read/unread sorts use natural direction (desc = newest/most first), unlike the legacy server's pre-inverted comparators. Do not "fix" this back.

## Project Structure

```
lib/
  config/       # AppTheme, ServerConfig, LayoutBreakpoint, string_utils
  models/       # Series, ComicFile, ComicInfo, ReadingProgress, etc.
  providers/    # Riverpod providers and notifiers (settings, library, reader, sidebar, etc.)
  screens/      # ReaderScreen, LibraryScreen, BrowseScreen, SeriesDetailScreen, etc.
  services/     # ApiClient, PagePrefetcher, PanSequenceController, display_rect_calculator, page_transform_calculator, spread_detector
  widgets/      # PageReader, ScrollReader, ZoomWrapper, SeriesDetailPanel, ShimmerBox, StaggeredEntry, IpadSidebar, etc.
test/           # Unit tests (page_prefetcher_test.dart)
docs/           # Design specs and implementation plans
```

## Build & Run

- `make ipad` / `make iphone` — release build installed to the device (IDs in `Makefile.local`); `-debug` variants for debug builds
- **Two flavors, one codebase.** `isStore` (`lib/config/flavor.dart`) is true unless built with `--dart-define=FLAVOR=personal`, which only the Makefile's personal targets pass. Store hides personal-only features (push, Claude, Review, Creators, Arcs, Remote, labeller, Recap, log viewer), has no default server (first launch shows `OnboardingScreen`) and defaults volume keys off. `NavigationNotifier.go` redirects store-hidden destinations to Read. Tests run as personal (`test/flutter_test_config.dart`); store tests set `isStore = true` and reset it.
- Bundle id, home-screen name and entitlements come from `ios/Flutter/Flavor.xcconfig` (untracked), which the Makefile writes before every build: personal = `com.ryanhaines.comicReaderApp`/Longbox/push entitlement, store = `com.ryanhaines.gutter`/Gutter/no entitlements. `make store-ipad` installs the store app beside the personal one; `make store-ipa` archives it. `flutter run` uses whichever Flavor.xcconfig the last `make` wrote, and signing fails if there is none.
- Installs use `xcrun devicectl device install app`, which upgrades in place and keeps the app's data (server URL, mirror DB, downloads). Don't use `flutter install` — it uninstalls first and wipes everything.
- Personal builds read device IDs, the push key and the default server from the untracked `Makefile.local` (see `CLAUDE.local.md`). Without it the build has no default server and no baked-in push key.
- `unlock` runs first and only prompts for the login password when the keychain is actually locked.
- `make devices` — list connected devices
- `make clean` — clean build artifacts
- `flutter run -d <device-id>` — debug build with live log streaming (required for debugPrint output)
- `make ipad-debug` does NOT stream logs — it only builds and installs
- Non-interactive build (keychain already unlocked): `make -o unlock ipad-release`. To leave uncommitted work out of the build, run it from a `git worktree add --detach … origin/main` checkout.
- The repo isn't `dart format`-clean: don't format whole files you edit, or the diff fills with unrelated reformatting.
- Codesigning errors (`errSecInternalComponent`): run `security lock-keychain ~/Library/Keychains/login.keychain-db && security unlock-keychain ~/Library/Keychains/login.keychain-db`. If that fails, run `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k YOUR_PASSWORD ~/Library/Keychains/login.keychain-db`
- Prevent recurring keychain lock: `security set-keychain-settings ~/Library/Keychains/login.keychain-db` (disables auto-lock timeout)
- An empty server scans on first start; `/library/refresh/status` reports progress (the Library shows it).

## Backend API

Configurable base URL (no built-in default in public builds). Backend: the Go/SQLite server, a separate repo. Every endpoint needs `Authorization` (Basic with any username + `GUTTER_PASSWORD`, or `Bearer GUTTER_API_KEY`); `/healthz` is open; `GET /` is the status page. Key endpoints:

- `GET /browse?path=` — file system browsing
- `GET /comics/{id}/pages/{num}` — comic page images
- `GET /comics/{id}/cover` — cover thumbnail (low res)
- `GET /comics/{id}/info` — comic metadata
- `GET /library` — series library (supports sort, filter, search, facet params)
- `GET /sync?since=<unix_ms>` — delta sync: changed series with inline issues, changed progress, full series_ids/progress_ids lists for pruning, and a server_time watermark in unix ms
- `GET /facets/{facet}` — distinct values for publisher/writer/genre/year with filter-aware counts
- `PUT /reading/{id}` — save reading progress + bookmarks; optional read_at (unix ms) — server returns 409 if not newer than stored read_at (outbox drops 409s as resolved)
- `PUT /reading/batch` — batch update progress (mark series read)
- `DELETE /reading/batch` — batch delete progress (mark series unread)
- `GET /reading` — reading list (in_progress items with currentPage)
- Note: `GET /reading/{id}` for single comic progress does NOT exist — use the list endpoint or pass progress from the caller
- `GET/POST /collections`, `PUT/DELETE /collections/{id}` — user-created series collections
- `POST /collections/{id}/series`, `DELETE /collections/{id}/series/{seriesId}` — collection membership
- `GET/POST /presets`, `PUT/DELETE /presets/{id}`, `POST /presets/{id}/reset` — reader presets (auto-seeds 3 defaults)
- `GET/POST /smart-filters`, `PUT/DELETE /smart-filters/{id}`, `GET /smart-filters/{id}/series` — rule-based filters
- `POST /reading/sessions` — record a reading session (comic_id, series_id, started_at, pages_read, duration_s; rejects <5s)
- `GET /stats/summary` — pre-computed dashboard (all-time/week/month totals, pages-per-day, top genres/publishers)
- `GET /stats/history?page=1&limit=20` — paginated reading session log with series enrichment
- `GET /creators` — library creators (series-level enrichment), with id, name, roles and seriesIds
- `GET /creators/{personId}` — header + bibliography (CV volumes, owned/partial/none). Bibliography is null when there's no localcv or the index is still building (`bibliographyPending`)
- `GET /creators/lookup?name=` — person matches for id-0 credits
- `GET /creators/volumes/{id}` — unowned volume detail
- `GET /creators/issues/{comicId}` — per-issue credits; 404 when there's no CV issue id
- The credits index is a sidecar `creators_index.db` next to `localcv.db`, rebuilt in the background when localcv's size or mtime changes (~15s)
- Marking as unread = DELETE the progress record. Setting currentPage=0 with totalPages>0 makes it "in progress", not "unread".
- Errors are JSON: {"error": "message"}; 500 bodies are generic (detail is server-logged).

## Responsive Layout

- Breakpoint: `LayoutBreakpoint.isTablet(context)` — width >= 768px
- **Phone**: `FloatingTabBar`, 5 tabs: Read(0), Library(1), Creators(2), Review(3), More(4).
- **iPad**: `IconRail` driven by the `NavDestination` enum. New destinations are appended to the END of the enum so stored indices don't shift; `creators` is last.
- **Library header**: Segmented control (All Series / Collections / Sources) + inline filter chip bar with facet picker sheet
- **Library split view**: On iPad, tapping a series opens `SeriesDetailPanel` on the right, at 0.40 width in landscape and 0.46 in portrait, with no animation (local `_selectedSeriesId` state). The Creators tab uses the same split for `CreatorDetailPanel`.
- **Reader chrome on iPad**: `ReaderTopBar(rail: true)` is a vertical rail (side set in Aa → More → Rail, `railSideProvider`, `ReaderTopBar.railTop`); the bottom `FilmstripScrubber` bar stays on both form factors. Chrome shows only on swipe up — no tap bands near the rail.
- `SeriesDetailPanel` is a reusable widget used by both the library split view (`onClose` callback) and `SeriesDetailScreen` (full-screen wrapper). Panel mode uses a compact vertical layout (cover above title); full-screen uses side-by-side.

## UI Animation Patterns

- **Library panel slide**: no animation (a plain swap)
- **Hero cover transitions**: Flutter default (~300ms). Wrap Hero children in `Material(type: MaterialType.transparency)` to fix flight rendering with PanelFrame's BoxDecoration/shadows.
- **Opening a comic** (`readerRoute`, `cover_flight_route.dart`): the cover flies (380ms) to the page's contain rect and holds while the reader loads underneath; the reader calls `CoverReveal.of(context)?.ready()` when its first page is visible (also in scroll mode and dead ends), then the cover cross-fades (160ms) and a zoomed first step eases in from identity. Any new reader exit path that never shows a page must call `ready()` too, or the cover holds for the 4s limit. Closing (420ms) re-finds the tile's `CoverAnchor` when the pop starts (shelves reorder while reading), fades the reader off the cover as it flies home, and fades the cover in place when the tile isn't on screen.
- **Shimmer loading**: `ShimmerBox` widget — 1500ms repeating LinearGradient sweep (surface1 → surface2 → surface1). Replaces CircularProgressIndicator in loading states.
- **Staggered entrances**: `StaggeredEntry` widget — 300ms fade+slide per item, 50ms stagger offset. NOT used on library grid (items start at opacity 0, looks like blank tiles while covers load). Used on home shelves and browse lists.
- **Haptics**: `selectionClick()` for nav taps, `mediumImpact()` for bookmarks and pull-to-refresh.
- **Bottom sheet state**: Don't use StatelessWidget with snapshot values for bottom sheets that show mutable state. Use ConsumerWidget watching the provider so the UI updates on interaction (e.g., SortPickerSheet).
- Display name helper: `stripComicExtension()` in `lib/config/string_utils.dart` — strips .cbz/.cbr/.cb7/.pdf from display names. Use everywhere a file path becomes a visible name.

## Key Design Decisions

### Riverpod 3.x Patterns
- No `StateProvider` — use `NotifierProvider` with a `Notifier<T>` class instead
- `AsyncNotifier` has a built-in `update()` method — don't name your own methods `update()`, use `edit()` or similar
- Active selection state pattern: `class FooNotifier extends Notifier<int?> { void select(int? id) => state = id; }`
- `valueOrNull` doesn't exist — use `.value` (nullable getter)

- `CachedNetworkImageProvider` is used in both PagePrefetcher and display widgets so they share the same cache layer. Do not use plain `NetworkImage` for prefetching.
- Image cache is set to 200 images / 512 MB in main.dart for large comic pages. Cache is cleared on reader exit.
- Prefetcher preloads 5 pages ahead (8 during fast flipping).

### Reader Transform System

- Images always render with `BoxFit.contain`. Fit modes (fitScreen/fitWidth/fitHeight) are handled by Matrix4 transforms on the InteractiveViewer, not by changing BoxFit.
- `display_rect_calculator` computes where the image actually renders on screen (the contain rect). `page_transform_calculator` takes that rect + fit mode and produces Matrix4 transforms.
- Spread detection: `width/height > 1.0`. Single pages are portrait (~0.65 aspect); a two-page spread doubles the width (~1.3+), so the two populations are cleanly separated and a `> 1.0` cut is robust. (Was `> 1.3`, which sat at the lower edge of the spread cluster and missed some.) Portrait spreads: full view → zoom left half → zoom right half (pins to top if height overflows). Landscape spreads: full view → cols×rows grid at half-width zoom. Do NOT change landscape grid to halves — it was already working.
- Pan rule: `ZoomWrapper` sets `panEnabled: _isScaled && allowPan()` (scale > 1.01). Pan is off at 1x to prevent dragging into black. The reader passes `allowPan: _offStep || zoom-locked`, so on a reader-set step (fit width, landscape auto-zoom, spread/panel/bubble steps) one-finger vertical drags don't pan — they show the chrome; a user pinch (off-step) or a carried-over zoom lock enables pan. (The old `disablePinch`/`disablePan` props were removed as dead code.)
- fitScreen auto-zooms when the contain rect is narrower than 95% of a landscape viewport (`page_transform_calculator.dart`) — a portrait page on a landscape screen starts zoomed (multi-step), not identity. Tests wanting single-step tap-to-advance use fitHeight.
- To prevent visual flash on page load: image renders at opacity 0 until `onImageLoaded` fires, transform is applied, then page is marked "ready" and shown at opacity 1.
- `InteractiveViewer`: use `constrained: true` (not false — false causes black screen), `boundaryMargin: infinity`, `minScale: 1.0`.
- Volume keys use `flutter_volume_controller` (monitors system volume changes). iOS does not send volume keys as KeyEvents.
- `settingsProvider` is async (fetches from API). Wait for it to load before showing reader content, otherwise default settings flash then jump.
- `fitWidth`/`fitHeight` BoxFit mapping is swapped from user perspective: "Fit Width" (page width fills screen) = `BoxFit.fitHeight` in the display rect calculator.
- Page turn animations: 'slide' (default PageScrollPhysics), 'fade' (crossfade overlay), 'none' (instant jump). Fade swipe falls back to slide. Guard `fadeToPage()` with `isFading` to prevent duplicate triggers from post-frame callbacks. During a fade the `PageView` stays mounted under the overlay Stack — removing it detaches the `PageController` and `jumpToPage()` asserts.
- Scroll mode progress: `ScrollReader` reads the page covering the top from real item layout, post-frame (scroll notifications arrive before layout). Never estimate as offset/viewportHeight: fit-width pages on a landscape iPad are ~2 screens tall. The reader passes the *current* page as `initialPage`, not `widget.initialPage`.
- Rebuilding a page's steps for the page already on screen (setting change, rotation) passes `keepPlace: true` to `_recalculateTransforms`, which lands via `PanSequenceController.jumpToNearest`. `setTransforms` alone resets to step 0, which is right only for a newly turned page.
- None mode: `NeverScrollableScrollPhysics` + GestureDetector for swipe. Apply transforms with `instant: true` to avoid briefly showing wrong position.
- Zoom lock: captures `TransformationController.value` on `onInteractionEnd`. Cleared on double-tap reset. Does not persist across reader sessions.
- `PageReaderState` is public (not `_PageReaderState`) for GlobalKey access to `fadeToPage()` and `isFading`.

### Backend Route Gotchas

- Go 1.26 ServeMux panics if two patterns with wildcards are ambiguous (e.g., `/library/{id}/cover` vs `/library/facets/{facet}` both match `/library/facets/cover`). Keep wildcard routes under different prefixes.
- ComicInfo.xml creator fields are often comma-separated ("Tom King, Scott Snyder") and may have ComicVine IDs appended ("Mark Waid [40724]"). The `splitCreators` + `stripComicVineID` functions in `server/facets.go` handle both.
- Backend scan reads metadata from first issue only per series (not all issues) — scanning all issues takes 5+ minutes for large libraries.

### Navigation Gotchas

- Home screen uses `IndexedStack` — providers don't auto-dispose. No manual invalidation needed for library/read-tab data: the mirror streams (`readTabProvider`, `libraryProvider`) self-update when the mirror changes. (`homeProvider` was retired in favor of `readTabProvider`.)
- `PageController(initialPage: N)` works but the sync callback in `_buildReaderBody` can stomp it on the first frame if the provider state is still at 0. Guard the first-frame sync.
- Pass `initialPage` from the caller (e.g., `ReadingProgress.currentPage`) rather than re-fetching progress in the reader provider.

## Testing

```
flutter test
```

Tests exist for PagePrefetcher, PanSequenceController (Matrix4-based), display_rect_calculator, page_transform_calculator, spread_detector, and ReaderSettings serialization.

`test/reader/` is the reader integration suite: it pumps the real `ReaderScreen` against an in-test HTTP server (`fake_comic_server.dart`) via `harness.dart` (`pumpReader`, `settleImages`, `disposeReader`, `useComicServer`). Never use `pumpAndSettle` there (repeating shimmer timers); real HTTP and image decode only progress inside `tester.runAsync` (use `settleImages`).

- Reader tests run on an 800×600 surface, which counts as tablet (the rail is on). `fitScreen` zooms a portrait page there, so a tap advances a step, not the page: set `server.settings = {'page_fit': 'fitHeight'}` when testing page turns.
- Don't `await settingsProvider.notifier.save()` in widget tests: its PUT is real HTTP and hangs outside `runAsync`. Call it, then `settleImages`.
- To check position, assert on what's on screen (item rects), not the reader's reported page: a wrong estimate reports itself consistently.
- `download_manager_test` "journal enqueue…" flakes under full-suite load and passes alone.

Personal deploy notes, device setup and local tooling: see `CLAUDE.local.md` (untracked).
