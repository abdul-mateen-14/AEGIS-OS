#!/usr/bin/env python3
"""W14 — build the aegis-mark Plymouth theme assets.

- watermark.png: the Aegis mark keyed out of the dark source (luminance →
  alpha, recoloured paper-white), scaled to a 160 px tall boot watermark.
- track.png: 240x2 white line at 25% alpha (the old asset was fully
  transparent, so the track never painted).
- fill.png: the accent #3E8BFF hairline, reused from theme/plymouth.

Sources stay in git under theme/plymouth-mark/; sync-includes.sh copies the
whole directory into the includes tree.
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "theme/plymouth/aegis-mark.png")
FILL_SRC = os.path.join(ROOT, "theme/plymouth/fill.png")
OUT = os.path.join(ROOT, "theme/plymouth-mark")

os.makedirs(OUT, exist_ok=True)

# ── watermark: luminance → alpha, white ink, 160 px tall ─────────────
src = Image.open(SRC).convert("L")
scale = 160 / src.height
mark = src.resize((round(src.width * scale), 160), Image.LANCZOS)
water = Image.new("RGBA", mark.size, (0, 0, 0, 0))
wp = water.load()
mp = mark.load()
for y in range(mark.height):
    for x in range(mark.width):
        lum = mp[x, y]
        # key out the near-black canvas; paper-white mark with soft edges
        a = 0 if lum < 24 else min(255, int((lum - 24) * 255 / (210 - 24)))
        wp[x, y] = (242, 244, 248, a)
water.save(os.path.join(OUT, "watermark.png"))
print("watermark.png", water.size)

# ── track: 240x2, white at 25% alpha ──────────────────────────────────
track = Image.new("RGBA", (240, 2), (242, 244, 248, 64))
track.save(os.path.join(OUT, "track.png"))
print("track.png", track.size)

# ── fill: accent hairline, reused verbatim ────────────────────────────
Image.open(FILL_SRC).convert("RGBA").save(os.path.join(OUT, "fill.png"))
print("fill.png copied")
