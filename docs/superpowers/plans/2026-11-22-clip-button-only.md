# Clip a panel: button only — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A long-press on the reader page no longer clips a panel; ⋯ → Clip a panel is the only way in.

**Architecture:** One branch in `ReaderScreen._handleLongPress` goes; the balloon long-press stays. The armed-tap flow is unchanged; only its "no panel" hint changes wording.

**Tech Stack:** Flutter, reader integration suite (`test/reader/`, `harness.dart`).

**Spec:** `docs/superpowers/specs/2026-11-22-clip-button-only-design.md`

## Global Constraints

- Keep long-press → next balloon (`_handleBubbleLongPress`) exactly as is.
- New hint copy, exact: `No panel here. Tap inside a panel to clip it.`
- Don't `dart format` whole files (repo isn't format-clean).

## Review Focus

- A resting thumb (long-press, 600 ms) on a Gutter-server page in page mode with panels: no clip outline, no clip hint. Pinned by the Task 1 test.
- Armed tap still clips (existing `Clip a panel: the armed tap…` test keeps passing).
- Balloon swap by long-press still works (existing bubble tests keep passing).

---

### Task 1: Remove long-press → clip

**Files:**
- Modify: `lib/screens/reader_screen.dart` (`_handleLongPress` ~line 1043; hint string ~line 1090)
- Test: `test/reader/server_only_features_test.dart`

**Interfaces:** none new. `_handleLongPress(ReaderSettings settings, Offset pos)` keeps its signature (still wired at `onLongPress`).

- [ ] **Step 1: Write the failing test** — in `server_only_features_test.dart`, next to the Komga long-press test:

```dart
testWidgets('Gutter server: long-press on the page offers no clip', (tester) async {
  await open(tester, gutter: true);
  final g = await tester.startGesture(const Offset(400, 300));
  await tester.pump(const Duration(milliseconds: 600));
  await g.up();
  await settleImages(tester);
  expect(find.textContaining('panel'), findsNothing);
  await disposeReader(tester);
});
```

- [ ] **Step 2: Run it, expect FAIL** (a clip hint such as "No panels detected…" appears)

Run: `flutter test test/reader/server_only_features_test.dart --plain-name "long-press on the page"`

- [ ] **Step 3: Implement** — `_handleLongPress` only calls `_handleBubbleLongPress(settings)`; drop the `_clipPanel` call and update its doc comment. Change the `panel == null` hint to the exact copy above.

- [ ] **Step 4: Run the reader suite, expect PASS**

Run: `flutter test test/reader/server_only_features_test.dart test/reader/reader_chrome_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/screens/reader_screen.dart test/reader/server_only_features_test.dart
git commit -m "fix(reader): long-press no longer clips a panel; use ⋯ → Clip a panel"
```
