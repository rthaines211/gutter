# Phase 0: Name + Public Repos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new app name is reserved, and the app and server each live in a new public GitHub repo that starts from one clean commit, with no personal infrastructure in it, while `make ipad` and the homelab deploy keep working from the new repos.

**Architecture:** First strip personal values out of the private repos' `main` (behind untracked `Makefile.local` / `CLAUDE.local.md`), so the seed is just "tracked files at `origin/main` minus excluded paths". Seed each public repo with `git archive` into a fresh directory, scan it, push it as **private**, cut the homelab over, and only then flip it to public and archive the old repos.

**Tech Stack:** Flutter/Dart (app), Go (server), GNU make, Docker Compose (Colima), `gh` CLI, `gitleaks`.

**Spec:** `docs/superpowers/specs/2026-11-05-app-store-launch-design.md` (sections "Decisions", "Repos & licensing")

## Global Constraints

- Fresh history: each public repo's first commit is the only commit; old private repos stay as the archive.
- App license: **PolyForm Noncommercial 1.0.0**. Server license: **AGPL-3.0**.
- Public repos contain no `<personal-domain>` hostname, no Tailscale IPs (`<tailnet-ip>`, `<tailnet-ip>`), no `<training-mac>`, no push `register_secret` value, no device UDIDs. (The Apple team ID `N5CXCS4RMU` in `project.pbxproj` is not secret and may stay.)
- The personal build's behavior is unchanged: same server URL, same push key, same devices, same `make` targets.
- Never open the live SQLite DB from the host. None of these tasks touch the stack's `data/` folder.
- Going public and archiving are outward-facing: each needs the user's explicit go-ahead in the moment (Task 8).
- The repo isn't `dart format`-clean: don't format whole files you edit.

## Review Focus

1. **Fresh clone with no `Makefile.local`:** `flutter analyze`, `flutter test` and `make -n ipad-release` must still work (no define, no default server). Tested in Task 3.
2. **Existing installs keep their server:** a stored `server_url` pref must win over the (now empty) built-in default, so the user's iPad isn't reset. Tested in Task 3.
3. **Ignored files leaking into a seed** (`config.yaml`, `*.db`, `Makefile.local`): seeds come from `git archive origin/main`, so only tracked files can appear; Tasks 5–6 verify with a forbidden-path check.
4. **Personal strings in docs and comments, not just code:** the seed check greps every file, docs included. Tasks 5–6.
5. **Unpushed or unmerged work lost at cutover:** Task 2 settles every unmerged branch before seeding; Task 7 diffs the new working copy against the old `main`.

---

### Task 1: Pick and reserve the new app name

**This is the user's decision. Bring 3–5 candidates and let them choose.**

**Produces:** `APP_NAME` (display name), `APP_SLUG` (lowercase, hyphens), public repo names `APP_SLUG` and `APP_SLUG-server`. Record them at the top of this plan before Task 5.

- [ ] **Step 1:** Propose candidates. Each must be ≤ 30 characters and descriptive enough for search (the market check says discovery comes from Komga/Kavita client lists, so the name should read as a comic reader).
- [ ] **Step 2:** For each candidate, check that it's absent from Komga's client list (komga.org docs, "iOS" clients) and Kavita's wiki client list, and that an App Store search for it shows no comic or reading app. Use `python3 ~/.claude/skills/niche-scout/sweep.py --limit 10 "<name>"`.
- [ ] **Step 3:** User picks one. The user reserves it in App Store Connect (My Apps → + → New App, bundle id stays `com.ryanhaines.comicReaderApp` for now). Done when ASC accepts the name.
- [ ] **Step 4:** Check `gh repo view rthaines211/<APP_SLUG>` and `rthaines211/<APP_SLUG>-server` both return "not found".

### Task 2: Settle in-flight branches

Seeds are cut from `origin/main`, so anything not merged is left behind.

