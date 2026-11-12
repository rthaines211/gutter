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
| Spanish (Mexico) | `selfhosted,nas,homelab,library,collection,opds,stats,streak,queue,bookmark,comics,lector,comic` | 94 |
| French | `manhwa,manhua,webtoon,vertical,scroll,bd,bande,dessinee,lecteur,volume,chapter,series,rtl,opds` | 94 |

Notes:
- Spanish (Mexico) carries the self-hosting words that did not fit in
  English, plus "lector comic(s)" for Spanish speakers.
- French carries the manga and vertical-scroll words. "webtoon" stands on
  vertical scroll mode; remove it if that mode goes.
- Not used: `epub`, `pdf`,
  competitor names and publisher names.
- English (UK/Australia/Canada) fields replace the U.S. field in those
  stores, so they would need the full U.S. set; not added.

## Translated listings

`fastlane/metadata/` now also holds `fr-FR`, `es-MX`, `pt-BR` and `de-DE`
with a translated subtitle, promotional text, description and release notes.
The name and the URLs are the same as English.

**The translations were machine-written. A native speaker must check each
locale before it goes into App Store Connect.** Nothing here is uploaded yet.

| Locale | Folder | Keywords | Length |
|---|---|---|---|
| French | `fr-FR` | `manhwa,manhua,webtoon,vertical,scroll,bd,bande,dessinee,lecteur,volume,chapter,series,rtl,opds` | 94 |
| Spanish (Mexico) | `es-MX` | `selfhosted,nas,homelab,library,collection,opds,stats,streak,queue,bookmark,comics,lector,comic` | 94 |
| Portuguese (Brazil) | `pt-BR` | `manga,quadrinhos,gibi,comics,ler,cbz,cbr,quadro,zoom,offline,baixar,sincronizar,servidor,nas,opds` | 97 |
| German | `de-DE` | `manga,lesen,leser,cbz,cbr,graphic,novel,panel,zoom,offline,download,sync,server,nas,webtoon,opds` | 96 |

Notes:
- French and Spanish (Mexico) keep the keyword strings from the table above
  without change, because the US storefront also indexes them. Their
  subtitles ("Vos comics sur Komga et Kavita", "Historietas en Komga y
  Kavita") do not use "lecteur", "bd", "lector" or "cómics", so no keyword
  repeats the subtitle.
- Portuguese (Brazil) and German have keywords in the local language. The
  subtitles are "Leitor de HQ: Komga e Kavita" and "Comic-Reader: Komga &
  Kavita", so `leitor`, `hq`, `comic` and `reader` are not in the fields.
- Screen labels that the app shows in English (Panels, Aa, Up Next, Read)
  stay in English in the release notes: the app has no translations.
- The same limits apply as for English: no `epub`, `pdf`, competitor
  names or publisher names. "webtoon" stands on vertical scroll mode.
- `opds` is in every translated keyword field (1.0.3 adds OPDS servers).
  English has it in the subtitle ("CBZ, Komga, Kavita & OPDS"), so it is
  not in the English keywords.
