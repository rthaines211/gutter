# App localization plan: de-DE, es-MX, fr-FR, pt-BR

Date: 2026-11-11. Status: plan only, no code changed.

The store listings already exist in four languages (`fastlane/metadata/{de-DE,es-MX,fr-FR,pt-BR}`).
The app UI is English only. This plan puts the store-visible UI into the same four languages.

## Measurements (main @ e8c3f2d)

How counted: a script over `lib/**/*.dart` collected string literals that hold prose
(a space, a capital start, or a UI argument such as `Text(`, `label:`, `title:`,
`tooltip:`, `message:`, SnackBar, dialogs). It dropped imports, keys, URLs, SQL, prefs keys
and lower-case log/exception text. A 45-line random sample was ~85-90% true UI strings.
Raw hits 1,038; after the filter **965 strings**. Treat ±10%.

| Pattern in `lib/` | Count |
|---|---|
| `Text(` | 572 |
| `label:` | 204 |
| `title:` | 113 |
| `SnackBar(` | 45 |
| `tooltip:` | 20 |
| `hintText:` | 12 |
| `AlertDialog(` | 11 |
| `semanticLabel` | 2 (few a11y labels exist; most icons have none) |
| Interpolated `Text('...$x')` | 57 |
| Plural ternaries (`== 1 ?` etc.) | 32 |
| `deviceNoun` uses (tablet/phone/iPad in sentences) | 18 |
| `toUpperCase()` on display text | 29 |
| Hand-made month arrays (`_months`, `'Jan'`, `JANUARY`) | 5 files |
| `intl` / `DateFormat` / `NumberFormat` | 0 (not a dependency) |
| `flutter_localizations`, ARB, `l10n.yaml` | none |

### Strings per area (filtered count, 965)

| Area | Strings | Plan |
|---|---|---|
| Onboarding, Servers, Settings, More, Pro sheet, Privacy, Downloads, sync/scan banners, offline | ~234 | Translate (first impression + purchase path) |
| Library, series detail, filters, sort, facets, issue lists | ~165 | Translate |
| Read tab, resume hero, stats, this week, streaks, stamps | ~145 | Translate |
| Reader (Aa panel, settings form, toolbar, end card, tap zones, more menu) | ~106 | Translate |
| Shell / services / models (error text, filter names, section names) | ~54 | Translate (needs a no-context lookup, see below) |
| Gutter-server-only but store-visible (queues, chapters, rename, metadata edit, enrichment) | ~85 | Translate in the last batch |
| **Store-hidden** (Remote, Review, Creators, Arcs, labeller, Recap, log viewer, Claude, smart filters, flag reasons) | ~185 | **Leave English** |

Store-visible total to translate: **~780 strings**, about 3,000 English words.
110 of the 965 live outside widgets (`services/`, `providers/`, `models/`, `config/`):
`arc_shelves` 17, `server_source` 14, `label_client` 12, `library_filter` 9, `page_fetcher` 5,
`scan_provider` 5, `local_import_provider` 5, `api_client` 4. Most store-visible ones are
messages that end up in a SnackBar.

### Tests

- 237 test files. **70 files have 759 text finders** (`find.text`, `find.textContaining`,
  `find.widgetWithText`, `find.byTooltip`, `find.bySemanticsLabel`).
- 80 test files build their own `MaterialApp(` (including `test/reader/harness.dart`).
  None pass `localizationsDelegates`.
- The suite runs as personal, as iOS, with the default test font (square glyphs, wide).
  CLAUDE.md already says phone header rows overflow at 390 wide with it.

## Recommended approach: `flutter_localizations` + `gen_l10n` (ARB)

Why: it is the Flutter-native path, needs no third-party runtime package, makes ICU
plurals and placeholders type-checked Dart methods, and ARB is the file format every
translator and translation tool reads. `intl` comes in as a transitive dependency and
also gives `DateFormat` for the month arrays.

Alternatives rejected:
- `easy_localization` / `slang`: extra runtime package and own conventions; no gain
  for four locales.
- Hand-rolled `Map<String,String>`: no plurals, no type checks, no tooling.

Design decisions:
1. **English ARB values = today's literals, word for word.** Then the 759 English
   finders keep passing with no test edits.
2. **`context.l10n` extension with an English fallback**:
   `Localizations.of<AppLocalizations>(this, AppLocalizations) ?? lookupAppLocalizations(const Locale('en'))`.
   The 80 test-built `MaterialApp`s keep working without delegates.
   (ponytail: avoids touching 80 test files; add delegates to tests only where a test
   checks a non-English locale.)