**Unmerged as of 2026-11-05:**
- App: `feat/bulletproof` (holds the launch spec and this plan), `feat/sleep-settings-move`, `feature/remote-second-screen`, `wip/main-checkout-2026-10-30`.
- Server: `docs/label-modes`, `fix/bookmark-replace` (shelved on purpose; see memory "Bookmarks not hydrated").

- [ ] **Step 1:** For each branch, ask the user: merge to `main`, or leave it in the archive. Merge the chosen ones via PR as usual.
- [ ] **Step 2:** `git fetch origin && git branch -a --no-merged origin/main` in both repos. Expected: only the branches the user chose to leave behind.

### Task 3: App — move personal values out of tracked files (private repo, PR to `main`)

**Files:**
- Modify: `lib/config/server_config.dart:11` (`_defaultServerUrl`)
- Modify: `lib/screens/settings_screen.dart:67` (hint text)
- Modify: `Makefile` (lines 1–15: device IDs, `BUNDLE_ID`, `BACKEND_DIR`, `BACKEND_URL`, `COMPOSE_DIR`, `PUSH_API_KEY`, `DART_DEFINES`)
- Create (untracked): `Makefile.local`, `CLAUDE.local.md`
- Modify: `CLAUDE.md`, `.gitignore`
- Test: `test/config/server_config_test.dart`

**Produces:**
- `ServerConfig.serverUrl` returns `String.fromEnvironment('DEFAULT_SERVER_URL')` when no pref is stored (empty string when undefined).
- `Makefile` does `-include Makefile.local` at the top; every personal variable has an empty or generic default in `Makefile`, and its real value lives in `Makefile.local`. `DART_DEFINES` adds `--dart-define=DEFAULT_SERVER_URL=$(BACKEND_URL)` when `BACKEND_URL` is set, alongside the existing `PUSH_API_KEY` define.

- [ ] **Step 1: Write the failing tests** in `test/config/server_config_test.dart`:

```dart
test('no stored url and no define -> empty default', () async {
  SharedPreferences.setMockInitialValues({});
  final c = ServerConfig(await SharedPreferences.getInstance());
  expect(c.serverUrl, '');
});
test('stored url wins over the built-in default', () async {
  SharedPreferences.setMockInitialValues({'server_url': 'https://my.server'});
  final c = ServerConfig(await SharedPreferences.getInstance());
  expect(c.serverUrl, 'https://my.server');
});
```

- [ ] **Step 2:** `flutter test test/config/server_config_test.dart`. Expected: the first test FAILS (returns the <personal-domain> URL); the second passes.
- [ ] **Step 3:** Change `_defaultServerUrl` to `String.fromEnvironment('DEFAULT_SERVER_URL')`. Change the settings hint to `'https://komga.example.com'`.
- [ ] **Step 4:** `flutter test test/config/server_config_test.dart`. Expected: PASS. Then `grep -rn "fromEnvironment\|serverUrl" lib | grep -v server_config.dart` and check no caller assumes a non-empty URL in a way that crashes at launch (a failed request is fine; first-run setup is Phase 1).
- [ ] **Step 5:** Move the personal values from `Makefile` into `Makefile.local` (exact current values), add `-include Makefile.local` at the top of `Makefile`, and add `Makefile.local` and `CLAUDE.local.md` to `.gitignore`.
- [ ] **Step 6:** Split `CLAUDE.md`: the "Dev / Deploy Topology" section, the `backend-check`/`backend-deploy`/`PUSH_API_KEY` build notes, the backend source path and the LCS reference path move to `CLAUDE.local.md`. `CLAUDE.md` keeps everything generic and says "Personal deploy notes: see CLAUDE.local.md (untracked)."
- [ ] **Step 7: Verify.**
  - `make -n ipad-release` shows both `--dart-define=PUSH_API_KEY=` (non-empty) and `--dart-define=DEFAULT_SERVER_URL=https://<personal-server>`.
  - `mv Makefile.local /tmp/ && make -n ipad-release; mv /tmp/Makefile.local .`. Expected: runs, no defines.
  - `flutter analyze && flutter test`. Expected: same results as `main` (note the known `download_manager_test` flake).
  - `git grep -n -I -E "<personal-domain>|<tailnet-ip>|<tailnet-ip>|<training-mac>|<udid>|<udid>" -- . ':!docs' ':!UI-Overhaul' ':!research_notes' ':!reports'`. Expected: nothing.
