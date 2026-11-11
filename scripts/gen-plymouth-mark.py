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
from PIL import Image, ImageDraw

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

# ── the two-step plugin's REQUIRED images (v0.6.24 post-mortem) ──────
# The v0.6.24 serial trace caught the real splash failure: two-step
# aborts at "loading lock image" when lock.png is missing and the whole
# theme falls back to the details text splash — that is where the boot
# lines on screen came from. lock.png is fatal on load failure; entry,
# bullet and box are the LUKS/password prompt assets (invisible on a
# normal boot, required for a clean unlock prompt on installed systems).
# Everything is drawn on the Tokens palette: paper #F2F4F8 ink on
# ink #08090C glass.
S = 4  # supersample


def rounded(draw, box, radius, **kw):
    draw.rounded_rectangle([box[0] * S, box[1] * S, box[2] * S, box[3] * S],
                           radius=radius * S, **kw)


PAPER = (242, 244, 248, 255)
INK = (16, 18, 22, 220)
INK_BORDER = (242, 244, 248, 200)

# lock.png — the padlock the two-step prompt paints next to password
# entries. 44 px on a 64 px canvas (the plugin scales by theme height).
lock = Image.new("RGBA", (64 * S, 64 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(lock)
# shackle — arc from the body top
d.arc([20 * S, 10 * S, 44 * S, 36 * S], start=180, end=360,
      fill=PAPER, width=3 * S)
# body — rounded rect
rounded(d, (14, 28, 50, 56), 6, fill=PAPER)
# keyhole — punched back out of the body
d.ellipse([29 * S, 36 * S, 35 * S, 42 * S], fill=(16, 18, 22, 255))
d.polygon([(30 * S, 40 * S), (34 * S, 40 * S), (33 * S, 50 * S),
           (31 * S, 50 * S)], fill=(16, 18, 22, 255))
lock = lock.resize((64, 64), Image.LANCZOS)
lock.save(os.path.join(OUT, "lock.png"))
print("lock.png", lock.size)

# entry.png — the password entry field: ink glass, hairline paper border
entry = Image.new("RGBA", (280 * S, 40 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(entry)
rounded(d, (0, 0, 279, 39), 8, fill=INK, outline=INK_BORDER, width=S)
entry = entry.resize((280, 40), Image.LANCZOS)
entry.save(os.path.join(OUT, "entry.png"))
print("entry.png", entry.size)

# bullet.png — the per-character dot inside the entry
bullet = Image.new("RGBA", (9 * S, 9 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(bullet)
d.ellipse([1 * S, 1 * S, 8 * S, 8 * S], fill=PAPER)
bullet = bullet.resize((9, 9), Image.LANCZOS)
bullet.save(os.path.join(OUT, "bullet.png"))
print("bullet.png", bullet.size)

# box.png — the multi-prompt auth dialog background
box = Image.new("RGBA", (340 * S, 160 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(box)
rounded(d, (0, 0, 339, 159), 16, fill=INK, outline=INK_BORDER, width=S)
box = box.resize((340, 160), Image.LANCZOS)
box.save(os.path.join(OUT, "box.png"))
print("box.png", box.size)
