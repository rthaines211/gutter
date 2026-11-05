# App Review Notes (paste into App Store Connect → App Review Information)

Fill the two placeholders in App Store Connect only. Never commit them.

---

Gutter is a comic reader for people who run their own comic server. It
has no content of its own and no accounts with us. On first launch it asks
for the address of the user's server and their login.

**Demo server** (public-domain comics, read-only reviewer account):

- Server type: Komga (selected by default)
- Address: `<demo-url>`
- Username / password: in the Sign-In Information fields above.

Steps: open the app → Komga → enter the address, username and password →
Connect. The library loads; tap any series, then an issue to read. Swipe
or tap the page edges to turn pages; swipe up for the reader controls.

**In-app purchase.** "Gutter Pro" is a one-time, non-consumable unlock
($12.99). It adds offline downloads, guided panel and spread zoom, more
than one server, and reading stats. To see it: tap the download icon on
any issue, or Settings → Gutter Pro. Restore Purchases is on the same
sheet. Reading, streaming and progress sync are free.

**Volume buttons (2.5.9).** Turning pages with the volume buttons is off by
default. Users can opt in under the reader's Aa → More. When on, the
buttons turn pages only while a comic is open.

**Network security.** The app connects only to servers the user types in,
which are usually on their home network or behind their own reverse
proxy, often over plain HTTP. That is why App Transport Security allows
arbitrary loads. The app talks to no other servers.

**Privacy.** No data is collected. No analytics, ads or tracking. Settings,
progress and downloads stay on the device and the user's own server.
