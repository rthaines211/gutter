# Phase 3: Public Go Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A stranger can follow the gutter-server README, run `docker compose up`, add the server in Gutter with a password, watch the first scan, and read a comic.

**Architecture:** One auth middleware wraps the whole Go mux, and credentials come from env vars. The config file becomes optional, and env vars override it. On an empty DB the server scans at once, and `GET /` shows progress. The app gets auth plumbing (API client, downloads, covers, images), a 401-aware onboarding, and a scanning empty state. Packaging is a compose file plus a multi-arch GHCR image built by GitHub Actions.

**Tech Stack:** Go 1.26, SQLite (CGO), `net/http` ServeMux, `html/template` + `embed`; Flutter/Riverpod 3, `cached_network_image`; Docker buildx, GitHub Actions, GHCR.

**Spec:** `docs/superpowers/specs/2026-11-05-phase3-public-backend-design.md` (in this app repo)

## Where the work happens

- **Server tasks (S1–S7):** in `~/projects/gutter-server`, in a new worktree on branch `feat/public-backend` cut from `origin/main`. Every `go test` command runs from that worktree's root.
- **App tasks (A1–A4):** in this app repo, on a branch cut from `origin/feat/store-flavor` (not `main`). Onboarding exists only there.
- **M1:** the owner's homelab and devices. Run it only after S1–S7 and A1–A4 are merged.

## Global Constraints

- Module path `github.com/rthaines211/gutter-server`. Binary `gutter`. Admin realm `Gutter`.
- Env vars: `GUTTER_PASSWORD` (required), `GUTTER_API_KEY`, `GUTTER_AUTH=off` (the only escape hatch), `GUTTER_COMICVINE_KEY`, `GUTTER_METRON_USER`, `GUTTER_METRON_PASS`, `GUTTER_WRITEBACK`, `GUTTER_SCAN_INTERVAL`, `GUTTER_MYLAR_URL`, `GUTTER_PUSH_REGISTER_SECRET`. The old unprefixed names are removed.
- Exempt from auth: `GET /healthz` and every `OPTIONS` request. Nothing else.
- Container: library at `/comics` (read-only in the compose file), data at `/data`, config `/data/config.yaml` (optional), port 8081.
- Image `ghcr.io/rthaines211/gutter-server`, tags `vX.Y.Z` and `latest`, platforms `linux/amd64,linux/arm64`.
- Never ship `localcv.db`. Matching needs the user's own dump. Metron, GCD and live ComicVine only add to it.
- Both repos are public. No personal hostnames, IPs, Tailscale names, UDIDs or keys go in either.
- App: don't `dart format` whole files. Never use `pumpAndSettle` in `test/reader/`.
- No local simulator/Xcode builds without asking. Multi-arch image builds run only in Actions.

## Review Focus

1. **`Authorization: Bearer ` (empty) when no API key is configured must get a 401.** A constant-time compare of `""` with `""` passes. S3 pins this.
2. **Basic passwords with `:`, spaces and non-ASCII** (`p:ss wörd`) must authenticate. `r.BasicAuth` splits at the first colon only. S3 pins this.
3. **A wrong or changed password must not make the app show as offline.** A 401 counts as "server reached". A1 pins this.
4. **The prefetched page and the displayed page must share one cache entry** after headers are added (the shared cache layer in CLAUDE.md). A2 pins this.
5. **A first scan that finishes with zero series** must show the normal empty state ("No comics found…"), not "Scanning…" forever. A4 pins this.

---

### Task S1: Rename comic-reader → gutter

**Files:**
- Modify: `go.mod`, every `*.go` import, `Dockerfile`, `server/admin/auth.go` (realm), `server/admin/templates/layout.html`, `main.go` log lines, `README.md`, `config.example.yaml`, `cmd/pushwatch/*`, `hostjob/**/*.plist` and scripts that name the binary or `/etc/comic-reader`

**Interfaces:**
- Produces: module `github.com/rthaines211/gutter-server`, binary `/usr/local/bin/gutter`.

