# Phase 3: Public Go backend — design

Parent: [App Store launch design](2026-11-05-app-store-launch-design.md), Phase 3.

## Intent

The Go backend (`~/projects/gutter-server`, rthaines211/gutter-server, AGPL) is the
"power user" server for Gutter. It's already public as source, but only the owner can
actually run it: there's no auth on the API, the config assumes the owner's homelab, and
nothing tells a newcomer what's happening while the first scan runs.

**Done when a stranger can follow the README, run `docker compose up`, and connect the
app.** "Connect" means: add the server in Gutter with a password, watch the first scan
progress, then open and read a comic.

## Decisions (made by the owner)

- **Single reader.** Each server has one set of credentials, and everyone who has them
  shares the same reading progress. No user accounts and no per-user tables.
- **Credentials come from env vars in compose.** `GUTTER_PASSWORD` is required, and the
  server refuses to start without it. `GUTTER_API_KEY` is optional. The same credentials
  protect `/_admin`.
- **First-run scan progress shows up in both places:** a status page served by the server
  and a scanning screen in the app.
- **ML/host-only features are off by default.** Their code stays in the repo. The public
  compose file and docs don't mention them.
- **Image: GHCR via GitHub Actions**, `ghcr.io/rthaines211/gutter-server`, multi-arch
  (amd64 + arm64), built when a version tag is pushed.
- **Rename comic-reader → gutter everywhere, now**, before the first public image: binary,
  Go module path, config dir, admin realm, log lines. The owner's homelab takes a one-time
  path change.
- **Metadata without keys:** ComicInfo.xml embedded in the files is the default.
  `localcv.db` is never shipped. **Matching stays a bring-your-own-`localcv.db` feature.**
  Metron, GCD and a live ComicVine key only fill gaps on top of it, as they do today, and
  this phase doesn't refactor the matcher. *(A Metron-only matcher is a possible later
  project.)*
- **The store app keeps Review and Creators hidden** (as on `feat/store-flavor`,
  15e7931), so the app needs no capability flag.
- **App work goes on `feat/store-flavor`**, because onboarding lives there. This phase's
  app PR follows 1a.

## Goals

1. Every endpoint requires auth, except `GET /healthz` and CORS `OPTIONS` preflight.
2. Starting the server needs one compose file, no config.yaml, and no edits beyond the
   library path and the password.
3. A fresh install starts scanning right away, and both the server page and the app show
   progress.
4. Without `localcv.db`, the server runs cleanly: no errors in the logs, and no
   matching/review UI that can't do anything.
5. The README quickstart and a config reference are enough for a stranger to succeed.
6. The owner's own setup keeps working after a documented migration.

## Non-goals

- Multi-user accounts, per-user progress, or roles.
- Built-in TLS. Docs point to a reverse proxy (Caddy/Traefik/NPM) or Tailscale.
- Publishing the Python ML jobs (bubble/panel detection, labeller) or documenting them.
- Push notifications for strangers. APNs needs the owner's key and bundle ID, so push stays
  an owner-only, undocumented feature.
- Docker Hub, Helm charts, unRAID templates. Those can come later if people ask.

## Anti-goals (a failure even if it technically works)

- A default setup that exposes a library to the network without a password.
- A default setup that writes to a stranger's comic files (ComicInfo.xml writeback, CBR→CBZ
  conversion) without them opting in.
- Errors or dead UI because no `localcv.db` is configured.
- A setup that takes a sysadmin to follow, or a README longer than one screen before the
  first `docker compose up`.

## Current state (from recon, 2026-11-05)

- Auth: only `/_admin` has it (Basic, any username, `admin_password` in config,
  `server/admin/auth.go`). The rest of the API is open. CORS `Allow-Headers` lacks
  `Authorization`.
