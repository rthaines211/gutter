# OPDS client listings (after OPDS ships)

Gate: the OPDS source is merged, in a released build, and tested against each
server below on a device. Then add `opds` to the keyword field and update
the site ("cannot add other OPDS servers" lines on komga/kavita/support and the
comparison pages).

| # | List | Where | Test first against | Notes |
|---|------|-------|--------------------|-------|
| 1 | Komga OPDS guide | PR to gotson/komga-website `website/docs/guides/opds.md` | demo Komga `/opds/v1.2/catalog` | gotson merged the Gutter client guide (#251) before; same reviewer |
| 2 | Kavita OPDS wiki | PR to Kareadita/Wiki-Nextra `content/guides/features/opds.mdx` | demo Kavita `/api/opds/{apiKey}` | #154 (dedicated apps) still open: link it |
| 3 | Stump "Tested Clients" | PR to stumpapp/stump `content/docs/guides/features/opds.mdx` | Stump in Docker (new, temporary) | needs a local Stump; OPDS v1.2 + PSE |
| 4 | Codex README "OPDS Clients" | PR to ajslater/codex | Codex in Docker (temporary) | Codex has OPDS v1 and v2; test v1 |
| 5 | LANraragi external readers | PR to Difegue/LANraragi `tools/Documentation/advanced-usage/external-readers.md` | LANraragi in Docker | optional, manga-heavy audience |
| 6 | MobileRead wiki OPDS page | wiki edit | — | low effort, low reach |

Per list:
1. Run the server in Docker on the `apps` network with 2–3 public-domain
   books from `media-servers/komga-demo/comics` (never copyrighted files).
2. On the iPad (store build): add server → library loads → open a book →
   pages stream (PSE) → progress kept locally → offline browse.
3. Note what does not work (no PSE → download fallback, auth type).
4. Open the PR with one factual line in the list's own format: name,
   platforms (iOS, iPadOS), price model (free; one-time Pro), App Store link,
   and "tested with <server> <version>". No marketing text.
5. Record the PR URL in memory; never open a PR without the user's yes.

Effort: ~0.5 day per server incl. Docker setup and the device check;
~3 days for all six.