- [ ] **Step 8:** Commit, PR, merge. The user runs `make ipad` once and confirms the app still opens on their library (no device builds without asking).

### Task 4: Server — move personal values out of tracked files (private repo, PR to `main`)

**Files:**
- Delete: `deploy.sh`, `Makefile` (its only targets SSH to the M2; the real deploy is `make backend-deploy` in the app's `Makefile.local`)
- Modify: `cmd/pushwatch/main.go:24` (default `-url`)
- Modify: `config.example.yaml:40` (`bundle_id` example)

- [ ] **Step 1:** Change the pushwatch `-url` default to `""`, and exit with a usage error when it's empty. Change the example `bundle_id` to `com.example.reader`.
- [ ] **Step 2:** If pushwatch is run by cron or launchd on this Mac, add the `-url` flag there: `crontab -l; ls ~/Library/LaunchAgents | grep -i push`.
- [ ] **Step 3: Verify.**
  - `go build ./... && go test ./...`. Expected: PASS.
  - `git grep -n -I -E "<personal-domain>|<tailnet-ip>|<tailnet-ip>|<training-mac>" -- . ':!docs'`. Expected: nothing.
- [ ] **Step 4:** Commit, PR, merge.

### Task 5: Seed the public app repo (pushed private)

**Produces:** `~/projects/<APP_SLUG>`, one commit, pushed to `github.com/rthaines211/<APP_SLUG>` as **private**.

- [ ] **Step 1:** `git -C ~/projects/comic_reader_app fetch origin && mkdir ~/projects/<APP_SLUG> && git -C ~/projects/comic_reader_app archive origin/main | tar -x -C ~/projects/<APP_SLUG>`
- [ ] **Step 2:** Delete the excluded paths in the new directory: `UI-Overhaul/ .superpowers/ research_notes/ reports/ docs/` (old plans, handoffs and research are full of personal paths; they stay in the archive).
- [ ] **Step 3:** Recreate `docs/superpowers/specs/` and `docs/superpowers/plans/` holding only the launch spec and this plan, with `<personal-server>` replaced by `<personal-server>`, Tailscale IPs by `<tailnet-ip>`, and `<training-mac>` by `<training-mac>`.
- [ ] **Step 4:** Add `LICENSE` with the PolyForm Noncommercial 1.0.0 text from polyformproject.org, plus a first line `Required Notice: Copyright 2026 Ryan Haines`. Replace `README.md` with a short one: what the app is, that it connects to Komga, how to build (`flutter run`), and a license line. Set the pubspec `description:` to one sentence about the app.
- [ ] **Step 5: Seed check.**
  - `git grep` doesn't work before `git init`, so: `grep -rn -I -E "<personal-domain>|<tailnet-ip>|<tailnet-ip>|<training-mac>|<udid>|<udid>|register_secret: *[0-9a-f]{16}" ~/projects/<APP_SLUG>`. Expected: nothing.
  - `ls ~/projects/<APP_SLUG>/{Makefile.local,CLAUDE.local.md,UI-Overhaul} 2>&1`. Expected: all "No such file".
  - `brew install gitleaks` (once), then `gitleaks dir ~/projects/<APP_SLUG>`. Expected: "no leaks found".
- [ ] **Step 6:** `cd ~/projects/<APP_SLUG> && git init -b main && git add -A && git commit -m "Initial public release"` (with the attribution trailer), then `gh repo create rthaines211/<APP_SLUG> --private --source . --push`.
- [ ] **Step 7:** `cp ~/projects/comic_reader_app/{Makefile.local,CLAUDE.local.md} ~/projects/<APP_SLUG>/`, then `flutter pub get && flutter analyze && flutter test`. Expected: same as Task 3's verification.

### Task 6: Seed the public server repo (pushed private)

**Produces:** `~/projects/<APP_SLUG>-server`, one commit, pushed to `github.com/rthaines211/<APP_SLUG>-server` as **private**.

- [ ] **Step 1:** `git -C ~/projects/comic-reader fetch origin && mkdir ~/projects/<APP_SLUG>-server && git -C ~/projects/comic-reader archive origin/main | tar -x -C ~/projects/<APP_SLUG>-server`
- [ ] **Step 2:** Delete `docs/` (personal paths and hostnames throughout).
- [ ] **Step 3:** Add `LICENSE` (AGPL-3.0 text from gnu.org) and a short `README.md`: what it is, `cp config.example.yaml config.yaml`, `docker build`, and a license line. Leave the Go module path `github.com/ryanhaines/comic-reader` as is: nothing `go get`s it, and renaming touches every import. Phase 3 can rename it.
- [ ] **Step 4: Seed check.** Same `grep` as Task 5 Step 5, plus `find . -name "*.db*" -o -name config.yaml -o -name config.test.yaml -o -name covers -o -name deploy.sh`. Expected: nothing. Then `gitleaks dir .`. Expected: no leaks.
- [ ] **Step 5:** `go build ./... && go test ./...`. Expected: PASS.
- [ ] **Step 6:** `git init -b main`, commit "Initial public release", `gh repo create rthaines211/<APP_SLUG>-server --private --source . --push`.

### Task 7: Cut the homelab and personal build over to the new repos

- [ ] **Step 1:** Compare old and new against the old `main`:
  - `diff -rq --exclude=.git --exclude=docs ~/projects/comic-reader ~/projects/<APP_SLUG>-server | grep -v -E "Only in .*/comic-reader: (comic-reader\.db|localcv|gcd|covers|cache|config\.yaml|config\.test\.yaml|Makefile|deploy\.sh|comic-reader$)"`. Expected: only the Task 6 additions (LICENSE, README).
  - Run the same for the app, excluding the Task 5 removals.
- [ ] **Step 2:** Back up the compose file (`cp docker-compose.yml docker-compose.yml.bak-$(date +%Y%m%d)-pre-public`), then change the `comic-reader` service's `build:` to `~/projects/<APP_SLUG>-server`.
- [ ] **Step 3:** In the new app dir's `Makefile.local`, set `BACKEND_DIR` to the new server path. Then `make backend-deploy`. Expected: the container rebuilds, and `make backend-check` passes (healthz reachable at the NPM URL).
- [ ] **Step 4:** Move Claude Code memory for the new app path: `cp -R ~/.claude/projects/-Users-ryanhaines-projects-comic-reader-app ~/.claude/projects/-Users-ryanhaines-projects-<APP_SLUG with / and _ as ->`, and update the `CLAUDE.local.md` paths.
- [ ] **Step 5:** The user runs `make ipad` from the new app dir and confirms the app opens on their library with push still registering.

### Task 8: Go public and archive the old repos (user confirms each)

- [ ] **Step 1:** Ask the user: "Both new repos pass the seed check and the homelab runs from them. Make them public now?" Only on a yes: `gh repo edit rthaines211/<APP_SLUG> --visibility public --accept-visibility-change-consequences`, same for `-server`.
- [ ] **Step 2:** Ask the user before archiving: `gh repo archive rthaines211/comic_reader_app` and `gh repo archive rthaines211/comic-reader`. Rename the old local dirs to `~/projects/_archive/comic_reader_app` and `~/projects/_archive/comic-reader`, so nothing builds from them by accident.
- [ ] **Step 3:** Update the spec's "Repos & licensing" with the final repo URLs, and update memory (the new paths and that the old repos are archived).
