# Phase 1b: Komga Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Komga server works as a source: onboarding, Library, Read tab, series detail, reader, progress sync and downloads behave as they do on the Go backend.

**Architecture:** `KomgaClient extends ApiClient` and overrides the handful of methods the mirror, reader, progress and downloads call, so `SyncEngine`, `SyncQueueDrainer` and the reader keep their `ApiClient` types. `fetchSync` does a full pull of Komga series + books and maps them into the existing `/sync` shape, so `MirrorDatabase.applySync` is unchanged except for not pruning local-only queues. Server-only features (collections, smart filters, stats, scan, metadata edit, rename, chapter detect, bubbles, flags) stay gated on `isCustomSourceProvider` (Go backend), which Komga is not.

**Tech Stack:** Flutter, Riverpod 3, http (+ `package:http/testing.dart` MockClient), drift mirror, cached_network_image.

**Spec:** `docs/superpowers/specs/2026-11-05-app-store-launch-design.md` (Architecture → Server adapters; Left to the builder → Komga API mapping, auth, watermarking).

## Global Constraints

- Komga API v1.30 (`https://raw.githubusercontent.com/gotson/komga/refs/heads/master/komga/docs/openapi.json`). Use only non-deprecated endpoints: `POST /api/v1/series/list`, `POST /api/v1/books/list`, `GET /api/v1/books/{id}`, `GET /api/v1/series/{id}`, `GET /api/v1/books/{id}/pages/{n}` (1-based), `GET /api/v1/books/{id}/thumbnail`, `GET /api/v1/series/{id}/thumbnail`, `PATCH`/`DELETE /api/v1/books/{id}/read-progress`, `GET /api/v2/users/me`.
- Komga auth: HTTP Basic, or `X-API-Key: <key>`. The Go backend keeps `Authorization: Bearer` for API keys.
- Every request to a Komga source (API, covers, page images, cover sync, downloads) carries the source's auth headers.
- Personal build must keep working unchanged against the Go backend (`make ipad`).
- Don't `dart format` whole files. Tests run as personal; store tests set `isStore = true` and reset it.
- No personal hostnames, IPs or credentials in the repo.

## Review Focus

- Komga book with `readProgress.completed = true` but `page` < pagesCount: must show as read (`current_page = total_pages`).
- Komga ids are opaque strings (not base64 paths): nothing in a store-visible path may decode them (`comicIdToPath`, `_seriesIdFromComicId`, `seriesFromComicPath`).
- Local queues on a Komga source must survive every sync (Komga has no queues; `queue_ids` is empty).
- Page numbering: app page 0 ↔ Komga page 1, in reader, prefetcher and downloads.
- Deleted books (`deleted: true`) and books with `media.status != READY` (0 pages) must not appear as readable issues.

---

### Task 1: Komga source type, auth headers, image URL helpers

**Files:**
- Modify: `lib/models/server_source.dart`, `lib/services/api_client.dart` (`_headers`), `lib/providers/providers.dart`
- Create: `lib/config/source_urls.dart`
- Test: `test/models/server_source_test.dart` (extend or create), `test/config/source_urls_test.dart`

**Interfaces:**
- Produces: `SourceType.komga`; `ServerSource.authHeaders` (Komga apiKey → `{'X-API-Key': key}`, basic unchanged, Go apiKey → Bearer unchanged); `extension SourceUrls on ServerSource { String comicCover(String id); String seriesCover(String id); String page(String id, int zeroBasedPage); Map<String,String> get imageHeaders /* == authHeaders */; }`; `ApiClient({..., Map<String,String> authHeaders = const {}})` merged into `_headers`; `hasMirrorProvider` (`custom || komga`); `apiClientProvider` returns `KomgaClient` for komga sources (Task 2) with `authHeaders: source.authHeaders`.

