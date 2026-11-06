# Launch Post Drafts

Plain and honest. No hype, no emoji. Replace `TODO_APP_STORE_LINK` before
posting. Check each community's self-promotion rules first (r/selfhosted
wants the author to say they made it; r/comicbooks may require a mod OK or a
specific day for app posts).

---

## r/selfhosted

**Title:** I made Gutter, an iPad and iPhone comic reader for Komga (and my own open-source comic server)

I read comics from a Komga server at home and wanted a reader on the iPad
that felt like a native app, so I built one. It's on the App Store now.

What it does:

- Connects to Komga with a username and password or an API key. It can
  also connect to Gutter server, a small Go/SQLite comic server I wrote
  (open source: https://github.com/rthaines211/gutter-server).
- Page or vertical scroll mode, left-to-right or right-to-left, fit to
  screen, width or height.
- Progress syncs both ways with the server. The library is kept on the
  device, so it still browses when the server is out of reach.
- Reading queues, search, filters and sorting.

Pricing: free to read, stream and sync. A one-time Pro unlock ($12.99)
adds offline downloads, guided zoom (panel by panel, and two-page spreads
half by half), more than one server, and reading stats. It is not a
subscription, and I won't charge for version upgrades.

Privacy: no accounts, analytics, ads or tracking. The app talks only to the
servers you add.

Not supported yet: Kavita has no dedicated adapter. iOS and iPadOS only.

App Store: TODO_APP_STORE_LINK
Issues and feedback: https://github.com/rthaines211/gutter/issues

Happy to answer questions.

---

## r/comicbooks

**Title:** I built a comic reader app for people who keep their own digital collection

If you keep your comics as CBZ/CBR files on a home server (Komga, or my own
Gutter server), I made an iPad and iPhone app to read them: Gutter.

It does not sell or include comics. It reads the ones you already have.

Things I cared about as a reader:

- Guided zoom that steps through a page panel by panel, and through
  two-page spreads one half at a time (part of the one-time Pro unlock)
- Right-to-left mode for manga, and a vertical scroll mode
- Picks up where you left off on any device, because progress syncs with
  your server
- Offline downloads for flights and commutes (Pro)

It is free to read. Pro is a single $12.99 purchase, not a subscription.
No ads, no tracking.

App Store: TODO_APP_STORE_LINK

---

## Komga Discord (#showcase or the channel mods point to)

Hi all. I've released Gutter, a free iPad and iPhone reader for Komga.

- Sign in with username and password or an API key
- Read progress syncs both ways through Komga's read-progress API
- Page and scroll modes, LTR and RTL, fit to screen, width or height
- Library is mirrored on the device, so it still browses when Komga is
  out of reach
- On-device panel detection for panel-by-panel zoom, and spread zoom

Free to read and sync. A one-time $12.99 Pro unlock adds offline
downloads, guided zoom, more than one server and reading stats. No
subscription, no analytics.

App Store: TODO_APP_STORE_LINK
Bugs and requests: https://github.com/rthaines211/gutter/issues

If anything acts up against your Komga version, please open an issue with
the Komga version number.

---

## Request: listing in Komga's client docs

Komga's docs list third-party clients. Open a pull request on the docs repo
(or an issue if they prefer) with:

> **Title:** Add Gutter (iOS/iPadOS) to the list of clients
>
> Gutter is an iPad and iPhone comic reader that connects to Komga with a
> username and password or an API key. It reads books, and syncs read
> progress both ways through the Komga API.
>
> - Platform: iOS / iPadOS
> - Price: free, with an optional one-time in-app purchase
> - App Store: TODO_APP_STORE_LINK
> - Source: https://github.com/rthaines211/gutter
>
> Happy to change the wording or format to match the page.