3. **No-context strings** (services/providers/models): return a code or enum and map it to
   text in the widget where possible. For the few that must stay strings (SnackBar text built
   in a provider), use a top-level `l10nNow` that does
   `lookupAppLocalizations(basicLocaleListResolution(PlatformDispatcher.instance.locales, supported))`.
4. **Store-hidden features stay raw English literals.** Do not extract them. A lint
   comment `// l10n: personal-only` on the file marks the intent.
5. **Plurals** use ICU (`{count, plural, one{...} other{...}}`). Replace all 32 ternaries,
   including "N comics on this iPad" / "N on iPad".
6. **`deviceNoun`**: German and French need gender/case agreement, so do not splice a noun
   into a sentence. Use an ICU `select` on `{device, select, ipad{...} tablet{...} phone{...}}`
   per sentence (18 sites).
7. **Dates**: replace the 5 hand-made month arrays with `DateFormat.MMMd(locale)` etc.
   `toUpperCase()` on translated text is fine for these four languages (no Turkish i).
8. **Server-provided text stays as-is**: series/issue names, Komga/Kavita/Gutter
   error bodies (`{"error": ...}`) are English or user data. Wrap them in a translated
   frame ("Server error: {message}") only.
9. **Platform**: add `CFBundleLocalizations` (en, de, es, fr, pt-BR) to `ios/Runner/Info.plist`
   or iOS reports only English to Flutter. Add `InfoPlist.strings` per locale for
   `NSLocalNetworkUsageDescription`. Android: `android/app/src/main/res/xml/locales_config.xml`
   for the per-app language setting.
10. **Locale fallback**: `es-MX` ARB as `app_es.arb` (covers all Spanish), `pt-BR` as
    `app_pt.arb` (covers pt-PT too), `de`, `fr`. Any other locale → English.

## Phases and effort

| # | Phase | Days |
|---|---|---|
| 0 | Setup | 0.5 |
| 1 | Extraction, 6 batches | 6.0 |
| 2 | Plurals, `deviceNoun`, dates, no-context strings | 1.5 |
| 3 | Translation draft + native review | 1.0 own time (+ 3-7 calendar days review) |
| 4 | Layout pass (German first) | 2.0 |
| 5 | Tests | 1.5 |
| 6 | Store copy + ASC Languages | 0.5 |
| 7 | Device QA | 1.5 |
|   | **Total** | **~14.5 dev days** |