- [ ] **Step 1: Tests.** `server_source_test`: komga + apiKey → `{'X-API-Key': 'k'}`; custom + apiKey → `{'Authorization': 'Bearer k'}`; komga JSON round-trips `type: 'komga'`. `source_urls_test`: custom `comicCover('a')` == `'$base/comics/a/cover'`, `seriesCover` == `'$base/library/a/cover'`, `page('a', 0)` == `'$base/comics/a/pages/0'`; komga → `'/api/v1/books/a/thumbnail'`, `'/api/v1/series/a/thumbnail'`, `'/api/v1/books/a/pages/1'`.
- [ ] **Step 2: Run** `flutter test test/models/server_source_test.dart test/config/source_urls_test.dart` — Expected: FAIL (no `komga`, no extension).
- [ ] **Step 3: Implement.** Ids are `Uri.encodeComponent`ed in both layouts (matches `ApiClient`). `ApiClient._headers` spreads `authHeaders`.
- [ ] **Step 4: Run** the same — Expected: PASS. Then `flutter test` — Expected: all pass.
- [ ] **Step 5: Commit** `feat: Komga source type, per-source auth headers and URL helpers`.

### Task 2: KomgaClient

**Files:**
- Create: `lib/services/komga_client.dart`
- Test: `test/services/komga_client_test.dart` (MockClient, inline JSON fixtures)

**Interfaces:**
- Consumes: `ApiClient` constructor (Task 1), `SyncResponse`, `ComicInfo.fromJson`, `SeriesDetail.fromJson`.
- Produces: `class KomgaClient extends ApiClient` overriding:
  - `fetchSync({required int since})` — ignores `since`; `POST /api/v1/series/list?unpaged=true` body `{}` and `POST /api/v1/books/list?unpaged=true` body `{}` (4-minute timeout like the Go bootstrap). Returns `SyncResponse(serverTime: now ms, series: [mapped with inline issues], progress: [...], seriesIds, progressIds, serverHasQueues: false)`. `// ponytail: full pull every sync (Komga has no lastModified search condition); page books by sort=lastModified,desc if big libraries get slow.`
  - `fetchSeriesRaw(id)` / `fetchSeriesDetail(id)` — `GET /api/v1/series/{id}` + `POST /api/v1/books/list?unpaged=true` with `{"condition":{"seriesId":{"operator":"is","value":id}}}`, same mapper.
  - `getComicInfo(id)` — `GET /api/v1/books/{id}` → `ComicInfo(title: metadata.title, series: seriesTitle, number: metadata.number, summary: metadata.summary, pageCount: media.pagesCount)`.
  - `pageUrl(id, n)` → `'$baseUrl/api/v1/books/$id/pages/${n + 1}'`.
  - `updateProgress(...)` — `currentPage >= totalPages` → `PATCH read-progress {"completed": true}`, else `{"page": currentPage + 1}`. Ignores bookmarks/chapters/readAt (last write wins).
  - `batchUpdateProgress(items)` / `batchDeleteProgress(ids)` — loop PATCH / `DELETE /api/v1/books/{id}/read-progress`.
  - `checkConnection()` — `GET /api/v2/users/me`, 2xx = true, 5s timeout, never throws.
  - `getSettings()` throws `UnsupportedError` (settingsProvider falls back to its local cache); `updateSettings`, `postReadingSession`, `putQueue`, `deleteQueue` are no-ops.
  - Top-level `Map<String, dynamic> komgaSeriesToSync(Map series, List<Map> books)` and `Map<String, dynamic>? komgaProgress(Map book)` for testing.
- Mapping (series → `/sync` series map): `id`, `name` = metadata.title, `updated_at` = lastModified, `created_at` = created, `issue_count` = booksCount, `cover_url` = `/api/v1/series/{id}/thumbnail`, `publisher`, `genres`, `description` = metadata.summary or booksMetadata.summary, `year`/`start_year` = year of booksMetadata.releaseDate, `writer`/`penciller` = first booksMetadata.authors with role `writer`/`penciller`, `folder_path` = `''`. Issues, sorted by metadata.numberSort, skipping `deleted` and `media.pagesCount == 0`: `id`, `name` = book.name, `number` = metadata.number, `title`, `summary`, `cover_date` = releaseDate, `cover_url` = `/api/v1/books/{id}/thumbnail`, `writer`, `penciller`.
- Progress: none when `readProgress == null`; else `comic_id`, `total_pages` = media.pagesCount, `current_page` = completed ? pagesCount : page − 1, `updated_at` = readProgress.lastModified.

