# Manage Servers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit, replace, sign out of, and (Pro) add and switch servers in the app, without losing queued progress silently.

**Architecture:** A `ServerActions` object (provider) owns the source lifecycle: same-server edits stay in place, replaces add a new id and forget the old one, sign-out forgets. Forget deletes the keychain, prefs, mirror, covers, cache and downloads. A `ServersScreen` drives it and reuses `OnboardingScreen` as the edit/add form. The UI flushes the outbox before any forget and asks if entries remain.

**Tech Stack:** Flutter, flutter_riverpod 3, drift, flutter_secure_storage.

**Spec:** `docs/superpowers/specs/2026-11-06-manage-servers-design.md`

## Global Constraints

- Don't `dart format` whole files.
- Riverpod 3: no `StateProvider`; `.value`, not `valueOrNull`.
- Dialog copy (exact):
  - Pending: title `N changes not synced to <name>`, buttons `Try again` / `Discard and continue` / `Cancel`.
  - Replace: `Replace <old name>?` / `Its library and downloads on this iPad are removed.`
  - Sign out: `Sign out of <name>?` / `Its library, downloads and reading stats on this iPad are removed.`
- Pro reason string: `'More than one server is part of Pro.'`
- Tests run as personal (`isStore=false`). Store tests set `isStore = true` and reset it.

## Review Focus

1. A forget fails part-way (a file is locked or missing). It must not throw before the source is removed from the list. → Task 2 test: forget with no files on disk still removes the source.
2. Signing out of the active default when other servers remain. The new active server must get `isDefault`. → Task 2 test.
3. The same URL with a trailing slash or a different scheme. `sameServer` compares normalized URLs, so `https://a/` equals `https://a`. → Task 2 test.
4. The user cancels the pending dialog. Nothing is deleted and the source stays active. → Task 5 test.
5. Editing a server that is not active to a new address. The active server does not change. → Task 2 test.

---

### Task 1: Delete helpers (files + downloads)

**Files:**
- Create: `lib/services/source_files.dart`
- Modify: `lib/services/download_manager.dart` (add `deleteSource`)
- Test: `test/services/source_files_test.dart`, `test/services/download_manager_test.dart`

**Interfaces:**
- Produces:
  - `Future<void> deleteSourceFiles(String docsDir, String sourceId)`. It deletes `mirror_<id>.sqlite`, `-wal`, `-shm`, `covers/<id>/` and `cache/<id>/` when they exist. Missing paths are not an error.
  - `Future<void> DownloadManager.deleteSource(String sourceId)`. It cancels every queued item of that source, drops its completed items, deletes `downloads/<id>/`, persists the journal and emits.

- [ ] **Step 1:** Tests:
  - `deleteSourceFiles removes only that source`: create files for ids `a` and `b` in a temp dir, delete `a`, then check that every `a` path is gone and every `b` path still exists.
  - `deleteSourceFiles tolerates missing paths`: it completes on an empty dir.
  - In download_manager_test, `deleteSource drops completed + dir for that source only`. Follow the existing test setup.
- [ ] **Step 2:** `flutter test test/services/source_files_test.dart test/services/download_manager_test.dart` → FAIL.
- [ ] **Step 3:** Implement both. Iterate over a copy of the queue when you call `cancel`. Then delete the dir recursively, wrapped in try. Add the comment `ponytail: an in-flight page may land after the dir delete; orphan, swept never`.
- [ ] **Step 4:** Run the same command → PASS.
- [ ] **Step 5:** Commit `feat: delete a source's files and downloads`.

### Task 2: ServerActions (lifecycle logic)