### Phase 0: setup (0.5 d)
- `pubspec.yaml`: `flutter_localizations: sdk: flutter`, `intl: any`, `flutter: generate: true`.
- `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
  `output-localization-file: app_localizations.dart`, `nullable-getter: true`.
- `MaterialApp` in `lib/app.dart`: `localizationsDelegates`, `supportedLocales`.
- `context.l10n` extension and `l10nNow` in `lib/l10n/l10n.dart`.
- Info.plist / Android locale config (decision 9).
- One string end to end (Read tab title) to prove the pipeline. `flutter test` green.

### Phase 1: extraction in batches (6 d, ~130 strings/day)
One PR per batch. Key names `<screen>_<meaning>` (`onboarding_serverAddressLabel`).
Each key gets a `@description` for the translator (where it shows, max width if tight).
1. Onboarding, Servers, Pro sheet, Privacy sheet (purchase + first launch).
2. Settings, More, Downloads, local import, offline banner, sync/scan banners.
3. Library screen, filter chips, facet picker, sort sheet, search, index rail.
4. Series detail (panel + header + stat tiles + issue list/grid + download sheet).
5. Read tab (resume hero, up next, this week, just added, streak, stamps), Stats.
6. Reader (Aa panel, settings form, toolbar, filmstrip, end card, tap zones, more menu),
   then Gutter-server-only store-visible screens (queues, chapters, rename, metadata edit).
After each batch: `flutter test` must stay green with no test edits (English unchanged).
A grep check script lists remaining literals in batch files so nothing is missed.

### Phase 2: hard strings (1.5 d)
32 plural ternaries → ICU plural. 18 `deviceNoun` sentences → ICU select.
5 month arrays → `DateFormat`. Number output (`toStringAsFixed`, 8 sites; stats hours,
GB sizes) → `NumberFormat` (decimal comma in de/fr/es/pt). Move no-context strings
(decision 3).

### Phase 3: translation (1 d own time + review)
- Draft all four ARBs with Claude from `app_en.arb` + `@description`s, using the glossary
  from the existing store listings (same words for "issue", "series", "Pro", "spread",
  "panel zoom"). Keep `Gutter`, `Komga`, `Kavita`, `CBZ` untranslated.
- Native-speaker review per language: ~3,000 words each. Options: a friend/user who
  reads comics in that language (best for terms like issue/Heft/numéro/edição), or a paid
  reviewer (~$0.04-0.08/word review-only ≈ $120-250 per language). Review in a sheet
  (key, English, draft, notes) exported from ARB; reviewer sees screenshots from Phase 4.
- `flutter gen-l10n` warns on untranslated keys; CI fails if any of the 4 ARBs lacks a key.

### Phase 4: layout pass (2 d)
German runs ~30% longer; French ~20%; es/pt ~15-25%.
Known risks: phone header rows (Library, Arcs) already overflow at 390 wide; the
Library segmented control (All Series / Collections / Sources); filter chip bar;
`FloatingTabBar` labels; reader rail labels and Aa panel segmented rows (`FIT` etc.);
Pro sheet buttons; stat tiles ("UP NEXT", "THIS WEEK" in caps get wider);
SnackBars with long sentences.
Fixes: `Flexible` + `TextOverflow.ellipsis`, `FittedBox(fit: scaleDown)` on one-line
caps labels, wrap segmented labels to 2 lines, shorter German wording via `@description` width hints.
Work through German on a phone first, then iPad portrait, then the other three.

### Phase 5: tests (1.5 d)
- Existing 759 finders: no change expected (English identical). Fix only the ones that break.
- New `test/l10n/arb_keys_test.dart`: every key in `app_en.arb` exists in all 4 ARBs,
  placeholders match, ICU parses (load each `lookupAppLocalizations`).
- New `test/l10n/overflow_test.dart`: pump the main store screens (Onboarding, Library,
  Series detail, Read tab, Settings, Pro sheet, reader chrome) with `locale: Locale('de')`
  and delegates, at 600 wide (phone, per CLAUDE.md) and 800×600 (tablet); fail on
  `FlutterError` overflow. The square test font exaggerates width, so this is a
  conservative check.
- One store-flavor test (`isStore = true`) that store-hidden rows are still absent in `de`.

### Phase 6: store copy (0.5 d)
- App Store Connect → App Information: the "Languages" list on the product page comes
  from the build's `CFBundleLocalizations` / `.lproj`; check it shows English, German,
  French, Spanish (Mexico), Portuguese (Brazil) after upload.
- Update `fastlane/metadata/*/description.txt` and `release_notes.txt`: say the app is in
  that language. Keep store copy true to the build (CLAUDE.md). Run the listing-accuracy check.
- Play Console: same for the Android listing (`docs/app-store/play-console.md`).
- Website (getgutter.app) one line: "Available in ...".

### Phase 7: device QA (1.5 d)
See "What to test on device".

## Risks

| Risk | Mitigation |
|---|---|
| Missed literals (heuristic count ±10%) | Per-batch grep script; pseudo-locale run (wrap every value as `[!! ... !!]`) shows any raw English left |
| German overflow on phone | Phase 4 + overflow test; ellipsis/scaleDown defaults |
| Wrong comic terms (machine draft) | Glossary from store listings; native review is a release gate |
| Strings built outside widgets show the wrong language after a live language switch | `l10nNow` reads current locale each call; iOS restarts the app on per-app language change anyway |
| Personal-only English inside a translated screen (mixed files like More, Settings) | Those rows are hidden in store flavor; personal build is the developer's own |
| Server error text stays English | Accept; wrap in a translated prefix |
| Every new string later needs 4 translations | `arb_keys_test` fails CI on a missing key; draft with Claude, batch reviews per release |
| `sameServer`/keys accidentally translated (pref keys, enum names) | Only extract display text; enum `name` stays the stored value |
| Store 1.0.x users on a mid-release build | Ship all four at once in one release, not batch by batch |

## What to test on device

Set the device language (Settings → General → Language & Region) and also the per-app
language (Settings → Gutter → Language) on the iPad, the iPhone and one Android device.
For each of de, es-MX, fr-FR, pt-BR (German in full, the others a spot check):
1. Store build, first launch: onboarding, add Komga demo server, wrong password message.
2. Pro sheet: price string comes from StoreKit (already localized), buttons fit.
3. Library: header row, segmented control, filter chips, facet picker, sort sheet,
   phone and iPad portrait/landscape.
4. Series detail panel: stat tiles, issue list, download sheet, "N on iPad" badge plural (1 vs 3).
5. Read tab: resume card dates ("LAST READ" + month), this week, streaks.
6. Reader: rail labels, Aa panel, settings form, end card, Panels/Bubbles trial note.
7. Offline: airplane mode banner "Offline · N comics on this iPad" (1 and many).
8. Downloads: remove dialog with `deviceNoun` ("tablet" on Android, "phone" on iPhone).
9. Stats: numbers with decimal comma, chart axis day names.
10. Personal build in German: hidden features still show English, nothing crashes.
11. Unsupported locale (e.g. Japanese) falls back to English.
12. VoiceOver on 3 screens: labels read in the device language.