- **The app sends no auth to the Go backend.** `ServerSource.authHeaders` exists
  (`lib/models/server_source.dart`), but only OPDS and push use it. `ApiClient` sends only
  `X-Device-ID`. Downloads build their own headers without auth (`series_detail_panel`,
  `issue_list_view`), and so does `CoverSyncer`. About 20 `CachedNetworkImage` /
  `CachedNetworkImageProvider` call sites send no headers either. Once auth is on, all of
  these would get 401s. The Komga adapter (Phase 1b) needs the same plumbing.
- The personal build's default source already carries an API key (the built-in push
  key, used as `Bearer` for `/devices`). If the owner sets `GUTTER_API_KEY` to the push
  register secret, the iPad authenticates with no app-side settings change.
- Startup: the scan is deliberately skipped at startup (the homelab's external drive can
  block). The scheduler's first tick is one `scan_interval` later (default 30m). **A fresh
  install shows an empty library for 30 minutes.**
- `GET /library/refresh/status` already reports scan progress, and the app has
  `scan_status_provider.dart` / `scan_indicator.dart` that poll it.
- Packaging: there's a Dockerfile (binary `comic-reader`, config at
  `/etc/comic-reader/config.yaml`, which it requires). There's no compose file, no CI, and
  no published image. `config.example.yaml` has homelab paths in it (`bubbles_dir:
  /media/Comics/.bubbles`).
- The Go module path is still `github.com/ryanhaines/comic-reader`.

## The design

### 1. Auth (server)

- One middleware wraps the whole mux, including `/_admin` and the review API. It replaces
  `admin.requireAuth`, and keeps that function's cross-site-write refusal for
  browser-originated requests.
- It accepts either:
  - `Authorization: Basic` with password = `GUTTER_PASSWORD`. Any username is accepted,
    as `/_admin` does today. *(Builder's call: any username, because the app's form asks
    for one and single-user has nothing to check it against.)*
  - `Authorization: Bearer <GUTTER_API_KEY>`, when an API key is set.
- Comparisons are constant-time. A 401 comes with `WWW-Authenticate: Basic realm="Gutter"`
  so browsers prompt for credentials (this is how the status page and `/_admin` work in a
  browser).
- Exempt: `GET /healthz` (Docker healthcheck, uptime monitors) and `OPTIONS`.
- Add `Authorization` to CORS `Allow-Headers`.
- Startup: if no password is set, log a clear message and exit non-zero. The one escape
  hatch is an explicit `GUTTER_AUTH=off` (for tests and `scripts/mk-dev-library.sh`),
  which logs a loud warning on every start. *(My call.)*
- Push device registration (`register_secret`) stays as it is, behind the new auth.
- Owner-side callers of the API (`hostjob/bubbles/run_panels.py`, `hostjob/pushwatch`,
  the panel-labels proxy, anything else that turns up) get the API key from their env and
  send it as Bearer. The builder lists them all with a grep for the port and host.

### 2. Config without a file

- Config file becomes optional. Env vars override the file, and the file overrides
  defaults. Minimum env set: `GUTTER_PASSWORD`, `GUTTER_API_KEY`, `GUTTER_COMICVINE_KEY`,
  `GUTTER_METRON_USER` / `GUTTER_METRON_PASS`, `GUTTER_WRITEBACK`, `GUTTER_SCAN_INTERVAL`.
  Anything more exotic stays file-only.
- Container defaults: library at `/comics`, DB/covers/cache under `/data`, port 8081.
  The config file lives at `/data/config.yaml`, which is optional. That way, saves from the
  admin console (add a dir, change the schedule) persist in the data volume.
- Rename `admin_password` → `password` in the file. *(No fallback alias. The owner
  migrates once.)*

### 3. Safe defaults for strangers' files

- The compose file mounts the library **read-only**, and writeback is **off by default**
  (`GUTTER_WRITEBACK=false`). Docs explain how to opt in: mount read-write and set it true.
  *(My call, from the anti-goal.)*
- The server notices when the library is read-only and turns off any write path (writeback,
  conversion, rename/organize) with one log line, instead of failing one file at a time.

### 4. Metadata without keys

