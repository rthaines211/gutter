# Manage servers in the app — design

Last feature before App Store submission (launch spec, "Shape of the work",
project 1).

## Why

The only way to sign in is first-launch onboarding. Settings → Server URL
changes the address in place but not the type or the login, so a wrong
login can only be fixed by deleting the app. App Review (and every store
user who mistypes a password) hits this.

## Goals

- **Free:** edit the one server (type, address, login) with the onboarding
  form; sign out.
- **Pro:** add more servers and switch between them.
- Queued offline progress is never dropped without the user saying so.

## Non-goals

- OPDS. The old `SourceConfigSheet` (Komga/OPDS, no Gutter) is dropped; Add
  uses the onboarding form (Gutter/Komga only).
- A library-header switcher. `SourceSwitcher` stays unmounted.
- Pro-downgrade handling (more servers than Free allows). Pro is a
  non-consumable; ignore.
- Per-source reader settings cache, push unregister, `device_id` per server.

## Decisions (user's)

| Change | Same source id? | Local data |
|---|---|---|
| Login only (same type **and** same address) | Yes, edit in place | All kept. Queued 401 entries drain with the new login. |
| Type or address changed | No: new source id, full sync | Old source goes through **forget** (below). |
| Sign out | — | Old source goes through **forget**. Last server → onboarding. |

**Forget** a source = delete everything on this device for it:
keychain `source_cred_<id>_*`, prefs entry, `<docs>/mirror_<id>.sqlite`
(+ `-wal`, `-shm`), `<docs>/covers/<id>/`, `<docs>/cache/<id>/` (outbox
`sync_queue.json`, Komga `sessions.json`, cache layer), downloads
(`<docs>/downloads/<id>/` and its journal entries, in-flight ones cancelled).

**Outbox before forget ("sync first, then ask"):** if the source's
`SyncQueue` has entries, drain it with that source's own client
(`SyncQueueDrainer(queue: SyncQueue(<docs>/cache/<id>/sync_queue.json),
client: clientFor(source))` — works for inactive sources too). If entries
remain: dialog "N changes not synced to <name>" → **Try again** /
**Discard and continue** / **Cancel**.

**UI:** Settings → "Server URL" row becomes **Servers**, which pushes a
`ServersScreen`:
- One row per server: name, type · host, ✓ on the active one.
- Tap a row → make it active (only matters with >1).
- Row ⋯ menu → **Edit** (onboarding form, prefilled) / **Sign out**.
- **Add server** button → `requirePro(...)`, then the onboarding form, empty.
- More's "Sources · 1 connected" row → "Servers · N" and opens
  `ServersScreen`; the "Signed out" status tile also opens it.

## How (builder's calls, stated)

**Form reuse.** `OnboardingScreen` gains `initial` (prefill: type, URL,
username, password/key; Gutter-with-login shows the login fields up front)
and `onConnected(ServerSource found)`. With `onConnected` set it shows an app
bar with back and title "Edit server" / "Add server". First-launch mode is
unchanged (`setDefaultServer`). The first Gutter probe reuses the auth of
`initial ?? activeSource`.

**Committing a save** (after the probe succeeds — nothing is deleted before
the new server answers):
- Edit, same type+URL → `edit(id, found with old id/name/isDefault)`.
- Edit, different → outbox check + confirm "Replace <old>? Its library and
  downloads on this iPad are removed." → `add(found with new id, old
  isDefault)`, select it, then forget the old one.
- Add → `add(found with new id, isDefault: false)`, select it.

**Sign out:** confirm "Sign out of <name>? Its library, downloads and
reading stats on this iPad are removed." → outbox check → if active and
another server exists, select another; if it is the last, add a blank
default source (**fresh id**, empty URL — `app.dart` shows onboarding) and
select it → forget.

**Order matters:** always select the new active source *before* deleting
files, so `mirrorDbProvider` closes the old DB. A fresh id for the blank
source avoids reopening `mirror_default.sqlite` while deleting it.

**Global `server_url` pref.** Eight widgets build cover URLs from
`serverConfigProvider.serverUrl` (and `sidebar_v2` shows its host), which
does not follow the active source and does not rebuild. Switch them to
`activeSourceProvider.baseUrl`. The pref stays only as the seed for the
default source; `_editServerUrl` and `updateDefaultUrl` go away.

**Small fixes needed for multi-server correctness:**
- `onDeviceProvider` counts only the active source's downloads (comic ids
  can collide across servers).
- Personal build: `builtInApiKey` seeds only a Gutter default source with
  `AuthType.none`, so it never overwrites a basic-auth or Komga login.

**New code (expected shape):**
- `DownloadManager.deleteSource(sourceId)`.
- `deleteSourceFiles(docsDir, id)` (mirror files, covers, cache).
- A small set of server actions (save / sign out / flush outbox) used by
  `ServersScreen`.

**More builder calls (from the review):**
- `isDefault` always sits on exactly one source. If the default is forgotten
  and others remain, the server that becomes active takes the flag.
- Editing an *inactive* server to a different type/address does not switch
  to it; the new source is selected only if the old one was active.
- The personal-only Settings → API Key row stays as is (push key).
- `ServersScreen` is reached only from Settings/More, so no reader is open
  while a source is forgotten; no extra guard.
- Offline sign-out still tries the drain (fails fast) and then shows the
  "N changes not synced" dialog; Try again works once back online.

## Tests

Unit: same-server vs replace id handling; sign-out of last server gives a
blank source with a new id; `deleteSourceFiles` on a temp dir;
`DownloadManager.deleteSource`; outbox flush leaves count. Widget:
`ServersScreen` Add server opens the Pro sheet in a non-Pro store build;
sign out with pending changes shows the dialog and Cancel keeps everything;
onboarding edit mode prefills. Full `flutter test` passes.