- [ ] **Step 1:** `go mod edit -module github.com/rthaines211/gutter-server`, then rewrite imports: `grep -rl 'github.com/ryanhaines/comic-reader' --include='*.go' . | xargs sed -i '' 's#github.com/ryanhaines/comic-reader#github.com/rthaines211/gutter-server#g'`
- [ ] **Step 2:** Rename user-visible strings: Dockerfile `-o /out/gutter`, `COPY … /usr/local/bin/gutter`, `ENTRYPOINT ["gutter", "-config", "/data/config.yaml"]` (S6 finishes the Dockerfile), realm `Basic realm="Gutter"`, `log.Printf("gutter starting on %s", addr)`, admin layout title. List the leftovers with `grep -rn 'comic-reader' . --exclude-dir=.git`. Leave the DB filename and data paths alone here (S2).
- [ ] **Step 3:** Run `go build ./... && go test ./...`. Expected: PASS, with no test changes beyond import paths.
- [ ] **Step 4: Commit** `chore: rename module and binary to gutter`

---

### Task S2: Config file optional, GUTTER_* env, Validate

**Files:**
- Modify: `config/config.go`, `main.go` (call `Validate`, env-name log lines)
- Test: `config/config_test.go`

**Interfaces:**
- Produces:
  - `config.Load(path string) (*Config, error)`: a missing file is not an error; defaults plus env apply, and `path` is kept so `Save` creates the file.
  - New fields: `Password string \`yaml:"password,omitempty"\``, `APIKey string \`yaml:"api_key,omitempty"\``, `AuthOff bool \`yaml:"-"\``. Remove `AdminPassword`.
  - `func (c *Config) Validate() error`: returns an error containing `GUTTER_PASSWORD` when `Password == "" && !AuthOff`.
  - Defaults: `Port: 8081`, `DBPath: "gutter.db"`, `ComicDirs: []string{"/comics"}` when the file and env leave it empty (replaces the "must not be empty" error).

- [ ] **Step 1: Write the failing tests**

```go
func TestLoadMissingFileUsesDefaultsAndEnv(t *testing.T) {
	t.Setenv("GUTTER_PASSWORD", "pw")
	t.Setenv("GUTTER_API_KEY", "k")
	t.Setenv("GUTTER_SCAN_INTERVAL", "5m")
	t.Setenv("GUTTER_WRITEBACK", "false")
	cfg, err := Load(filepath.Join(t.TempDir(), "config.yaml"))
	if err != nil { t.Fatal(err) }
	if cfg.Port != 8081 || cfg.DBPath != "gutter.db" || cfg.ComicDirs[0] != "/comics" { t.Fatalf("defaults: %+v", cfg) }
	if cfg.Password != "pw" || cfg.APIKey != "k" || cfg.ScanInterval != "5m" || !cfg.WritebackDisabled { t.Fatalf("env: %+v", cfg) }
}

func TestEnvOverridesFile(t *testing.T) // file password: a, GUTTER_PASSWORD=b → "b"; file metron_user: x, GUTTER_METRON_USER unset → "x"

func TestValidate(t *testing.T) {
	// {Password:""} → error mentioning "GUTTER_PASSWORD"
	// {Password:"x"} → nil
	// {AuthOff:true} → nil   (GUTTER_AUTH=off sets AuthOff)
}

func TestSaveCreatesMissingFile0600(t *testing.T) // Load(missing) → Save() → file exists, mode 0600
```

- [ ] **Step 2:** Run `go test ./config/`. Expected: FAIL (unknown fields `Password`, `APIKey`, `Validate`).
- [ ] **Step 3: Implement.** Env mapping: `GUTTER_PASSWORD→Password`, `GUTTER_API_KEY→APIKey`, `GUTTER_AUTH=="off"→AuthOff`, `GUTTER_COMICVINE_KEY→ComicVineAPIKey`, `GUTTER_METRON_USER/PASS`, `GUTTER_WRITEBACK` (`strconv.ParseBool`; false → `WritebackDisabled=true`), `GUTTER_SCAN_INTERVAL`, `GUTTER_MYLAR_URL`, `GUTTER_PUSH_REGISTER_SECRET`. Delete the old unprefixed lookups. `Save` writes mode `0600`, because it may persist env-provided secrets: add `// ponytail: env secrets can land in the saved file; 0600 is the guard, split file/env state if that ever matters`. In `main.go`, after `Load`: `if err := cfg.Validate(); err != nil { log.Fatal(err) }`, and when `cfg.AuthOff` log `WARNING: auth is OFF (GUTTER_AUTH=off) — anyone who can reach this port can read and change your library`. Update the `enrichment: disabled (…)` log line to the new env name.
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS. Fix `server/admin/auth_test.go` compile errors by deleting that test (S3 replaces it).
- [ ] **Step 5: Commit** `feat: optional config file, GUTTER_* env overrides, require a password`

