# Demo Komga for App Review

App Review needs a server it can reach for the whole review, with
public-domain comics and a reviewer login. This is a small Komga on the
homelab behind the reverse proxy (HTTPS).

## Content

Public-domain Golden Age comics from Digital Comic Museum
(`digitalcomicmuseum.com`, all files there are public domain). About 5–10
series is plenty. Put them in their own folder; the demo library must not
point at the real collection.

```
<demo-root>/
  config/            # Komga's database
  comics/
    Phantom Lady/Phantom Lady 013.cbz
    ...
```

## Compose service

Add to the media-servers stack (adjust paths and the network to match it):

```yaml
  komga-demo:
    image: gotson/komga:1.30.0
    container_name: komga-demo
    restart: unless-stopped
    user: "1000:1000"
    environment:
      - TZ=America/New_York
    volumes:
      - <demo-root>/config:/config
      - <demo-root>/comics:/data:ro
    # No host port: the reverse proxy reaches it on the stack network (:25600).
```

Then in the reverse proxy: a new HTTPS host for the demo, forwarded to
`komga-demo:25600`.

## Setup

1. First visit: create the admin account (keep it private).
2. Add a library pointing at `/data`, then let the scan finish.
3. Server settings → Users → add `reviewer` with a long random password,
   access to the demo library only, no admin rights. Make it read-only by
   leaving download/upload rights off apart from "page streaming" and
   "file download" (needed for the Pro downloads feature).
4. Check from a phone on cellular: the app's onboarding connects with the
   reviewer login and a comic opens.
5. Put the address in App Store Connect → App Review → Notes and the
   login in Sign-In Information. Keep it running until the review is
   approved, and again for each update's review.
