#!/usr/bin/env python3
"""W41 — recalibrate the blur A/B strips from bt73's real on/off frames.

bt73 (44155514095) proved the clip fix WORKS (blurlog: 'region panel
275,270 730x64' — the dock's blur is the pill only) and exposed that
the old strips were measuring the DOCK WINDOW'S FULL-RECT BLEED:
- w66's strip (W-340..W-320, y 540..620) sits above the pill inside
  the 340 px dock window — bt71's 1.66/11.86 PASS was the bleed, the
  bug the user reported.
- the clip rung's above-pill band (y H-130..H-90) is the same zone —
  static across toggles is now the CORRECT (clipped) behavior.

New anchors, measured from bt73's frames (04j2 = blur forced on,
04j4 = off, both with the CC sheet open):
- w66 (sheet glass): must sit INSIDE the sheet window (348x446 at
  x~928..1276, y~65..511) over glass with wallpaper behind.
- clip positive control: INSIDE the pill (y H-70..H-10), must MOVE.
- clip negative control (above pill): must stay.
"""
from PIL import Image

OUT = "/home/z/my-project/scripts/bt73-art/screenshots"

def grad_energy(png, box):
    im = Image.open(png).convert("L")
    px = im.load()
    x0, y0, x1, y1 = box
    g = 0
    n = 0
    for yy in range(y0, y1, 2):
        for xx in range(x0, x1, 2):
            g += abs(px[xx, yy] - px[xx + 2, yy])
            g += abs(px[xx, yy] - px[xx, yy + 2])
            n += 2
    return g / max(1, n)

on = f"{OUT}/04j2-cc-over-files.png"
off = f"{OUT}/04j4-cc-blur-off.png"
rest = f"{OUT}/04j5-cc-blur-restored.png"

# candidate sheet-glass boxes (inside the sheet, over wallpaper-backed
# glass: x 1040..1270, y 400..505 — below Files' right edge, above the
# sheet's bottom edge ~511)
cands = {
    "sheet glass A (x1040-1270,y410-500)":
        (1040, 410, 1270, 500),
    "sheet glass B (x1150-1270,y430-500)":
        (1150, 430, 1270, 500),
    "sheet glass C (x940-1040,y430-505)":
        (940, 430, 1040, 505),
    "OLD w66 strip (x940-960,y540-620)":
        (1280 - 340, 540, 1280 - 320, 620),
}
print("== sheet-glass candidates (want BIG on/off delta) ==")
for name, box in cands.items():
    a = grad_energy(on, box)
    b = grad_energy(off, box)
    c = grad_energy(rest, box)
    print(f"  {name}: on={a:.2f} off={b:.2f} rest={c:.2f} "
          f"ratio={max(a, b) / max(0.01, min(a, b)):.2f}")

# pill + above-pill bands (screen 1280x800: pill y 730..794)
pill = (400, 732, 880, 792)
above = (400, 670, 880, 710)
print("== dock clip bands ==")
for name, box in (("pill band", pill), ("above-pill band", above)):
    a = grad_energy(on, box)
    b = grad_energy(off, box)
    print(f"  {name} {box}: on={a:.2f} off={b:.2f} "
          f"delta={abs(a - b):.2f}")