---

### Task S3: Auth on every endpoint

**Files:**
- Create: `server/auth.go`, `server/auth_test.go`
- Modify: `server/router.go` (`NewRouter`, CORS headers), `server/admin/admin.go` (`Register` stops wrapping), `main.go` (set `srv.Password`, `srv.APIKey`, `srv.AuthOff`)
- Delete: `server/admin/auth.go`, `server/admin/auth_test.go`

**Interfaces:**
- Consumes: `cfg.Password`, `cfg.APIKey`, `cfg.AuthOff` (S2).
- Produces: `func RequireAuth(next http.Handler, password, apiKey string) http.Handler`; `Server` fields `Password, APIKey string; AuthOff bool`. `NewRouter` returns `reqLog(cors(RequireAuth(mux)))`, or skips `RequireAuth` when `AuthOff`.

- [ ] **Step 1: Write the failing test** (table test over a stub handler returning 200):

```go
func TestRequireAuth(t *testing.T) {
	h := RequireAuth(ok, "p:ss wörd", "key123")
	cases := []struct{ name, method, path, authz, site string; want int }{
		{"no creds", "GET", "/library", "", "", 401},
		{"healthz open", "GET", "/healthz", "", "", 200},
		{"options open", "OPTIONS", "/library", "", "", 200},
		{"basic ok any user", "GET", "/library", basic("whoever", "p:ss wörd"), "", 200},
		{"basic wrong", "GET", "/library", basic("x", "nope"), "", 401},
		{"bearer ok", "GET", "/library", "Bearer key123", "", 200},
		{"bearer wrong", "GET", "/library", "Bearer nope", "", 401},
		{"admin gated", "GET", "/_admin/", "", "", 401},
		{"status page gated", "GET", "/", "", "", 401},
		{"cross-site write refused", "POST", "/library/refresh", basic("x", "p:ss wörd"), "cross-site", 403},
		{"same-origin write ok", "POST", "/library/refresh", basic("x", "p:ss wörd"), "same-origin", 200},
	}
	// 401 responses carry WWW-Authenticate: Basic realm="Gutter", charset="UTF-8"
}

func TestRequireAuthEmptyAPIKeyNeverMatches(t *testing.T) {
	h := RequireAuth(ok, "pw", "")
	// "Bearer " → 401, and "Bearer" → 401
}

func TestRouterCORSAllowsAuthorization(t *testing.T) // OPTIONS response Access-Control-Allow-Headers contains "Authorization"
```

- [ ] **Step 2:** Run `go test ./server/ -run 'RequireAuth|CORS'`. Expected: FAIL (`RequireAuth` undefined).
- [ ] **Step 3: Implement** with `subtle.ConstantTimeCompare`. Bearer is accepted only when `apiKey != ""`. Keep the existing cross-site-write refusal (non-GET + `Sec-Fetch-Site: cross-site` → 403) after auth succeeds. The `/devices` push-secret check in `server/devices.go` stays as is. Existing handler tests that call `NewRouter` without credentials must set `AuthOff: true` on the test `Server`, or send creds.
- [ ] **Step 4:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: require auth on every endpoint except /healthz`

---

### Task S4: Safe defaults: read-only library, quiet without localcv, owner features off

**Files:**
- Create: `writeback/writable.go`, `writeback/writable_test.go`
- Modify: `main.go`, `server/admin/admin.go` (`PageData.MatchEnabled`), `server/admin/templates/layout.html` (hide Match/Organize nav when `!MatchEnabled`), `config.example.yaml`

**Interfaces:**
- Produces: `func writeback.Writable(dirs []string) bool`, true only if a temp file can be created and removed in every dir.

- [ ] **Step 1: Write the failing test.** `TestWritable`: a `t.TempDir()` → true; a dir chmodded `0555` → false (`t.Skip` when `os.Geteuid()==0`); a missing dir → false.
- [ ] **Step 2:** Run `go test ./writeback/ -run Writable`. Expected: FAIL.
- [ ] **Step 3: Implement**, then in `main.go`, before the writeback block: `if !cfg.WritebackDisabled && !writeback.Writable(cfg.ComicDirs) { cfg.WritebackDisabled = true; log.Printf("writeback: off (library is read-only)") }`. Set `PageData.MatchEnabled = a.Match != nil` in `baseData`, and wrap the Match/Organize nav links in `{{if .MatchEnabled}}`. In `config.example.yaml`: `bubbles_dir: ""`, remove the push/mylar/tagger/bubbles blocks (they stay in the code, undocumented), list `localcv_db_path` first among the metadata keys with the comment "Matching needs your own ComicVine dump. Metron, GCD and comicvine_api_key only add to it.", and rename `admin_password` → `password`.
- [ ] **Step 4: Smoke test with no localcv.** Run `scripts/mk-dev-library.sh` (or point at any folder of 3 CBZs), then `GUTTER_PASSWORD=x go run . -config /nonexistent/config.yaml` with `comic_dirs` via a temp config. Then `curl -u x:x localhost:8081/creators`, `/review`, `/enrichment/status`, `/_admin/`. Expected: no 500s, and the log has one "disabled" line per feature with no `error`/`panic` lines (`grep -iE 'error|panic'` on the log is empty). Fix any handler that 500s when `Match`/creators/enrichment is nil, so it returns an empty result or 503 JSON `{"error":"… disabled"}`.
- [ ] **Step 5:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: read-only libraries turn writeback off; quiet startup without localcv`

