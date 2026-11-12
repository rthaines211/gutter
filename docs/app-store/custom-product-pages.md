# Custom product pages

App Store Connect → Gutter → Custom Product Pages. A page can change the
screenshots and promotional text only. Keywords can be assigned only from
the live keyword field (`fastlane/metadata/en-US/keywords.txt`, 1.0.3):

`manga,book,cbr,import,local,graphic,novel,panel,guided,zoom,offline,download,sync,self,hosted,server`

"komga" and "kavita" are in the name/subtitle ("CBZ, Komga, Kavita & OPDS"),
not in the keyword field, so they cannot be assigned. Do not reuse one
keyword on two pages.

## Komga (draft exists, unsubmitted)

- Reference name: `Komga`
- Promotional text (≤170):
  `Your Komga library on iPad and iPhone. Progress syncs both ways, page by page, for free. Browse offline, download issues, step through panels. No subscription.`
- Screenshots: same as the default page (Read tab first, then Library).
- Keywords: `self`, `hosted`, `server`, `sync`
- Link it from getgutter.app/komga and the Komga docs guide (`?ppid=<id>`).

## Kavita (new)

- Reference name: `Kavita`
- Promotional text (≤170):
  `Your Kavita 0.9+ library on iPad and iPhone. Sign in once; progress syncs both ways for free. Browse offline, download issues, step through panels. One-time Pro.`
- Screenshots: same as default.
- Keywords: `offline`, `download`
- Link it from getgutter.app/kavita and the Kavita wiki entry (`?ppid=<id>`).

## Optional: Your files (no server)

- Promotional text: `No server needed. Import CBZ files from the Files app and read them free. Guided panel zoom, reading stats, iPad-first. No account, no ads.`
- Keywords: `import`, `local`, `cbr`

## Notes

- Each page goes through App Review (submit with or after a version).
- After approval, change the site links to the `?ppid=` URLs.
- Check the 170-char limit in ASC; the counter there is the authority.
