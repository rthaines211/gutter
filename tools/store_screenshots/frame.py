#!/usr/bin/env python3
"""Frame raw app captures as App Store screenshots with a localized caption.

Usage:
  python3 tools/store_screenshots/frame.py --device ipad --shot read \
      --capture raw/read.png --out out/ [--locales en-US,fr-FR] [--clear-status-bar 44]

Writes out/<locale>/<device>-<shot>.png for each locale in captions.json.
Sizes: ipad = 13" (2064x2752), iphone = 6.9" (1320x2868). Captures should be
native screenshots from that device or simulator; smaller ones are scaled up
and look soft. Style matches the set already in App Store Connect: caption
yellow background, Bangers title, device frame bleeding off the bottom.
"""
import argparse, json, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
YELLOW = (255, 210, 63)   # --caption, the app's caption-box yellow
INK = (27, 23, 32)        # --ink
BEZEL = (17, 15, 20)

DEVICES = {
    # canvas, screen width, bezel, screen corner radius, caption block height
    "ipad":   dict(size=(2064, 2752), screen_w=1640, bezel=34, radius=60, top=150, title=150, sub=62),
    "iphone": dict(size=(1320, 2868), screen_w=1060, bezel=30, radius=120, top=150, title=120, sub=50),
}
BODY_FONTS = [
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/System/Library/Fonts/SFNS.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
]


def body_font(size):
    for p in BODY_FONTS:
        if os.path.exists(p):
            f = ImageFont.truetype(p, size)
            if p.endswith("SFNS.ttf"):
                try:
                    f.set_variation_by_name("Bold")
                except Exception:
                    pass
            return f
    return ImageFont.load_default(size)


def fit(draw, text, font_path, size, max_w, loader=None):
    while size > 20:
        f = loader(size) if loader else ImageFont.truetype(font_path, size)
        if draw.textlength(text, font=f) <= max_w:
            return f
        size -= 4
    return f


def clear_status_bar(img, rows):
    """Paint the status bar (time, VPN, battery) with the row just below it."""
    if rows <= 0:
        return img
    img = img.copy()
    strip = img.crop((0, rows, img.width, rows + 1)).resize((img.width, rows))
    img.paste(strip, (0, 0))
    return img


def frame(device, capture, title, sub):
    d = DEVICES[device]
    W, H = d["size"]
    canvas = Image.new("RGB", (W, H), YELLOW)
    draw = ImageDraw.Draw(canvas)
    margin = int(W * 0.06)
    bangers = os.path.join(REPO, "assets/fonts/Bangers-Regular.ttf")
    tf = fit(draw, title.upper(), bangers, d["title"], W - 2 * margin)
    sf = fit(draw, sub, None, d["sub"], W - 2 * margin, loader=body_font)
    # Baseline anchors, so accents (É, Ñ) don't push a line down.
    y = d["top"] + d["title"]
    draw.text((W / 2, y), title.upper(), font=tf, fill=INK, anchor="ms")
    y += 30 + d["sub"]
    draw.text((W / 2, y), sub, font=sf, fill=INK, anchor="ms")
    y += 90

    sw = d["screen_w"]
    shot = capture.convert("RGB")
    sh = round(sw * shot.height / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    b = d["bezel"]
    x0 = (W - sw) // 2 - b
    dev = Image.new("RGBA", (sw + 2 * b, sh + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(dev).rounded_rectangle((0, 0, dev.width - 1, dev.height - 1), radius=d["radius"] + b, fill=BEZEL)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=d["radius"], fill=255)
    dev.paste(shot, (b, b), mask)
    canvas.paste(dev, (x0, y), dev)
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", choices=DEVICES, required=True)
    ap.add_argument("--shot", required=True, help="key in captions.json")
    ap.add_argument("--capture", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--locales", default="")
    ap.add_argument("--clear-status-bar", type=int, default=0, help="rows to blank at the top of the capture")
    a = ap.parse_args()
    caps = json.load(open(os.path.join(HERE, "captions.json"), encoding="utf-8"))[a.shot]
    locales = a.locales.split(",") if a.locales else list(caps)
    img = clear_status_bar(Image.open(a.capture), a.clear_status_bar)
    for loc in locales:
        c = caps[loc]
        os.makedirs(os.path.join(a.out, loc), exist_ok=True)
        path = os.path.join(a.out, loc, f"{a.device}-{a.shot}.png")
        frame(a.device, img, c["title"], c["sub"]).save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