---

### Task S5: First-run scan and status page

**Files:**
- Create: `server/status_page.go`, `server/status_page.html` (embedded), `server/status_page_test.go`
- Modify: `main.go`, `server/router.go` (route `GET /{$}`), `server/admin/admin.go` (`var Version = "dev"`, used by `baseData` in place of `"0.4.2"`)

**Interfaces:**
- Consumes: `admin.ScanState.Snapshot()` (`IsScanning`, `Scanned`, `Total`, `LastScanAt`), `Store.SeriesCount()`, `Server.Admin.Match != nil`.
- Produces: `func (s *Server) HandleStatusPage(w http.ResponseWriter, r *http.Request)`; `admin.Version` (set by `-ldflags "-X github.com/rthaines211/gutter-server/server/admin.Version=$VERSION"` in S6).

- [ ] **Step 1: Write the failing tests:**

```go
func TestStatusPageScanning(t *testing.T)  // ScanState scanning 120/583 → 200, text/html, body contains "Scanning", "120", "583"
func TestStatusPageReady(t *testing.T)     // not scanning, 3 series in store → body contains "Ready" and "3 series"
func TestStatusPageProviders(t *testing.T) // Admin.Match nil → body contains "Matching: off"
```

- [ ] **Step 2:** Run `go test ./server/ -run StatusPage`. Expected: FAIL.
- [ ] **Step 3: Implement.** A self-contained page: inline CSS, styled like the `/_admin` templates. It shows the version, the scan line, "Add this server in Gutter: <scheme://host from the request>", and the matching on/off line. A ~10-line inline script polls `/library/refresh/status` every 2s while scanning and reloads when it finishes. Same-origin fetch reuses the browser's Basic credentials.
- [ ] **Step 4: First-run scan.** In `main.go`, replace the "scan skipped" block: `if count == 0 { log.Printf("first run: empty library, scanning now"); go scanFn() } else { /* existing skip log */ }`. This needs no test: it's one branch, and M1's success test checks it.
- [ ] **Step 5:** Run `go test ./...`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: scan immediately on an empty library; status page at /`

---

### Task S6: Dockerfile, compose, CI and image

**Files:**
- Modify: `Dockerfile`
- Create: `compose.yaml`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `admin.Version` ldflag (S5), `/data/config.yaml` optional (S2).

- [ ] **Step 1: Dockerfile.** Add `ARG VERSION=dev` to the builder and append `-X github.com/rthaines211/gutter-server/server/admin.Version=${VERSION}` to `-ldflags`. In the runtime image: `WORKDIR /data`, `VOLUME /data`, `ENTRYPOINT ["gutter", "-config", "/data/config.yaml"]`. Keep tesseract and the healthcheck.
- [ ] **Step 2: compose.yaml:**

```yaml
services:
  gutter:
    image: ghcr.io/rthaines211/gutter-server:latest
    restart: unless-stopped
    ports: ["8081:8081"]
    environment:
      GUTTER_PASSWORD: change-me          # required
      # GUTTER_API_KEY: ""                # optional, for scripts (Authorization: Bearer)
      # GUTTER_COMICVINE_KEY: ""          # see docs/CONFIG.md, Metadata
    volumes:
      - ./data:/data
      - /path/to/your/comics:/comics:ro   # remove :ro and set GUTTER_WRITEBACK=true to let Gutter write metadata into files
