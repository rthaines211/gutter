# Long-term roadmap

Written 2026-11-07 from an assessment session. Estimates are for one developer
and are rough.

| Priority | Item | Why |
|---|---|---|
| Now | Xcode 27.x build (macOS 27.2 installed; install Xcode 27.2) | Fills the iPhone Duo inner screen; App Store will require the SDK |
| Now | PDF test on the demo Komga/Kavita (10 min) | Shows whether app users can already read PDFs |
| Next | Android app | Biggest new audience; Komga/Kavita users need no Gutter server |
| Then | OPDS + KOReader sync in gutter-server | Cheap; covers e-ink and other reader apps |
| Later | PDF support in gutter-server | Some DRM-free sales ship only PDF; Humble comic bundles usually offer CBZ too |
| Later | Mac server app (DMG first, App Store after a spike) | Only helps Gutter server users |
| Later | Two-page mode | Helps iPad, Duo, Android tablets and desktop |
| Later | Windows app | Same Go server and Flutter code; wrapper differs |
| Skip | Kobo Sync, Send to Kindle | Brittle or one-way; Komga and KCC cover them |
| Skip | Humble Bundle library integration | No official customer API; see below |

## Parallel work (waves)

- Wave 1 (started 2026-11-08): cloud sessions for OPDS + KOReader sync
  (gutter-server) and Android (gutter). Mac server app spike waits for Xcode 27.
- Wave 2: install Xcode 27 with no local agents running; Mac app spike;
  Android device test; deploy OPDS.
- Wave 3: full Mac app, two-page mode (after Android merges), Windows.
- Limit: review and device tests. About 3 lanes at once.

## iPhone Duo

- Inner screen 626×890pt (portrait), outer 466pt. Apps fill the inner screen
  only when built with the iOS 27.1+ SDK; older builds letterbox at ~402pt.
- Fold/unfold is a size change; the reader already keeps place on it
  (`_recalculateTransforms(keepPlace: true)`).
- Done (PR #34): `deviceNoun` cutoff 700pt; reader sessions end only on
  `paused`, so Split View reading counts.
- Flutter fills `MediaQuery.displayFeatures` only on Android. Build any fold
  logic on it (works on Android foldables now, iOS when the engine PR lands);
  don't add UIKit-only plugins.

## Android (~5–8 weeks)

- No `Platform.isIOS` checks, no Cupertino widgets; all plugins support Android.
- No `android/` folder yet (`flutter create --platforms=android .`).
- Native work: `files` channel (~30 lines Kotlin); panel model: export
  `panel-ft-r2.pt` to TFLite/ONNX + Kotlin bridge (2–4 days). `push` and
  `open_url` are personal-only, skip.
- Also: cleartext HTTP network security config for local servers, Play
  Billing product for Pro, back gesture and edge-to-edge insets, device range.
- Play Store: new personal accounts need a closed test with 12 testers for
  14 days before production.
- First step: run on the emulator against the demo Komga (ask first, heavy build).

## PDF

- gutter-server: the scanner only adds `.cbz`/`.cbr` (`server/scanner.go:443`,
  `server/browse.go:20`). PDFs never reach the library. Leftover PDF code: raw
  download content type (`server/comic.go:214`), writeback skips PDFs, the
  app's metadata sheet has a PDF caption.
- Work: a PDF page renderer. Go has no good pure-Go one. Choices: MuPDF (CGO,
  AGPL), pdfium (CGO), or exec `pdftoppm` (poppler) like `tesseract`. The
  choice affects the Docker image and the Mac server app.
- App with Komga/Kavita: no format filter, so PDF books show up. Komga
  probably renders PDF pages to images; Kavita's web reader uses pdf.js, so
  `/api/Reader/image` may not serve PDF pages.
- **Test (do first):** put one public-domain PDF comic in
  `media-servers/komga-demo/comics`, rescan both demo servers (Komga deep scan
  + empty trash, Kavita forced scan), open it in Gutter on each. If Kavita
  fails, hide or label PDF books from Kavita until fixed.

## OPDS + KOReader sync (~2 weeks)

- gutter-server has neither today. Komga already has OPDS, Kobo Sync and
  KOReader Sync.
- OPDS (+ OPDS-PSE page streaming) reaches KOReader on Kobo and jailbroken
  Kindles, plus Panels/Chunky and similar apps.
- KOReader sync is a few progress endpoints. Mapping KEPUB/EPUB positions to
  page numbers is the risky part.
- Test first: Kobo on the demo Komga + Gutter on iPad. If progress syncs both
  ways, Komga users already have Kobo support.

## Mac server app (~3–5 weeks)

- gutter-server already builds and runs natively on macOS (go-sqlite3 and
  go-unarr compile; only external program is `tesseract`).
- DMG (Developer ID + notarization) and Mac App Store are separate routes from
  one Xcode project. The App Store does not take DMGs.
- App Store risk: sandbox. The Go binary as an embedded helper inherits the
  sandbox but not folder access; the app must pass an implicit security-scoped
  bookmark that Go resolves via a CGO shim. Spike this first (1–2 days).
  Fallback: link Go as a `c-archive` (~1 extra week).
- Cheapest first step: Homebrew formula + `brew services` (~1 day).

## Skipped

- Humble Bundle: no official customer library API. Community tools use a
  reverse-engineered API (session cookie, `X-Requested-By: hb_android_app`)
  that can break and may break Humble's terms; a store app logging into it is
  an App Review risk. Instead: users download with Humble's site or a
  community downloader into their comics folder, and the server scans it.
  Humble comic bundles usually offer CBZ, which works today.

- Kobo Sync: reverse-engineered Kobo store API, 3–6 weeks, breaks when Kobo
  changes it. Komga handles it.
- Kindle: no model opens CBZ/CBR; needs KCC conversion to EPUB and Send to
  Kindle. One-way, no progress sync.