- No `localcv_db_path` → no match runner (as today, `main.go`). The server reads embedded
  ComicInfo.xml at scan time. The review queue, enrichment, arcsync and creators index
  report "disabled" instead of erroring, and the log has one line per feature, not a
  stack of errors.
- `/_admin` hides its matching/review sections when there is no match runner. No app
  change, because the store flavor already hides Review and Creators.
- Docs say it plainly: matching needs your own `localcv.db`. Metron, GCD and a live
  ComicVine key add to it, and none of them works alone.
- Env overrides rename from the unprefixed names (`COMICVINE_API_KEY`, `METRON_USER`, …)
  to `GUTTER_*`. This is part of the owner migration.

### 5. First run

- **Server:** at startup, if the library DB has zero series, start a scan immediately in
  the background. The existing "skip scan at startup" behavior stays for non-empty DBs.
- **Server status page:** `GET /` (authed) serves a small self-contained HTML page with:
  the Gutter name and version, scan state ("Scanning… 120 of 583 folders" or "Ready — 583
  series"), the URL to enter in the app, and which metadata providers are on. It refreshes
  itself by polling `/library/refresh/status`. No framework. Match the style of the
  existing `/_admin` templates.
- **App:** when the active Go source's library is empty and the scan status says scanning,
  the Library tab (and the Read tab's empty state) shows "Scanning your library… N of M"
  instead of the empty state. It reuses `scanStatusProvider` polling, and when the scan
  finishes it triggers a mirror sync so series appear without a manual refresh.

### 6. App: send auth everywhere

- `ApiClient` takes the active source's `authHeaders` and sends them on every request.
  Downloads and `CoverSyncer` do too. Downloads add `Authorization` at request time and
  never write it into the download journal on disk.
- A 401 counts as "server reached" for connectivity, so a wrong password never shows the
  app as offline.
- Every `CachedNetworkImage` / `CachedNetworkImageProvider` that loads from a source sends
  that source's `authHeaders` (`httpHeaders:`). Use one small helper so call sites don't
  each rebuild headers. The cache key stays the URL, so the prefetcher and display widgets
  still share entries (see CLAUDE.md on the shared cache).
- This also unblocks Komga images in Phase 1b. Whichever phase lands first does it.
- Onboarding (on `feat/store-flavor`) probes `GET /browse` via `ApiClient.checkConnection`
  before it asks for credentials, and that probe will get a 401 once auth is on. Change
  the flow to URL, then credentials (password, optional API key), then probe. A 401 on
  the probe means "ask for or re-ask for credentials", not "server unreachable". So the
  flow is: URL, probe, then on a 401 show username and password fields and probe again
  with Basic auth. A server without auth (Komga with no auth) connects in one step. An API
  key stays a Settings → source option and isn't part of onboarding. *(My call.)*

### 7. Rename

- Module → `github.com/rthaines211/gutter-server`, binary → `gutter`, config dir →
  `/data/config.yaml`, admin realm and log prefix → Gutter. One mechanical commit, kept apart
  from behavior changes.

### 8. Off-by-default owner features

- Bubbles endpoints, hostjob, the labeller/panel proxy, the remote hub and push stay off
  unless their config is present. Most already behave this way. The builder checks each
  and strips owner paths from `config.example.yaml`.
- None of them appear in the public compose file or docs.

### 9. Packaging

- `compose.yaml` at the repo root: the image `ghcr.io/rthaines211/gutter-server:latest`,
  port 8081, a `./data:/data` volume, a library mount (`/path/to/comics:/comics:ro`) and an
  `environment:` block with `GUTTER_PASSWORD` (plus the optional keys, commented out).
  Use the existing healthcheck, pointing at `/healthz`.
- GHCR packages start private: after the first push, set the package to public (a one-time
  owner step, in the plan).
- `.github/workflows/release.yml`: on a `v*` tag, buildx multi-arch (amd64, arm64; CGO for
  SQLite, so QEMU or native arm runners), push `:vX.Y.Z` and `:latest` to GHCR, and run
  `go test ./...` first.
- Dockerfile: new binary/config paths, and runs without a config file.

### 10. Docs

- **README:** what it is, then a quickstart that fits on one screen (copy `compose.yaml`,
  set the library path and password, `docker compose up -d`, open `http://host:8081`,
  add the server in Gutter), then links.
- **`docs/CONFIG.md`:** every env var and config key, its default and what it does.
  Metadata providers. Turning on writeback. Upgrading (`docker compose pull && up -d`).
- **`docs/REMOTE-ACCESS.md`** (short): don't port-forward plain HTTP. Use Tailscale, or a
  reverse proxy with TLS. One Caddy example.

### 11. Owner migration

A checklist in the plan, not in the public docs: update the homelab compose (new image or
build path, `/data/config.yaml`, `GUTTER_PASSWORD`, `GUTTER_API_KEY`, keep the library rw and
writeback on), add credentials to the iPad's source, and update the hostjob/pushwatch/
proxy callers. Also update app `CLAUDE.md` "Backend API" for auth, and the stale "endpoints
won't respond until scan completes" line.

## Constraints

- Server work happens in `~/projects/gutter-server` (its own worktree/branch). App work
  happens in this repo. Both are public, so no personal hostnames, IPs or keys go in
  either.
- Don't break the owner's running homelab until the migration step. Deploy follows memory
  notes (local docker compose on the M2, Colima).
- No heavy local builds without asking (the Mac is the homelab). Multi-arch image builds
  happen in GitHub Actions.
- The app must still work with servers that don't require auth (Komga without auth, older
  self-builds). Sending headers when the source has auth = none is a no-op.

## Left to the builder

- Exact env var list beyond the minimum, and how the file/env merge is implemented.
- How "read-only library" is detected.
- Status page layout and copy.
- Task order and how the work splits into PRs (suggested: rename → auth + app image
  headers → config/compose/first-run → docs → CI/image).

## Success test

On a machine that has never run Gutter: follow only the README, `docker compose up -d`
with a folder of CBZs, open the status page and watch the scan, add the server in the store
build of the app with the password, and read a comic. Repeat with no `localcv.db` or keys at all,
and confirm there are no errors or dead UI.

<!-- flow-decisions:start -->
## Decisions

| Who | Stage | Decision | Why | Confirmed |
|---|---|---|---|---|
| Claude | Build · Review | Console SetScanInterval persists its value to config.yaml even when GUTTER_SCAN_INTERVAL is set; env still wins at next start | Restoring the file value would silently drop the user's console change; the ruling only required env to win at start | pending |
| Claude | Build · Review | config.example.yaml now ships writeback_disabled: true, matching the new off-by-default writeback | Copying the old example (false) would have silently opted a user into writing their files | pending |
| Claude | Review · Review | Read-tab first-scan state goes in read_screen.dart's empty-state block (~line 172), reusing a widget pulled out of the Library's inline scan state. No second watchIfBusy kick, because the IndexedStack always mounts LibraryScreen. | One progress widget for both tabs, and the existing Library kick and the ScanBanner sync already run on every tab. | pending |
| Claude | Review · Review | The image-header helper takes the URL and returns source auth only when the URL is on the source's base URL. | ComicVine/Metron cover URLs (creator bibliography, volume sheet, review guesses) would otherwise receive the server password or API key. | pending |
| Claude | Review · Review | The outbox drainer treats 401/403 as a pause, not a terminal drop, and source credentials load before runApp. | Otherwise a wrong password, or the cold-launch race before secure storage answers, silently deletes queued offline reading progress. | pending |
| Claude | Build · Review | main() reads secure-storage secrets into sourceCredentialsProvider; built-in-key merge stays in SourceListNotifier.build() (now synchronous), not in main | Keeps the built-in key logic in one place beside the fresh-install seed while still completing sources before any request | pending |
<!-- flow-decisions:end -->