```

- [ ] **Step 3: ci.yml.** On `push` (main, tags `v*`) and `pull_request`, job `test`: setup-go 1.26, `go test ./...`. Job `image` (needs test, only on `refs/tags/v*`): `docker/setup-qemu-action`, `docker/setup-buildx-action`, `docker/login-action` to ghcr.io with `GITHUB_TOKEN` (`permissions: packages: write`), `docker/metadata-action` (tags: semver `{{version}}` + `latest`), `docker/build-push-action` with `platforms: linux/amd64,linux/arm64`, `build-args: VERSION=${{ github.ref_name }}`.
- [ ] **Step 4: Verify locally (single arch, light).** Ask the owner before running: `docker build -t gutter-test .`, then `docker run --rm -e GUTTER_PASSWORD=x -v $(mktemp -d):/data -v <3-CBZ folder>:/comics:ro -p 18081:8081 gutter-test`. Expected: `curl -s localhost:18081/healthz` prints `ok`; `curl -s -o /dev/null -w '%{http_code}' localhost:18081/library` prints `401`; `curl -su x:x localhost:18081/library` returns the 3 series within a minute. Without `GUTTER_PASSWORD`, the container exits non-zero with the GUTTER_PASSWORD message.
- [ ] **Step 5: Commit** `feat: compose file, CI, multi-arch GHCR image`

---

### Task S7: Docs

**Files:**
- Modify: `README.md`
- Create: `docs/CONFIG.md`, `docs/REMOTE-ACCESS.md`

- [ ] **Step 1: README.** In order: one paragraph on what it is; **Quick start** (download `compose.yaml`, set the comics path and `GUTTER_PASSWORD`, `docker compose up -d`, open `http://<host>:8081` and sign in with any username + the password, then in Gutter add the server address and enter the password when asked); then links to CONFIG, REMOTE-ACCESS and the license. The quick start fits one screen. Remove the "no authentication yet" warning.
- [ ] **Step 2: docs/CONFIG.md.** A table of every `GUTTER_*` env var and every config key: default and meaning. Sections: *Metadata* ("Gutter reads ComicInfo.xml from your files. Matching and enrichment need your own ComicVine dump (`localcv_db_path`); Metron, GCD and a ComicVine API key only add to it."), *Letting Gutter write to your files* (remove `:ro`, `GUTTER_WRITEBACK=true`, what it writes), *Upgrading* (`docker compose pull && docker compose up -d`), *Backups* (the `/data` dir; stop the container first, and never open the live DB from the host).
- [ ] **Step 3: docs/REMOTE-ACCESS.md.** Never port-forward plain HTTP. Option 1: Tailscale. Option 2: a reverse proxy with TLS, with one Caddyfile example (`comics.example.com { reverse_proxy localhost:8081 }`).
- [ ] **Step 4:** Check the docs for private details: `grep -rnE '100\.|tail[0-9a-f]+\.ts\.net|haineshome|/Volumes/' README.md docs/ compose.yaml config.example.yaml` returns nothing.
- [ ] **Step 5: Commit** `docs: quick start, config reference, remote access`

---

### Task A1: App sends source auth on every Go-backend request

**Files:**
- Modify: `lib/services/api_client.dart` (constructor, `_headers`, outcome on 401), `lib/providers/providers.dart` (`apiClientProvider`), `lib/services/mirror/cover_syncer.dart` + `lib/providers/mirror_provider.dart`, `lib/services/download_manager.dart` + `lib/providers/download_provider.dart`, `lib/services/remote_session.dart`, `lib/services/label_client.dart` (if they build their own requests)
- Test: `test/api_client_connection_test.dart`, `test/services/cover_syncer_auth_test.dart`, `test/services/download_manager_test.dart`

**Interfaces:**
- Produces:
  - `ApiClient({…, Map<String, String> authHeaders = const {}})`; `_headers` spreads `authHeaders` in.
  - `Future<int?> ApiClient.probeStatus()`: `GET /browse` with a 5s timeout. Returns the HTTP status, or null on a network error. `checkConnection()` becomes `(await probeStatus()) case final s? when s >= 200 && s < 300`.
  - `CoverSyncer({…, Map<String, String> headers = const {}})`.
  - `DownloadManager({…, Map<String, String> Function(String sourceId)? authFor})`: merged into request headers at fetch time, and never persisted in the journal.

