# App Store Launch — Strategy & Design

Date: 2026-11-05 · Status: draft for approval

## Intent

Put the comic reader on the App Store as a free app with a one-time Pro
unlock, aimed at people who self-host comics. At launch it connects to
**Komga** or to the owner's **Go backend, published for anyone to run**.
Goal is **side income ("beer money")**: no services we operate, no
subscription obligations.

Why this shape: the app's strongest assets — reader quality (fit modes,
spread and panel zoom, page-turn feel), local-first offline mirror + sync,
and metadata/discovery — matter most to self-hosters, who already pay for
readers (Panels, Chunky). Komga users get the reader; the public Go
backend is the moat for people who want matching, arcs, chapters and
panel data that Komga doesn't have.

## Decisions (made by the user)

| Topic | Decision |
|---|---|
| Audience | Self-hosters: Komga users, plus people who run the Go backend. Kavita/OPDS later. |
| Success | Beer money. |
| Rework appetite | Whatever it takes for the right product. |
| Paid hooks | Reader quality, offline/sync, metadata & discovery. |
| Pricing | Free download + one-time Pro unlock (non-consumable IAP) at **$12.99**, with **no paid upgrades** for new versions (undercuts Panels' $19.99 per version and Komic's $22.99). |
| Free vs Pro | **Free:** connect one server, stream and read, **two-way progress sync**, basic fit modes (sync stays free to compete with free KMReader). **Pro:** offline downloads, guided panel + spread zoom, multiple servers, stats. |
| v1 server support | **Komga + Go backend, then Kavita before submission** (Kavita roughly doubles the reachable audience). OPDS in a later update. |
| Go backend | **Public at launch**, accepting the extra scope (auth, ComicVine handling, packaging, docs) and some install support. |
| Panel zoom | **On-device panel detection in v1** (Core ML), so it works on Komga too. |
| Stats / Creators | **Stats built locally** from on-device reading sessions. **No Creators/discovery screen for Komga in v1.** |
| Devices | iPad + iPhone (universal, one purchase). |
| Personal features | Separate personal build. Store build strips Claude panel, push, review deck, bedtime reminder, labeller; `make ipad` keeps today's build intact. |
| Repos | **New public repos for app and server.** The public app repo becomes the home for all development; the personal build is a flavor in it. Current private repos are archived. |
| History | **Fresh history**: each public repo starts from one clean initial commit. Old private repos remain the archive. |
| License | **App source-available** (forbids rebranded commercial clones, e.g. PolyForm Noncommercial); **server open source**. |

## Shape of the work: three projects, one launch

Each gets its own plan; all three must land before submission.