**Files:**
- Create: `lib/providers/server_actions.dart`
- Modify: `lib/providers/source_provider.dart`
- Test: `test/providers/server_actions_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `bool sameServer(ServerSource a, ServerSource b)`: same `type` and `normalizeServerUrl(baseUrl)` equal. Move `normalizeServerUrl` and `serverUrlCandidates` to `lib/config/server_url.dart`, and have `onboarding_screen.dart` re-export them so existing imports still work.
  - `typedef OutboxDrain = Future<void> Function(ServerSource source, SyncQueue queue);`
  - `final serverActionsProvider = Provider<ServerActions>((ref) => ServerActions(ref));`
  - `class ServerActions`:
    - `Future<int> pendingCount(ServerSource s)`
    - `Future<int> flushOutbox(ServerSource s)`: drains and returns the remaining count.
    - `Future<void> save({ServerSource? old, required ServerSource found})`
    - `Future<void> signOut(ServerSource s)`
    - `@visibleForTesting OutboxDrain drain`: defaults to `SyncQueueDrainer(queue: q, client: clientFor(s, deviceId: …, sessions: LocalSessionStore(<docs>/cache/<id>/sessions.json))).drain()`.
  - The queue path is `<docs>/cache/<id>/sync_queue.json` from `await ref.read(docsDirProvider.future)`.

`save` rules:
- `old != null && sameServer(old, found)`: `edit(old.id, found with old.id, old.name, old.isDefault)`.
- `old != null`, different server: add `found` with a new `generateSourceId()` and `old.isDefault`. Select it only if `old` was active. Then forget `old`.
- `old == null`: add with a new id and `isDefault: false`, then select it.

Build the new copies with the `ServerSource(...)` constructor. `copyWith` can't set `id` or `isDefault`.

`signOut(s)` rules:
- Another source exists: if `s` is active, select another one first. If `s.isDefault`, the active one takes `isDefault`.
- `s` is the last source: add a blank `ServerSource(id: generateSourceId(), name: 'My Server', type: custom, baseUrl: '', authType: none, isDefault: true)` and select it.
- Then forget.

Forget order:
1. Select the next active source first, so `mirrorDbProvider` closes the old DB.
2. `sourceListProvider.notifier.remove(id)`.
3. `downloadManagerProvider?.deleteSource(id)`.
4. `deleteSourceFiles`.

Steps 3 and 4 are wrapped in try/log, so a file error never blocks the remove.

`source_provider.dart`: `_withCredentials` seeds `builtInApiKey` only when `s.isDefault && s.type == SourceType.custom && s.authType == AuthType.none`.

- [ ] **Step 1:** Tests. Use a container with mock prefs, mock secure storage (`FlutterSecureStorage.setMockInitialValues({})`), and `docsDirProvider.overrideWith((_) async => tmp.path)`. Set `drain` to a fake.
  - `same server keeps id and data`: login change, the id is unchanged, and `mirror_<id>.sqlite` still exists.
  - `trailing slash is the same server`.
  - `new address gets new id, is selected, old files deleted, isDefault carried`.
  - `editing an inactive server to a new address keeps the active one`.
  - `add selects the new server, isDefault false`.
  - `sign out of last server leaves a blank default with a new id` (baseUrl `''`, id != old).
  - `sign out of active default with others: next becomes active + default`.
  - `forget with no files on disk still removes the source`.
  - `flushOutbox returns what the drain left` (the fake drain removes 1 of 2 → 1).
  - `builtInApiKey does not overwrite a basic-auth default`.
- [ ] **Step 2:** `flutter test test/providers/server_actions_test.dart` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the test → PASS. Also run `flutter test test/screens/onboarding_screen_test.dart test/providers/source_api_key_test.dart` → PASS.
- [ ] **Step 5:** Commit `feat: ServerActions for editing, replacing and signing out of servers`.

### Task 3: Active-source URL everywhere + on-device per source

**Files:**
- Modify:
  - `lib/screens/creators_screen.dart:358,454`
  - `lib/screens/read_screen.dart:34`
  - `lib/screens/arc_common.dart:84`
  - `lib/widgets/series_detail_panel.dart:86`
  - `lib/widgets/stats_history_list.dart:36`
  - `lib/widgets/stats_dashboard.dart:21`
  - `lib/widgets/creator_detail_panel.dart:191`
  - `lib/widgets/sidebar_v2.dart:135`
  - `lib/providers/download_provider.dart` (`onDeviceProvider`)
- Test: `test/providers/on_device_test.dart` (new)

**Interfaces:**
- Replace `ref.watch(serverConfigProvider).serverUrl` with `ref.watch(activeSourceProvider.select((s) => s.baseUrl))`.
- `onDeviceProvider` skips items whose `sourceId != ref.watch(activeSourceIdProvider)`. The select key keeps the sourceId.

- [ ] **Step 1:** Test `onDeviceProvider counts only the active source`. Override `downloadStateProvider` with a stream that has completed items for `a` and `b`, set active `a`, and check that only `a`'s comic ids are counted.
- [ ] **Step 2:** Run it → FAIL.
- [ ] **Step 3:** Make the edits. Then `grep -rn "serverConfigProvider).serverUrl" lib` should show only `settings_screen.dart` (Task 4 removes it).
- [ ] **Step 4:** Run the test plus `flutter analyze lib` → PASS / no new issues.
- [ ] **Step 5:** Commit `fix: covers and on-device counts follow the active server`.

### Task 4: Onboarding form edit/add mode

**Files:**
- Modify: `lib/screens/onboarding_screen.dart`
- Test: `test/screens/onboarding_screen_test.dart`

**Interfaces:**
- Produces: `OnboardingScreen({Key? key, Future<int?> Function(ServerSource)? probe, ServerSource? initial, Future<void> Function(ServerSource found)? onConnected})`.
  - With `onConnected` set: the Scaffold gets an `AppBar` with title `Edit server` (when `initial != null`) or `Add server`. On success it calls `await onConnected(found)` instead of `setServerUrl` + `setDefaultServer`, and it clears `_probing` if still mounted.
  - `initial` prefills the type, URL (`baseUrl`), username and password. A Komga apiKey sets `_useKey`. A Gutter source with `AuthType.basic` sets `_authUrl = initial.baseUrl`, so the login fields show.
  - The first Gutter probe uses the auth of `widget.initial ?? activeSource`.

- [ ] **Step 1:** Tests:
  - `edit mode prefills Komga login`: the URL, username and the `Edit server` title show.
  - `edit mode shows Gutter login fields for a basic-auth source`.
  - `onConnected receives the probed source; default source untouched`: the sources list is unchanged after Connect.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test test/screens/onboarding_screen_test.dart` → PASS (old tests too).
