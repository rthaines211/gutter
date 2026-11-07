# Long-term roadmap

Written 2026-11-07 from an assessment session. Estimates are for one developer
and are rough.

| Priority | Item | Why |
|---|---|---|
| Now | Xcode 27.x build (needs macOS 26.6 first) | Fills the iPhone Duo inner screen; App Store will require the SDK |
| Next | Android app | Biggest new audience; Komga/Kavita users need no Gutter server |
| Then | OPDS + KOReader sync in gutter-server | Cheap; covers e-ink and other reader apps |
| Later | Mac server app (DMG first, App Store after a spike) | Only helps Gutter server users |
| Later | Two-page mode | Helps iPad, Duo, Android tablets and desktop |
| Later | Windows app | Same Go server and Flutter code; wrapper differs |
| Skip | Kobo Sync, Send to Kindle | Brittle or one-way; Komga and KCC cover them |

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

- Kobo Sync: reverse-engineered Kobo store API, 3–6 weeks, breaks when Kobo
  changes it. Komga handles it.
- Kindle: no model opens CBZ/CBR; needs KCC conversion to EPUB and Send to
  Kindle. One-way, no progress sync.
