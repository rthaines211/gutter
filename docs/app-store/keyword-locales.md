# Extra keyword fields

The US storefront also indexes the keyword fields of some other locales
(Spanish (Mexico), French, Portuguese (Brazil) and more). Source: AppTweak,
Nov 2025; Apple lists the locales but does not document the indexing, so the
effect is not certain. Words do not combine across locales, only inside one.

To use a field, add that locale in App Store Connect with the same name,
subtitle and description as English, and paste its keywords. Every word must
be true for the build.

| Locale | Keywords | Length |
|---|---|---|
| English (U.S.) | see `fastlane/metadata/en-US/keywords.txt` | 98 |
| Spanish (Mexico) | `selfhosted,nas,homelab,library,collection,digital,stats,streak,queue,bookmark,comics,lector,comic` | 97 |
| French | `manhwa,manhua,webtoon,vertical,scroll,bd,bande,dessinee,lecteur,volume,chapter,series,rtl,japanese` | 98 |

Notes:
- Spanish (Mexico) carries the self-hosting words that did not fit in
  English, plus "lector comic(s)" for Spanish speakers.
- French carries the manga and vertical-scroll words. "webtoon" stands on
  vertical scroll mode; remove it if that mode goes.
- Not used: `opds` (the app cannot add an OPDS server), `epub`, `pdf`,
  competitor names and publisher names.
- English (UK/Australia/Canada) fields replace the U.S. field in those
  stores, so they would need the full U.S. set; not added.