- [ ] **Step 1: Tests:** `fetchSync maps series, issues and progress` (two books, one completed with page 3 of 20 → current_page 20; one at page 5 → 4; one deleted book absent; issues ordered by numberSort; series cover_url relative Komga path); `fetchSync sends auth header` (MockClient asserts `X-API-Key`); `updateProgress completed vs page` (asserts PATCH bodies); `pageUrl is 1-based`; `getComicInfo reads media.pagesCount`; `checkConnection false on 401`.
- [ ] **Step 2: Run** `flutter test test/services/komga_client_test.dart` — Expected: FAIL (no file).
- [ ] **Step 3: Implement**; wire `apiClientProvider` to return it for `SourceType.komga`.
- [ ] **Step 4: Run** — Expected: PASS; `flutter test` all pass.
- [ ] **Step 5: Commit** `feat: KomgaClient maps Komga into the mirror's sync shape`.

### Task 3: Mirror keeps local queues for servers without them; sync runs for Komga

**Files:**
- Modify: `lib/models/sync_response.dart` (`final bool serverHasQueues; // default true`), `lib/services/mirror/mirror_database.dart` (`applySync` skips queue and arc pruning when `!resp.serverHasQueues`), `lib/providers/connectivity_provider.dart:167` and `lib/screens/library_screen.dart:220,846` (`isCustomSourceProvider` → `hasMirrorProvider` where it means "uses the mirror")
- Test: `test/services/mirror/mirror_database_test.dart` (extend)

- [ ] **Step 1: Test** `applySync without server queues keeps local queues`: insert a queue, apply `SyncResponse(..., serverHasQueues: false)` with empty `queueIds` → queue still there; with `true` → pruned.
- [ ] **Step 2: Run** — Expected: FAIL (named param missing).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** test + `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: mirror sync runs for Komga and keeps its local queues`.

### Task 4: No path-decoding of ids on store-visible paths

**Files:**
- Modify: `lib/providers/reader_provider.dart:30,183`, `lib/screens/reader_screen.dart:88,271,429`, `lib/config/string_utils.dart:9` (`comicIdToPath`), callers `read_screen.dart:283`, `resume_hero_card.dart:141`
- Add: `MirrorDatabase.seriesIdForComic(String comicId) → Future<String?>` (IssueRows lookup)
- Test: `test/services/mirror/mirror_database_test.dart`, `test/config/string_utils_test.dart`

- [ ] **Step 1: Tests:** `seriesIdForComic returns the issue's series`; `comicIdToPath returns null for a non-base64 id` (e.g. `'0B6JRNE8N3GCV'`) instead of throwing or garbage.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.** `comicIdToPath` returns `String?` (null on decode failure or non-UTF-8); reader and session code ask the mirror for the series id first and fall back to the old path decode only when the mirror has none; display callers fall back to the mirror issue name.
- [ ] **Step 4: Run** + `flutter test` — Expected: PASS (reader suite included).
- [ ] **Step 5: Commit** `fix: series ids come from the mirror, not decoded comic paths`.

### Task 5: Covers, pages and downloads use source URLs and auth