- [ ] **Step 1: Write the failing tests** (`MockClient` from `package:http/testing.dart`):

```dart
test('sends source auth headers', ...)        // ApiClient(authHeaders: {'Authorization': 'Basic abc'}) → captured request has it, plus X-Device-ID
test('401 counts as server reached', ...)     // MockClient returns 401 → onRequestOutcome called with true
test('probeStatus returns 401', ...)          // → 401; on SocketException → null
test('cover syncer sends headers', ...)       // CoverSyncer(headers: {...}) → captured cover GET carries Authorization
test('journal never stores Authorization', ...) // enqueue with authFor returning auth → journal JSON has no "Authorization"; fetch request has it
```

- [ ] **Step 2:** Run `flutter test test/api_client_connection_test.dart test/services/`. Expected: FAIL.
- [ ] **Step 3: Implement.** `apiClientProvider` passes `source.authHeaders`. Find where `onRequestOutcome` decides reachability and make any HTTP response (401 included) count as reached. Wire `CoverSyncer` headers from `activeSourceProvider` in `mirror_provider.dart`. Wire `authFor` in `download_provider.dart` by looking up the source by id in `sourceListProvider`. Run `grep -rn "http.Client()\|\.get(Uri" lib/services` and give every Go-backend caller the headers.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS (the known `download_manager_test` journal flake passes when run alone).
- [ ] **Step 5: Commit** `feat: send source auth on API, cover and download requests`

---

### Task A2: Images send auth headers