- [ ] **Step 5:** Commit `feat: onboarding form doubles as edit/add server`.

### Task 5: ServersScreen + entry points

**Files:**
- Create: `lib/screens/servers_screen.dart`
- Modify:
  - `lib/screens/settings_screen.dart`: replace the Server URL row with `Servers` (value = active name), pushing `ServersScreen` at `/servers`. Delete `_editServerUrl`.
  - `lib/providers/source_provider.dart`: delete `updateDefaultUrl` once it is unused.
  - `lib/screens/more_screen.dart`: the row label becomes `Servers`, the value is `'${sources.length}'`, and it opens `ServersScreen`. The Server status tile gets `onTap` → `ServersScreen` when `signedOut`.
  - Delete `lib/widgets/source_config_sheet.dart` and its test, and drop its Add from `source_switcher.dart`. If the switcher still compiles without it, keep the file; it is unmounted.
- Test: `test/screens/servers_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 `serverActionsProvider`, Task 4 `OnboardingScreen(initial:, onConnected:)`.
- Produces:
  - `class ServersScreen extends ConsumerWidget`.
  - `Future<bool> confirmLeaveServer(BuildContext context, WidgetRef ref, ServerSource s, {required String title, required String body})`. It shows the confirm dialog (`Cancel` / the action label: `Replace` or `Sign out`). Then it calls `pendingCount`. If the count is > 0 it calls `flushOutbox` and loops on the pending dialog while entries remain. `Try again` flushes again, `Discard and continue` returns true, `Cancel` returns false.

Screen behaviour:
- A `ListView` of sources: title `name`, subtitle `Komga · host` or `Gutter · host`, a check icon on the active one.
- `onTap` → `activeSourceIdProvider.notifier.select(id)`.
- A trailing `PopupMenuButton` with `Edit` and `Sign out`.
- Edit pushes `OnboardingScreen(initial: s, onConnected: (found) async { if (!sameServer(s, found) && !await confirmLeaveServer(... 'Replace ${s.name}?' ...)) return; await actions.save(old: s, found: found); if (ctx.mounted) Navigator.pop(ctx); })`.
- Sign out → `confirmLeaveServer(... 'Sign out of ${s.name}?' ...)` → `actions.signOut(s)`. After signing out of the last server, pop to root (`Navigator.popUntil(first)`), so `app.dart` shows onboarding.
- An `Add server` button at the bottom → `requirePro(context, ref, reason: 'More than one server is part of Pro.')`, then push `OnboardingScreen(onConnected: (f) async { await actions.save(found: f); pop; })`.

- [ ] **Step 1:** Tests. Pump `ServersScreen` with mock prefs holding 1 source, and override `serverActionsProvider` with a `ServerActions` whose `drain` is a fake.
  - `store build without Pro: Add server opens the Pro sheet` (`isStore = true`, `proProvider` false → `find.byType(ProSheet)`).
  - `sign out with pending changes shows the dialog; Cancel keeps the server`: write 2 entries to the queue file, use a fake drain that does nothing, tap Sign out → confirm → expect `2 changes not synced to My Server`, then Cancel → the source is still in the list and the queue file still has 2 entries.
  - `Discard and continue signs out`: the source list now has the blank default.
  - `tap switches the active server`: with 2 sources, tap the second → `activeSourceIdProvider` == its id.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the screen and the entry points.
- [ ] **Step 4:** `flutter test test/screens/servers_screen_test.dart test/screens/more_screen_test.dart` → PASS.
- [ ] **Step 5:** Commit `feat: Servers screen to edit, sign out, add and switch servers`.

### Task 6: Full suite, CLAUDE.md, PR

- [ ] **Step 1:** `flutter analyze` (no new issues), then `flutter test` → all pass. The known flake `download_manager_test "journal enqueue…"` passes when run alone.
- [ ] **Step 2:** Add one Architecture bullet to CLAUDE.md:
  - Servers: Settings/More → `ServersScreen`.
  - A login-only edit keeps the id. A type or address change makes a new id and forgets the old one.
  - Forget deletes the keychain, mirror, covers, cache and downloads, and flushes the outbox first.
- [ ] **Step 3:** Commit, `git push -u origin feat/manage-servers`, and open the PR to main. The PR body has iPad test steps: fix a wrong login, change Komga↔Gutter, sign out with pending offline progress (airplane mode), and Pro add + switch on the personal build.
