# Listing refresh (Nov 2026)

Drafted 2026-11-26. Nothing here has been uploaded or saved in App Store
Connect. The copy is in `fastlane/metadata/<locale>/`; the screenshot
captions and framing script are in `tools/store_screenshots/`.

## What App Store Connect shows today (read 2026-11-26, 10 PM ET)

- 1.0.6 is Waiting for Review. Its keywords are Option A
  (`cbz,cbr,manga,webtoon,book,graphic,novel,library,panel,guided,offline,superhero,self,hosted,server`)
  and its subtitle is Option A (`Komga, Kavita & OPDS Comics`). The repo now
  matches.
- Promotional text (English): the Black Friday line, "Black Friday: Gutter Pro
  drops to $4.99 from Nov 27 to 30. Read your Komga, Kavita and OPDS library
  anywhere." Leave it until Nov 30; a Dec 1 reminder is set to change it.
- Localizations: English (U.S.), French, Spanish (Mexico). No Portuguese
  (Brazil) or German yet. French and Spanish have no screenshots of their own,
  so they show the English ones.
- Screenshots: iPhone (6.9") has 5: Panel by panel, Your whole library, Pick
  up where you left off, Big sharp pages, Read offline. iPad 13" has 3: Made
  for iPad, Pick up where you left off, Your whole library. iPad has 7 empty
  slots and no guided zoom shot.
- The public page lists Pro at $7.99 today (sale $4.99 Nov 27–30, $12.99 from
  Dec 1), 0 ratings, age rating 18+ (13+ arrives with 1.0.6).

## What the old copy left out

Added in 1.0.3–1.0.6 and now in the description in all five languages:

- Try a sample comic on the first screen (no files, no server).
- One-tap read checks: tap the circle on any issue, with Undo.
- iPad: tap the title while reading to see the series in a side panel.
- The first comic opens with guided zoom on, free for that issue.
- Stats share card (numbers only, never what you read).
- "Gutter does not include comics" was no longer true with the bundled sample;
  it now says "Apart from the free sample".

The price is not in the description, so the Dec 1 rise needs no edit there.

## Promotional text

Promotional text changes without review. The drafts in
`promotional_text.txt` are for after the sale (from Dec 1):

| Locale | Text | Chars |
|---|---|---|
| en-US | Try Gutter free with a sample comic, no server needed. Or bring your Komga, Kavita or OPDS library. Pro is one purchase, never a subscription: guided zoom and downloads. | 169 |
| fr-FR | Essayez Gutter gratuitement avec un comic d'exemple, sans serveur. Ou connectez votre bibliothèque Komga, Kavita ou OPDS. Pro, un seul achat sans abonnement : zoom guidé. | 170 |
| es-MX | Prueba Gutter gratis con un cómic de ejemplo, sin servidor. O conecta tu biblioteca Komga, Kavita u OPDS. Pro es una sola compra, sin suscripción: zoom guiado. | 161 |
| pt-BR | Experimente o Gutter grátis com um quadrinho de exemplo, sem servidor. Ou conecte sua biblioteca Komga, Kavita ou OPDS. Pro: compra única, sem assinatura. Zoom guiado. | 169 |
| de-DE | Teste Gutter kostenlos mit einem Beispiel-Comic, ganz ohne Server. Oder verbinde deine Komga-, Kavita- oder OPDS-Bibliothek. Pro: Einmalkauf, kein Abo. Geführter Zoom. | 168 |

Black Friday lines for French and Spanish (Mexico), to use Nov 27–30 if
wanted. No dollar amount, because those storefronts show their own currency:

- fr-FR: `Black Friday : Gutter Pro à prix réduit du 27 au 30 novembre. Lisez votre bibliothèque Komga, Kavita et OPDS partout.`
- es-MX: `Black Friday: Gutter Pro con descuento del 27 al 30 de noviembre. Lee tu biblioteca de Komga, Kavita y OPDS donde sea.`

## Keywords

- en-US: Option A, as set on 1.0.6. Unchanged.
- fr-FR and es-MX (the US store also indexes these, so a word repeated from
  the English field or subtitle is wasted):
  - fr-FR: `manhwa,manhua,vertical,scroll,bd,bande,dessinee,lecteur,volume,chapter,series,rtl,zoom,spread` (93).
    Dropped `webtoon` (now in English) and `opds` (now in the subtitle); added
    `zoom` and `spread`.
  - es-MX: `selfhosted,nas,homelab,collection,stats,streak,queue,bookmark,lector,tracker,unread,sync,vinetas` (96).
    Dropped `library` (English), `opds` and `comics`/`comic` (subtitle and
    name); added `tracker`, `unread`, `sync`, `vinetas`.
- pt-BR and de-DE: unchanged (local-language words, not indexed in the US).

## Subtitles

Unchanged in fr-FR, es-MX, pt-BR and de-DE. English is Option A.

## Screenshots

Captures must be the store build on the demo Komga or the sample comic, with
public-domain or CC BY comics only. Native sizes: iPad 13" 2064×2752
(portrait), iPhone 6.9" 1320×2868. Hide the status bar clutter (a simulator
with `xcrun simctl status_bar <id> override --time 9:41 --batteryLevel 100`
is easiest).

Frame each capture with:

```
python3 tools/store_screenshots/frame.py --device ipad --shot <shot> --capture <file> --out <dir>
```

It writes one PNG per locale with the caption from `captions.json`, in the
same yellow-caption style as the current set.

### Order and captions (English; other languages are in captions.json)

| # | shot key | Caption | iPad | iPhone | Capture |
|---|---|---|---|---|---|
| 1 | panel | Panel by panel / Guided zoom walks you through every page | new capture | have | Reader on a guided-zoom step |
| 2 | read | Pick up where you left off / Progress syncs with Komga and Kavita | made | have | Read tab |
| 3 | library | Your whole library / Komga, Kavita, OPDS or your own CBZ files | made | have | Library grid |
| 4 | series_panel | The series, right there / Tap the title to see every issue beside the page | new capture | — (iPad only) | Reader with the series panel open |
| 5 | read_checks | One tap: read / Tap the circle on any issue. Undo is right there | new capture | new capture | Series detail, one issue just checked, Undo showing |
| 6 | sample | Reading in seconds / Try a sample comic. No server, no account | new capture | new capture | Onboarding with Try a sample comic, or Pepper&Carrot open |
| 7 | page (iPad) / pages (iPhone) | Made for iPad / Big, sharp pages | made | have | Full-screen page |
| 8 | offline | Read offline / Download issues and read anywhere | new capture | have | Downloads |
| 9 | stats | Your reading, in numbers / Streaks and pages per day, with a card to share | new capture | new capture | Stats screen, or the share card |
| 10 | pro | One purchase. No subscription. / Gutter Pro covers every future version | optional | optional | Pro sheet (price shows; capture after Dec 1 so it isn't the sale price) |

"made" = framed from the existing site captures in all five languages, in
the project files folder `gutter/store-screenshots/ipad-from-existing-captures/`.
Those captures are 1200×1600, so they are scaled up and slightly soft;
re-frame from native captures before upload if you have them. They match the
three iPad shots already in App Store Connect, so for English they only add
value as sharper replacements; for French and Spanish they give those
listings localized captions.

## When it can go live

- Promotional text: any time, no review. English waits until the sale ends.
- Description, keywords, screenshots: version metadata, so they go in with
  1.0.7 (1.0.6 is in review and those fields are locked).
- Portuguese (Brazil) and German: add the localizations on 1.0.7. The
  translations are machine-written; have a native speaker check them first.