**Files:**
- Modify: widgets that build `/comics/{id}/cover`, `/library/{id}/cover` or `/pages/0` from a `serverUrl` (`issue_list_view.dart:111`, `issue_grid_view.dart:31`, `up_next_card.dart:69`, `resume_hero_card.dart:224`, `series_grid_tile.dart:199`, `series_list_tile.dart:42`, `just_added_card.dart:35`, `comic_grid_tile.dart:47`, `series_detail_panel.dart:84,176,274`, `read_screen.dart:32`, `queue_detail_screen.dart:21,62`, `reader_screen.dart:1470-1487`) — take the `ServerSource` (or read `activeSourceProvider`) and use `SourceUrls`, passing `httpHeaders: source.imageHeaders`.
- Modify: `page_reader.dart:234`, `scroll_reader.dart:159`, `PagePrefetcher` — pass `source.imageHeaders`.
- Modify: `cover_syncer.dart:49` — headers from the source.
- Modify: `download_manager.dart` `_handOff` + journal meta: `bool komga` (persisted); komga → info from `meta.url` (`media.pagesCount`), pages `'${meta.url}/pages/${i + 1}'`. Call sites `series_detail_panel.dart:585-605`, `issue_list_view.dart:208-219` pass `comicUrl` = komga ? `$base/api/v1/books/$id` : today's, headers include `source.authHeaders`. `series_download_sheet.dart:80` skips the size HEAD for komga.
- Test: `test/download_manager_test.dart` (komga layout: requests `/pages/1`..`/pages/N`, count from `media.pagesCount`), `test/config/source_url_guard_test.dart`.

- [ ] **Step 1: Tests:** download komga layout test; guard test: no file under `lib/widgets` or `lib/screens` contains `'/comics/$` + `cover`, `'/library/$` + `cover` or `'/pages/0'` string literals (reads files, regex; exempt store-hidden creators/arcs/review/remote/stats files by name list).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** + `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: covers, pages and downloads follow the source's URLs and auth`.

### Task 6: Hide Go-only features on Komga sources

**Files:** entry points for collections (library segmented control "Collections"), smart filters, stats (rail/More/Read-tab stats shelf `read_tab_provider.dart:43`), scan (`scan_status_provider`, scan banner), metadata edit/rename/templates (`series_action_sheet.dart`), chapter detect (`scan_provider.dart`), bubbles/flags (`bubble_repository.dart`, reader flag) — gate on `ref.watch(isCustomSourceProvider)`.
- Test: one widget/provider test per surface that is cheap to pump (series action sheet rows; read tab skips stats fetch on komga); the rest by the guard of the provider returning empty without a network call.

- [ ] **Step 1: Tests** for the action sheet rows and read-tab stats on a komga source.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** + `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: Go-only features hide on Komga sources`.

### Task 7: Onboarding and source sheet offer Komga

**Files:** `lib/screens/onboarding_screen.dart`, `lib/widgets/source_config_sheet.dart`, `lib/providers/source_provider.dart` (save type + credentials for the default source), `CLAUDE.md`
- Test: `test/screens/onboarding_screen_test.dart` (extend)

**Interfaces:** `OnboardingScreen({Future<bool> Function(ServerSource source)? probe})` — probe now takes a candidate source (url + type + auth) and defaults to `clientFor(source).checkConnection()`. A segmented choice **Komga | Gutter server** (Komga first); Komga shows Username/Password, with an "Use API key instead" toggle. On success saves the default source with type, auth and secrets (secure storage) and the URL to `ServerConfig`.

- [ ] **Step 1: Tests:** `Komga connect saves a komga source with basic auth` (probe receives `type == komga`, `authHeaders` Basic); `Gutter server path unchanged` (existing tests still pass with the new probe signature).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement**; source sheet gains a Komga type with the same fields. CLAUDE.md: Komga adapter paragraph under Architecture (KomgaClient, full pull, 1-based pages, gated features).
- [ ] **Step 4: Run** + `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: onboarding and source sheet connect to Komga`.

### Verification (after Task 7)

On-device against a real Komga (the 1c demo container can be stood up early for this): onboard, library fills, open + read a book, progress shows in Komga's web UI, mark read in Komga → app shows read after refresh, download a book and read it in airplane mode, `make ipad` personal build still on the Go backend.
