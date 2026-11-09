#!/usr/bin/env python3
"""Render the Aegis theme to a check montage (dark background like the dock)."""
import cairosvg, glob, os
from PIL import Image

APPS = "/home/z/my-project/work/aegis-os/debian-live/config/includes.chroot/usr/share/icons/Aegis/apps/scalable"
OUT = "/tmp/icon-qa"
os.makedirs(OUT, exist_ok=True)

files = sorted(glob.glob(f"{APPS}/*.svg"))
CELL, PAD = 100, 10
cols = 7
rows = (len(files) + cols - 1) // cols
W = cols * (CELL + PAD) + PAD
H = rows * (CELL + PAD) + PAD
canvas = Image.new("RGB", (W, H), (18, 22, 30))

for i, f in enumerate(files):
    png = f"{OUT}/{os.path.basename(f)}.png"
    cairosvg.svg2png(url=f, write_to=png, output_width=CELL, output_height=CELL)
    tile = Image.open(png).convert("RGBA")
    x = PAD + (i % cols) * (CELL + PAD)
    y = PAD + (i // cols) * (CELL + PAD)
    canvas.paste(tile, (x, y), tile)

canvas.save("/tmp/icon-montage.png")
print("apps:", len(files), "->", "/tmp/icon-montage.png")

# also render the places + devices icons on a dark panel
pv = "/home/z/my-project/work/aegis-os/debian-live/config/includes.chroot/usr/share/icons/Aegis/places/scalable"
dv = "/home/z/my-project/work/aegis-os/debian-live/config/includes.chroot/usr/share/icons/Aegis/devices/scalable"
small = sorted(glob.glob(f"{pv}/*.svg")) + sorted(glob.glob(f"{dv}/*.svg"))
S, SP = 64, 14
W2 = len(small) * (S + SP) + SP
canvas2 = Image.new("RGB", (W2, S + 2 * SP), (18, 22, 30))
for i, f in enumerate(small):
    png = f"{OUT}/pd_{os.path.basename(f)}.png"
    cairosvg.svg2png(url=f, write_to=png, output_width=S, output_height=S)
    t = Image.open(png).convert("RGBA")
    canvas2.paste(t, (SP + i * (S + SP), SP), t)
canvas2.save("/tmp/places-montage.png")
print("places+devices:", len(small))
