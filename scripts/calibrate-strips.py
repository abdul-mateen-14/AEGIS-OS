#!/usr/bin/env python3
"""W72 — calibrate-strips.py: derive the harness's pixel-strip boxes from
REAL capture frames, so a material commit ships its recalibrated strips in
the same SHA instead of re-running the four-commit bt86-bt91 war.

The w66-recalibrate.py pattern, generalized: point it at a capture
directory (a boot-test artifact's screenshots/, or any frame set), and it
prints the boxes the harness currently samples — the CC sheet glass band,
the plate/backdrop bands, the sidebar glyph column, the dock clip bands —
each with the measured energy/luminance so the numbers in boot-capture.py
are derived, never hand-guessed.

Usage:
    python3 scripts/calibrate-strips.py <capture-dir> [--png 04j2-...png]

Exit is always 0 — this is a calibration REPORT, not a gate; the gates
live in boot-capture.py and read the boxes this emits.
"""
import sys
import os
from PIL import Image


def grad_energy(im, box):
    px = im.convert("L").load()
    x0, y0, x1, y1 = box
    g = n = 0
    for yy in range(y0, y1, 2):
        for xx in range(x0, x1, 2):
            g += abs(px[xx, yy] - px[xx + 2, yy])
            g += abs(px[xx, yy] - px[xx, yy + 2])
            n += 2
    return g / max(1, n)


def mean_lum(im, box):
    px = im.convert("L").load()
    t = n = 0
    for yy in range(box[1], box[3], 2):
        for xx in range(box[0], box[2], 2):
            t += px[xx, yy]
            n += 1
    return t / max(1, n)


def find_window_top(im, x):
    """The first row from the top whose run at x is a hairline bright
    edge — the sheet/titleband window top (the window_hairline rule,
    reimplemented locally so the tool needs no harness import)."""
    px = im.convert("L").load()
    W, H = im.size
    for y in range(40, min(700, H)):
        if px[x, y] > 120 and px[x, y + 2] > 90:
            return y
    return None


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    if not os.path.isdir(d):
        print(f"no such dir: {d}")
        return 1
    im = None
    for cand in ("04j2-cc-over-files.png", "01-home.png"):
        p = os.path.join(d, cand)
        if os.path.exists(p):
            im = Image.open(p).convert("RGB")
            break
    if im is None:
        pngs = sorted(f for f in os.listdir(d) if f.endswith(".png"))
        if not pngs:
            print("no captures")
            return 1
        im = Image.open(os.path.join(d, pngs[0])).convert("RGB")
    W, H = im.size
    print(f"frame {im.size} from {d}")

    # CC sheet window: W68 changes its height (446 -> ~428) — re-derive
    # the sheet top from the frame, then emit the glass bands relative
    # to it. Sheet x span at 1280: W-348-4 .. W-4.
    top = find_window_top(im, W - 174)
    sx0, sx1 = W - 348, W - 4
    print(f"sheet top ~= {top} (x {sx0}..{sx1})")
    if top is not None:
        for name, box in (
            ("sheet glass A (lower band, pre-W68)",
                (1160, 418, 1260, 434)),
            ("sheet glass B (slider band, pre-W68)",
                (940, 540, 960, 620)),
        ):
            adj = (box[0], min(box[1], H), min(box[2], W),
                   min(box[3], H))
            print(f"  {name}: energy {grad_energy(im, adj):.2f} "
                  f"lum {mean_lum(im, adj):.0f}")
    back = (860, 418, 910, 434)
    print(f"  backdrop band {back}: lum {mean_lum(im, back):.0f}")

    # dock clip bands (W-anchored, bottom edge — stable across W67-W71)
    pill = (W // 2 - 240, H - 70, W // 2 + 240, H - 10)
    above = (W // 2 - 240, H - 130, W // 2 + 240, H - 90)
    print(f"  dock pill band {pill}: energy {grad_energy(im, pill):.2f}")
    print(f"  above-pill band {above}: energy "
          f"{grad_energy(im, above):.2f}")

    # sidebar glyph column (W75 moves the ink to white strokes): the
    # settings window's left edge — derive from the 04n frame if present
    n = os.path.join(d, "04n-wallpaper.png")
    if os.path.exists(n):
        si = Image.open(n).convert("L")
        stop = find_window_top(si, 220)
        print(f"04n settings window top ~= {stop} — W63 strip uses "
              f"y stop+90..stop+550, x sx0..sx0+260 (see boot-capture.py)")
    print("emit these boxes into boot-capture.py in the SAME SHA as the "
          "material change (W72)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