**Files:**
- Modify: `lib/providers/providers.dart` (add `imageHeadersProvider`), `lib/services/page_prefetcher.dart`, `lib/widgets/cover_flight_route.dart`, and every `CachedNetworkImage(` / `CachedNetworkImageProvider(` site that loads from the server (`grep -rn "CachedNetworkImage" lib`, about 20 sites, all of them including personal-only screens, since the owner's server requires auth too)
- Test: `test/cache_layer_test.dart`

**Interfaces:**
- Produces: `final imageHeadersProvider = Provider<Map<String, String>>((ref) => ref.watch(activeSourceProvider).authHeaders);`. `PagePrefetcher` takes `Map<String, String> headers` (constructor) and passes `headers:` to `CachedNetworkImageProvider`.

- [ ] **Step 1: Write the failing test.** `test('prefetch and display share one cache entry with headers')`: two `CachedNetworkImageProvider(url, headers: h)` instances are `==` and resolve to the same `cacheKey`; and `PagePrefetcher(headers: h)` builds providers whose `headers` equals `h`.
- [ ] **Step 2:** Run `flutter test test/cache_layer_test.dart`. Expected: FAIL (no `headers` param on `PagePrefetcher`).
- [ ] **Step 3: Implement.** Each widget passes `httpHeaders: ref.watch(imageHeadersProvider)` (a provider gets `headers:`). Turn a stateless widget into a `ConsumerWidget` only when it has no other way to get the headers. Don't set `cacheKey` (the URL stays the key). After the change, `grep -rn "CachedNetworkImage" lib | grep -v "httpHeaders\|headers:"` lists only non-server images, if any.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: send source auth with cover and page images`

---

### Task A3: Onboarding asks for credentials on a 401

**Files:**
- Modify: `lib/screens/onboarding_screen.dart`, `lib/providers/source_provider.dart`
- Test: `test/screens/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.probeStatus()` (A1).
- Produces:
  - `OnboardingScreen.probe` changes to `Future<int?> Function(String url, Map<String, String> headers)?`.
  - `SourceListNotifier.updateDefaultBasicAuth(String username, String password)`, mirroring `updateDefaultApiKey`, with `AuthType.basic`.

- [ ] **Step 1: Write the failing tests:**

```dart
testWidgets('200 connects without asking for credentials', ...)
testWidgets('401 reveals username + password fields, then connects with Basic', ...)
  // probe: no Authorization → 401; Authorization == 'Basic ' + base64('me:pw') → 200
  // after entering me/pw and tapping Connect: default source authType == basic, username 'me', url saved
testWidgets('401 again shows "Wrong username or password"', ...)
testWidgets('null (unreachable) keeps the existing "Couldn\'t reach" error', ...)
```

- [ ] **Step 2:** Run `flutter test test/screens/onboarding_screen_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Probe each candidate URL. A 2xx saves as today. A 401 on a candidate stops trying the other candidates, remembers that URL, and shows the fields ("This server needs a password"). The second Connect probes with the Basic header, then saves the URL plus `updateDefaultBasicAuth`. The username field gets `autofillHints: [AutofillHints.username]`, and the password field gets `obscureText: true` and `AutofillHints.password`.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: onboarding asks for credentials when the server returns 401`

---

### Task A4: Library shows first-scan progress

**Files:**
- Modify: `lib/providers/scan_status_provider.dart`, `lib/screens/library_screen.dart` (the All Series empty branch, `filteredList.isEmpty` around line 559)
- Test: `test/screens/library_first_scan_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getScanStatus()`, `ScanStatus.isBusy/scanned/total`, `syncEngineProvider` (`SyncEngine.sync()`).
- Produces: `ScanStatusNotifier.watchIfBusy()`: one poll; if busy, it keeps polling (the existing 2s timer). On busy→done it calls `ref.read(syncEngineProvider)?.sync()`.

- [ ] **Step 1: Write the failing tests:**

```dart
testWidgets('empty library while scanning shows progress', ...)   // status scanning 120/583 → finds 'Scanning your library…' and '120 of 583'
testWidgets('scan finishing triggers a mirror sync', ...)          // busy then done → fake SyncEngine.sync called once
testWidgets('scan finished with zero series shows empty state', ...) // done, still empty → finds 'No comics found' and not 'Scanning'
```

- [ ] **Step 2:** Run `flutter test test/screens/library_first_scan_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** When the unfiltered library is empty on a custom (Go) source, call `watchIfBusy()` once (post-frame). The empty branch shows "Scanning your library… N of M" with a `LinearProgressIndicator` (value `scanned/total`, indeterminate while `total == 0`) when `phase == scanning`. Otherwise it shows the existing empty state, worded "No comics found in your library folder yet." when no filter is active.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5:** Update app `CLAUDE.md` "Backend API": every endpoint needs `Authorization` (Basic with any username + `GUTTER_PASSWORD`, or `Bearer GUTTER_API_KEY`); `/healthz` is open; `GET /` is the status page. Replace "Backend server scan takes ~2 minutes … Endpoints won't respond until scan completes" with "An empty server scans on first start; `/library/refresh/status` reports progress."
- [ ] **Step 6: Commit** `feat: library shows first-scan progress; docs for backend auth`

---

### Task M1: Owner migration and success test

Not code. Run it with the owner after everything above is merged. It touches the live homelab.

- [ ] **Step 1:** Grep for other API callers: `grep -rnE '8081|/library|/comics/' ~/projects/gutter-server/hostjob ~/projects/gutter-server/cmd ~/projects/panel-labels ~/docker/stacks/media-servers 2>/dev/null`. Give each one `Authorization: Bearer $GUTTER_API_KEY` from its env (launchd plists get an `EnvironmentVariables` key).
- [ ] **Step 2:** Stack compose: mount the existing config at `/data/config.yaml` (rename `admin_password` → `password`, keep `db_path` pointing at the current DB file), set `GUTTER_PASSWORD`, and set `GUTTER_API_KEY` = the current push `register_secret` (the personal build already sends it as Bearer). Rename the old env vars (`COMICVINE_API_KEY` → `GUTTER_COMICVINE_KEY`, and so on). Keep the library rw and set `GUTTER_WRITEBACK=true` (writeback is now off by default; a config file without `writeback_disabled` loads as off). Then `docker compose build && docker compose up -d --force-recreate`.
- [ ] **Step 3:** Check: `curl -s https://<backend>/healthz` → ok; unauthenticated `/library` → 401; the iPad (personal build) loads the library, covers and pages with no settings change; pushwatch and bubbles jobs log no 401s.
- [ ] **Step 4:** Tag `v0.1.0` on gutter-server. Wait for the Actions image, then set the GHCR package to **Public** (GitHub → Packages → gutter-server → Settings).
- [ ] **Step 5: Success test.** In a scratch dir on another machine (or a clean folder here), using only the README: copy `compose.yaml`, point it at a folder of CBZs, `docker compose up -d`. Watch the scan on `http://host:8081`. Add the server in the store build (enter the password on the 401 prompt) and read a comic. Repeat with no metadata keys and check the logs and UI for errors or dead ends.
- [ ] **Step 6:** Update the memory notes (deploy reference, rollout state).