1. **Store app**: build flavors, Komga adapter, onboarding, StoreKit Pro,
   local stats and settings, App Review package.
   - **To do before submission: manage servers in the app.** Today the
     only way to sign in is first-launch onboarding; after that, Settings
     → Server URL changes the address but not the type or login, and
     fixing a wrong login means deleting the app. Free: change or replace
     the one server (type, address, login) through the onboarding form,
     and sign out. Pro: add more servers and switch between them (the
     source switcher's Add Server, already gated).
2. **On-device panels**: replace the Ultralytics model with a
   permissively licensed one, run it on-device, and feed the existing
   panel-step pipeline (`lib/services/panel_steps.dart`).
   - **Step 1, retrain (decided):** fine-tune **YOLOX-S** (Apache-2.0,
     COCO weights) on round 2's exact data: 727 train pages with the 70
     hard pages ×3, 150 held-out pages. Train on the Mac mini (MPS) or
     RunPod. YOLOX-S is ~9M params, ~10 MB after int8, which also fixes
     app size (today's `panel-ft-r2.pt` is YOLOv12x, 119 MB).
   - **Step 2, compare:** grade with `score.py`'s rules against the
     shipped r2 (cutoff 0.4, nofold: 90 good / 34 acceptable / 26 wrong).
     Ship only if YOLOX ties or beats r2 in ≥ 50% of bootstrap resamples
     and is within 5 good pages in ≥ 95%, plus a feel check in the
     reader. If behind: add mosaic augmentation, then try RF-DETR
     (Apache-2.0).
   - **Step 3:** Core ML export (int8), on-device inference, cache
     panel boxes in the mirror.
   - Drafts exist on the mini (`~/projects/panel-detect-train/`):
     `data-r2/`, `train_yolox.py`, `score_yolox.py`, cached r2
     predictions in `yolox/r2_preds.json`; YOLOX source cloned to
     `~/projects/YOLOX`. Untested; needs a venv with torch +
     `yolox_s.pth` from Megvii's GitHub release.
3. **Public Go backend** (from `~/projects/comic-reader`): request auth,
   ComicVine compliance, public repo + Docker image, first-run experience,
   docs.

Step 0 for projects 1 and 3 is **standing up the public repo** (see
"Repos & licensing"). Suggested order: 0 → 1 → 2 → 3 (2 and 3 can
overlap). *(Order is my call.)*

## Repos & licensing

- **App:** new public GitHub repo seeded from the current app with one
  clean initial commit. All future work happens there. The
  `personal` flavor lives in the public repo, but its private values
  (server URL, push key, backend-only endpoints) come from an untracked
  local file (e.g. `--dart-define-from-file=personal.json`, gitignored).
  Nothing personal is hardcoded. *(Mechanism is my call.)*
  `comic_reader_app` (private) is archived after cutover.
- **Server:** new public repo seeded from `comic-reader` with a clean
  initial commit. Before seeding, exclude local data and config:
  `*.db*` (`comic-reader.db`, `localcv.db`, `gcd.db`), `config.yaml`,
  `covers/`, `cache/`, `deploy.sh` and homelab-specific Makefile
  targets. Ship `config.example.yaml` only. The homelab deploy then
  builds from the public repo.
- **Pre-publish secret sweep** on both seeds (e.g. `gitleaks` or
  `trufflehog` over the working tree): no keys, hostnames
  (`<personal-domain>`, Tailscale IPs), Apple team secrets or personal
  paths. *(Tool choice is the builder's.)*
- **Licenses:** app under a source-available noncommercial license
  (PolyForm Noncommercial 1.0 suggested) so the source is visible but no
  one can ship a rebranded copy on the App Store. The owner, as
  copyright holder, still sells the App Store build. Server under
  **AGPL-3.0** so hosted forks stay open. *(AGPL over MIT is my call.)*
- **Dependencies:** check third-party licenses are compatible with
  distribution (the bundled YOLO weights are trained via Ultralytics,
  which is AGPL; shipping the model in a closed/noncommercial app may
  need an Ultralytics Enterprise license or a retrain on a permissively
  licensed detector). **Must resolve before project 2 ships.**

## Goals

- Store build works against a stranger's Komga server or their own copy
  of the Go backend, with zero knowledge of `<personal-server>`.
- Komga adapter feeds the existing mirror (`lib/services/mirror/`), so
  Library, Read tab, series detail, downloads and progress sync behave as
  they do today.
- Guided panel zoom works on any source, computed on-device.
- StoreKit Pro unlock with restore purchases.
- A stranger can `docker compose up` the Go backend from public docs and
  connect the app securely.
- Passes App Review (demo server, clean listing, privacy label).

## Non-goals (v1)

- OPDS-as-primary, local file import.
- Creators/discovery for Komga sources.
- Any service we host or pay for per user (cloud sync, accounts, AI).
- Subscriptions, ads, tips.
- Android.
- The backend's Python ML jobs (server-side panel/bubble detection,
  labeller) in the public package. On-device detection replaces them for
  users. *(My call.)*

## Anti-goals (failure even if it ships)

- Support load that outgrows beer money. Keep backend setup to one
  compose file and good docs; GitHub issues are the only support channel.
  *(The channel is my call.)*
- Recurring costs that outrun revenue.
- Personal-build regressions: store work must not break `make ipad` or
  the owner's daily use.
- Rejection or takedown for piracy optics or third-party ToS breaches.
- A public backend that exposes someone's library without auth.

## Constraints

- **ComicVine API terms prohibit commercial use.** The paid app must
  never call ComicVine. The public backend is free, and each user
  supplies their own ComicVine key (as Mylar and Komf do). `localcv.db`
  is not redistributed. Metron/GCD are the key-free paths. *(Pattern is
  my call; worth a ToS read before launch.)*
- **App Review** needs a reachable demo server with public-domain comics
  and credentials in the review notes. The listing and screenshots show
  public-domain or self-owned content only.
- Apple Developer account already paid (team N5CXCS4RMU).
- Hard assumptions to remove from the store build: default server URL in
  `lib/config/server_config.dart`, `PUSH_API_KEY` dart-define, and
  server-side reader settings (`GET/PUT /settings`), which become local
  for Komga sources.
- Foundation to build on: `ServerSource` already models multiple sources
  (`SourceType { custom, opds }`), the mirror is per-source, and
  `lib/services/opds_client.dart` exists.

## Market check (2026-11-05)

Full report: `reports/Self hosted comic reader market.md`. Qualified go: base case ~$180/month net, high ~$1,160. Discovery comes from Komga/Kavita client lists, Reddit and Discord, not App Store search ("komga", "kavita", "opds" have no search index). Top user complaint is progress/offline sync drifting from the server, which the local-first mirror solves. Launch tasks: get listed in Komga's and Kavita's client docs.

## App Review audit findings (2026-11-05)

From an `appstore-review` pass over the current personal build. All
must be handled in the store build before submission.

**Blockers**
- Default server `<personal-server>` (`lib/config/server_config.dart:11`)
  and `PUSH_API_KEY` baked into the binary
  (`lib/providers/source_provider.dart:21`). Store build: no default
  server, no embedded secrets, first-run onboarding, demo Komga for review.
- No `ios/Runner/PrivacyInfo.xcprivacy`. Add one: no tracking, no data
  collected, UserDefaults reason CA92.1, file-timestamp reason C617.1.
- No privacy policy or support link. Host a "no data collected" policy;
  link policy + support from More.
- 1024 App Store icon has an alpha channel
  (`AppIcon.appiconset/Icon-App-1024x1024@1x.png`); upload will be
  rejected. Flatten it.

**Rejection risks**
- Volume keys hijack the hardware buttons (hides HUD, pins volume) and
  default **on** (`lib/models/reader_settings.dart:32`). Guideline 2.5.9.
  Store build: default off, opt-in, explain in review notes.
- "Recap coming soon" placeholder (`lib/screens/recap_screen.dart`),
  reachable from the reader. Remove from store build.
- Missing `NSLocalNetworkUsageDescription`; LAN servers trigger the
  Local Network prompt with no explanation.
- Personal features (Claude panel webview, push + `aps-environment`,
  Review, Remote, labeller, backend-only Creators) stripped.
- Pro unlock must use IAP with a visible Restore Purchases button; no
  external payment links.
- Check name availability for "Longbox" in App Store Connect before
  investing in branding.

**Housekeeping**
- `ITSAppUsesNonExemptEncryption = false` (HTTPS only).
- `CFBundleName` is `comic_reader_app`; pubspec description is the
  Flutter default.
- iOS 26.0 minimum narrows reach; consider gating the FoundationModels
  feature and lowering the target.
- Stale `ios/Pods/UnrarKit`; hide the log viewer in the store build.

**Already clean:** no third-party login (no Sign in with Apple needed),
no accounts (no deletion flow), no ads/tracking/ATT, credentials in
`flutter_secure_storage`, no ATS exceptions.

## Architecture (the how)

- **Two build flavors** from one codebase (the public app repo):
  `personal` (today's app, private values from an untracked file) and
  `store` (the default). **Separate bundle ids**, so both install side by side on the
  owner's iPad. *(My call.)* The personal flavor also gets the Komga
  adapter and treats Pro as always unlocked. *(My call.)*
- **Server adapters**: Komga adapter alongside the Go API client, both
  feeding the mirror's push-then-pull sync. `SourceType` gains `komga`.
- **Pro gating**: one entitlement provider (Riverpod) backed by StoreKit.
  **Every user gets the mirror** as the data layer. Pro gates downloads
  and offline reading, a second source, guided zoom, and stats. *(My
  call. Making the mirror Pro-only would mean a second data path.)*
- **Onboarding**: first launch asks for the server type, URL and
  credentials. No default server.
- **Backend auth**: a user/API-key login on all endpoints. The app sends
  it per source (`AuthType` already has basic/apiKey).

## Left to the builder

- Flavor mechanism (Dart define vs Flutter flavors vs separate entrypoint).
- Komga API mapping (series/books/read-progress → mirror tables), auth,
  and sync watermarking (Komga has no `/sync` delta endpoint).
- Core ML integration path (platform channel vs plugin), model size vs
  accuracy tradeoff, caching panel results in the mirror.
- Backend auth design details, and the Docker image registry.
- StoreKit plugin (`in_app_purchase` default).
- Icon, listing copy. **App name must change:** Komga's docs already list an iOS OPDS reader called "Longbox"; pick and check a new name in Phase 0.
- Demo server for review (e.g. a small Komga on the homelab via NPM with
  a reviewer account).
- Privacy policy page and App Privacy label (expected: no data collected).
