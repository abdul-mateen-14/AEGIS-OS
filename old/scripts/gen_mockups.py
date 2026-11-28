#!/usr/bin/env python3
# AEGIS v0.6.81 mockups — 4 review images built from the icon pack + the real
# v0.6.78 wallpaper/panel language. Glass = blur + saturate + white ink +
# specular rims + sheen + inner bottom shadow (the W67 recipe, rendered).
import os, math
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont

REPO = "/home/z/my-project/work/aegis-v0678/repo"
PACK = "/home/z/my-project/download/AEGIS-v0.6.81-icon-pack/png"
OUT = "/home/z/my-project/download/AEGIS-v0.6.81-mockups"
os.makedirs(OUT, exist_ok=True)

F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(sz, bold=False): return ImageFont.truetype(FB if bold else F, sz)

ACCENT = (62, 139, 255)
CAP = Image.open(f"{REPO}/docs/screenshots/v0.6.78/01-home.png").convert("RGB")
SET = Image.open(f"{REPO}/docs/screenshots/v0.6.78/04-settings.png").convert("RGB")
CC  = Image.open(f"{REPO}/docs/screenshots/v0.6.78/04j2-cc-over-files.png").convert("RGB")
MARK = Image.open(f"{REPO}/shell/src/qml/aegis-mark.png").convert("RGBA")

# wallpaper backdrop: the real Aurora Ink, panel/island rows cropped out
WALL = CAP.crop((0, 72, 1280, 708)).resize((1280, 800), Image.LANCZOS)

def rr(draw, box, r, **kw): draw.rounded_rectangle(box, radius=r, **kw)

def overlay(im):
    """translucent shapes go on a fresh layer — Draw() on an RGBA image does
    NOT blend semi-transparent ink in this Pillow; alpha_composite does."""
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    return ov, ImageDraw.Draw(ov)

def commit(im, ov): im.alpha_composite(ov)

def glass(im, box, r=18, blur=18, sat=2.0, bright=1.08, ink=0.14, border=0.30,
          sheen=0.10, ibs=0.12, ink_color=(255, 255, 255)):
    """the W67 material: blurred+saturated backdrop, white ink, rims, sheen."""
    x0, y0, x1, y1 = box
    reg = im.crop(box).filter(ImageFilter.GaussianBlur(blur))
    reg = ImageEnhance.Color(reg).enhance(sat)
    reg = ImageEnhance.Brightness(reg).enhance(bright)
    ov = Image.new("RGBA", reg.size, ink_color + (int(255 * ink),))
    reg = Image.alpha_composite(reg.convert("RGBA"), ov)
    if sheen > 0:  # top-half sheen wash
        h = reg.size[1]
        grad = Image.new("L", (1, h))
        for y in range(h):
            grad.putpixel((0, y), int(255 * sheen * max(0, 1 - y / (h * 0.55))))
        grad = grad.resize(reg.size)
        white_layer = Image.new("RGBA", reg.size, (255, 255, 255, 255))
        white_layer.putalpha(grad)
        reg = Image.alpha_composite(reg, white_layer)
    mask = Image.new("L", reg.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, reg.size[0] - 1, reg.size[1] - 1), r, fill=255)
    im.paste(reg.convert("RGB"), (x0, y0), mask)
    dr = ImageDraw.Draw(im, "RGBA")
    rr(dr, box, r, outline=(255, 255, 255, int(255 * border)), width=2)          # rim
    rr(dr, (x0 + 1, y0 + 1, x1 - 1, y1 - 1), r - 1,
       outline=(255, 255, 255, int(255 * border * 0.45)), width=1)               # inner rim
    if ibs > 0:                                                                  # inner bottom shadow
        ov, d2 = overlay(im)
        d2.line((x0 + r, y1 - 2, x1 - r, y1 - 2), fill=(0, 0, 0, int(255 * ibs)), width=2)
        commit(im, ov)

def icon(im, name, color, px, pos):
    p = f"{PACK}/{name}-{color}@3x.png"
    ic = Image.open(p).convert("RGBA").resize((px, px), Image.LANCZOS)
    im.paste(ic, pos, ic)

def text(im, pos, s, sz=12, fill=(255, 255, 255, 235), bold=False, anchor="la"):
    ImageDraw.Draw(im, "RGBA").text(pos, s, font=font(sz, bold), fill=fill, anchor=anchor)

def circle_glass(im, c, d, active=False, glyph=None):
    """64px circular toggle — glass ring, or accent fill when active."""
    cx, cy = c
    box = (cx - d // 2, cy - d // 2, cx + d // 2, cy + d // 2)
    reg = im.crop(box).filter(ImageFilter.GaussianBlur(14))
    reg = ImageEnhance.Color(reg).enhance(2.0)
    reg = reg.convert("RGBA")
    if active:
        base = Image.new("RGBA", reg.size, ACCENT + (235,))
    else:
        base = Image.alpha_composite(reg, Image.new("RGBA", reg.size, (255, 255, 255, 30)))
    m = Image.new("L", reg.size, 0); ImageDraw.Draw(m).ellipse((0, 0, d - 1, d - 1), fill=255)
    im.paste(base.convert("RGB"), (box[0], box[1]), m)
    dr = ImageDraw.Draw(im, "RGBA")
    dr.ellipse(box, outline=(255, 255, 255, 70 if not active else 90), width=2)
    ov, d2 = overlay(im)
    d2.ellipse((box[0] + 2, box[1] + 2, box[2] - 2, box[3] - 2), outline=(255, 255, 255, 36), width=1)
    commit(im, ov)
    if glyph:
        icon(im, glyph[0], "white", glyph[2], (cx - glyph[2] // 2, cy - glyph[2] // 2))

def pill_slider(im, box, frac, glyph):
    x0, y0, x1, y1 = box  # track h 30
    glass(im, box, r=15, blur=12, sat=1.9, ink=0.16, border=0.18, sheen=0, ibs=0.16)
    ov, dr = overlay(im)
    kw = int((x1 - x0 - 6) * frac)
    rr(dr, (x0 + 3, y0 + 3, x0 + 3 + kw, y1 - 3), 12, fill=(255, 255, 255, 205))
    kx = x0 + 3 + kw - 11
    rr(dr, (kx, y0 + 4, kx + 22, y1 - 4), 8, fill=(255, 255, 255, 245),
       outline=(0, 0, 0, 40), width=1)
    commit(im, ov)
    icon(im, glyph, "white", 22, (x0 - 30, (y0 + y1) // 2 - 11))

def hairline(im, x0, x1, y):
    ov, dr = overlay(im)
    dr.line((x0, y, x1, y), fill=(255, 255, 255, 40), width=1)
    commit(im, ov)

def panel_and_island(im):
    glass(im, (0, 0, 1280, 28), r=2, blur=10, sat=1.8, ink=0.12, border=0.0, sheen=0.06, ibs=0)
    mk = MARK.resize((15, 15), Image.LANCZOS); im.paste(mk, (12, 7), mk)
    text(im, (33, 6), "Aegis", 12, (255, 255, 255, 235), True)
    icon(im, "wifi", "white", 18, (1074, 5))
    icon(im, "speaker", "white", 18, (1100, 5))
    icon(im, "battery", "white", 24, (1126, 2))
    text(im, (1156, 8), "Fri 20 Nov  12:19", 10)
    icon(im, "sliders", "white", 16, (1252, 6))
    # island — the one opaque instrument (T17, exempt from the ink flip)
    dr = ImageDraw.Draw(im, "RGBA")
    rr(dr, (556, 36, 724, 64), 14, fill=(8, 10, 13, 240), outline=(255, 255, 255, 30), width=1)
    mk2 = MARK.resize((17, 17), Image.LANCZOS); im.paste(mk2, (585, 41), mk2)

def dock(im, labels=False):
    dr = ImageDraw.Draw(im, "RGBA")
    glass(im, (266, 710, 1014, 784), r=24, blur=16, sat=1.9, ink=0.08, border=0.38,
          sheen=0.05, ibs=0.10)
    plates = [
        "folder", "mail", "mark", "chat", "cx", "note", "grid", "pencil",
        "pulse", "bag", "gear", "trash"]
    x = 292
    for kind in plates:
        # W76 clear mode: every plate is GLASS, every glyph white — the
        # colorful v1.3 plate-9 identity is retired by owner order
        glass(im, (x, 721, x + 52, 773), r=13, blur=8, sat=1.8, ink=0.13,
              border=0.30, sheen=0.04, ibs=0.06)
        gx, gy = x + 14, 729
        d2 = ImageDraw.Draw(im, "RGBA")
        if kind == "folder":
            d2.rounded_rectangle((gx, gy + 6, gx + 24, gy + 22), 4, fill=(255, 255, 255, 235))
            d2.rounded_rectangle((gx, gy + 2, gx + 10, gy + 8), 2, fill=(255, 255, 255, 235))
        elif kind == "mail":
            d2.rounded_rectangle((gx, gy + 6, gx + 24, gy + 20), 3, outline=(255, 255, 255, 235), width=2)
            d2.line((gx + 1, gy + 7, gx + 12, gy + 15, gx + 23, gy + 7), fill=(255, 255, 255, 235), width=2)
        elif kind == "mark":
            m3 = MARK.resize((26, 26), Image.LANCZOS).convert("RGBA")
            im.paste(m3, (x + 13, gy), m3)
        elif kind == "chat":
            d2.rounded_rectangle((gx, gy + 4, gx + 24, gy + 18), 7, fill=(255, 255, 255, 235))
            d2.polygon([(gx + 6, gy + 17), (gx + 6, gy + 24), (gx + 13, gy + 17)], fill=(255, 255, 255, 235))
        elif kind == "cx":
            d2.text((x + 26, gy + 12), "Cx", font=font(15, True), fill=(255, 255, 255, 235), anchor="mm")
            d2.text((x + 26, gy + 22), "CoreX", font=font(6), fill=(255, 255, 255, 190), anchor="mm")
        elif kind == "note":
            d2.ellipse((gx + 2, gy + 12, gx + 12, gy + 22), fill=(255, 255, 255, 235))
            d2.line((gx + 12, gy + 16, gx + 12, gy + 2), fill=(255, 255, 255, 235), width=3)
            d2.ellipse((gx + 12, gy + 2, gx + 22, gy + 12), fill=(255, 255, 255, 235))
        elif kind == "grid":
            for i in range(3):
                for j in range(3):
                    d2.rounded_rectangle((gx + i * 8, gy + 4 + j * 8, gx + 5 + i * 8, gy + 9 + j * 8), 2, fill=(255, 255, 255, 235))
        elif kind == "pencil":
            d2.line((gx + 4, gy + 20, gx + 20, gy + 4), fill=(255, 255, 255, 235), width=4)
            d2.polygon([(gx + 2, gy + 22), (gx + 4, gy + 20), (gx + 6, gy + 22)], fill=(255, 255, 255, 235))
        elif kind == "pulse":
            d2.line((gx + 1, gy + 12, gx + 7, gy + 12, gx + 10, gy + 5, gx + 14, gy + 19, gx + 17, gy + 12, gx + 23, gy + 12),
                    fill=(255, 255, 255, 235), width=2, joint="curve")
        elif kind == "bag":
            d2.rounded_rectangle((gx + 2, gy + 8, gx + 22, gy + 22), 4, fill=(255, 255, 255, 235))
            d2.arc((gx + 6, gy + 1, gx + 18, gy + 12), 180, 360, fill=(255, 255, 255, 235), width=3)
        elif kind == "gear":
            d2.ellipse((gx + 5, gy + 5, gx + 19, gy + 19), outline=(255, 255, 255, 235), width=3)
            for k in range(8):
                a = k * math.pi / 4
                d2.line((gx + 12 + 9 * math.cos(a), gy + 12 + 9 * math.sin(a),
                         gx + 12 + 12 * math.cos(a), gy + 12 + 12 * math.sin(a)), fill=(255, 255, 255, 235), width=3)
        elif kind == "trash":
            d2.line((gx + 4, gy + 6, gx + 20, gy + 6), fill=(255, 255, 255, 235), width=2)
            d2.rounded_rectangle((gx + 6, gy + 8, gx + 18, gy + 22), 3, outline=(255, 255, 255, 235), width=2)
            for k in (10, 12, 14):
                d2.line((gx + k, gy + 10, gx + k, gy + 20), fill=(255, 255, 255, 235), width=1)
        x += 60

def files_window(im, box):
    x0, y0, x1, y1 = box
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x0 + 2, y0 + 8, x1 + 2, y1 + 8), 14, fill=(0, 0, 0, 70))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
    # titleband: Chrome Glass — dark ink over the blurred wallpaper (stays dark)
    glass(im, (x0, y0, x1, y0 + 44), r=14, blur=16, sat=1.9, bright=1.0,
          ink=0.45, ink_color=(12, 13, 16), border=0.22, sheen=0.05, ibs=0)
    dr = ImageDraw.Draw(im, "RGBA")
    dr.line((x0, y0 + 44, x1, y0 + 44), fill=(255, 255, 255, 26), width=1)
    text(im, ((x0 + x1) // 2, y0 + 13), "Files", 13, (255, 255, 255, 245), True, anchor="ma")
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        dr.ellipse((x0 + 18 + i * 20, y0 + 16, x0 + 30 + i * 20, y0 + 28), fill=c)
    # content: SOLID — the fd24476 rule (glass is chrome, content stays solid)
    dr.rounded_rectangle((x0, y0 + 44, x1, y1), 0, fill=(38, 41, 48))
    dr.rounded_rectangle((x0, y1 - 14, x1, y1), 14, fill=(38, 41, 48))
    ov, d2 = overlay(im)
    rr(d2, (x0 + 1, y0 + 1, x1 - 1, y1 - 1), 14, outline=(255, 255, 255, 34), width=1)
    commit(im, ov)
    dr.rounded_rectangle((x0, y0 + 44, x0 + 200, y1), 0, fill=(43, 47, 54))
    dr.line((x0 + 200, y0 + 44, x0 + 200, y1), fill=(255, 255, 255, 20), width=1)
    rows = [("Home", ACCENT), ("Documents", (94, 156, 255)), ("Downloads", (52, 199, 123)),
            ("Music", (250, 45, 72)), ("Pictures", (139, 92, 246)), ("Videos", (255, 159, 10)),
            ("Trash", (110, 123, 255))]
    for i, (name, tint) in enumerate(rows):
        yy = y0 + 62 + i * 34
        ov, d2 = overlay(im)
        if i == 0: rr(d2, (x0 + 8, yy - 6, x0 + 192, yy + 22), 8, fill=ACCENT + (80,))
        commit(im, ov)
        dr.rounded_rectangle((x0 + 18, yy - 2, x0 + 32, yy + 12), 3, fill=tint)
        text(im, (x0 + 42, yy), name, 12)
    text(im, (x0 + 216, y0 + 56), "Home  ·  13 items", 11, (255, 255, 255, 150))
    for c in range(5):
        cx = x0 + 216 + c * 124
        dr.rounded_rectangle((cx, y0 + 84, cx + 112, y0 + 186), 10, fill=(47, 51, 59),
                             outline=(255, 255, 255, 26), width=1)
        dr.rounded_rectangle((cx + 36, y0 + 108, cx + 76, y0 + 140), 5, fill=(94, 156, 255, 200))
        dr.rounded_rectangle((cx + 36, y0 + 104, cx + 50, y0 + 112), 3, fill=(94, 156, 255, 200))
        text(im, (cx + 56, y0 + 152), ["Desktop", "Documents", "Downloads", "Music", "Pictures"][c],
             10, (255, 255, 255, 200), anchor="ma")
    text(im, (x0 + 216, y0 + 206), "The card grid is W64's Small preset — solid plates, glass nowhere.",
         10, (255, 255, 255, 120))

def cc_sheet(im, box):
    x0, y0, x1, y1 = box
    glass(im, box, r=20, blur=22, sat=2.0, bright=1.12, ink=0.14, border=0.34, sheen=0.10, ibs=0.14)
    mk = MARK.resize((16, 16), Image.LANCZOS); im.paste(mk, (x0 + 16, y0 + 12), mk)
    text(im, (x0 + 40, y0 + 12), "Control Center", 13, (255, 255, 255, 245), True)
    hairline(im, x0 + 14, x1 - 14, y0 + 38)
    tiles = [("wired", "Ethernet", True), ("bluetooth", "Bluetooth", False),
             ("moon", "Calm Mode", False), ("half", "Dark Mode", True)]
    for i, (g, lab, act) in enumerate(tiles):
        cx = x0 + 48 + i * 76
        cy = y0 + 74
        circle_glass(im, (cx, cy), 62, active=act, glyph=(g, None, 26))
        text(im, (cx, cy + 38), lab, 9, (255, 255, 255, 200), anchor="ma")
    hairline(im, x0 + 14, x1 - 14, y0 + 126)
    ov, dr = overlay(im)
    rr(dr, (x0 + 16, y0 + 136, x1 - 16, y0 + 174), 12, fill=(255, 255, 255, 24))
    rr(dr, (x1 - 62, y0 + 143, x1 - 24, y0 + 167), 12, fill=(255, 255, 255, 42))
    dr.ellipse((x1 - 58, y0 + 146, x1 - 40, y0 + 164), fill=(255, 255, 255, 245))
    commit(im, ov)
    icon(im, "bell", "white", 18, (x0 + 28, y0 + 146))
    text(im, (x0 + 54, y0 + 147), "Do Not Disturb", 11)
    hairline(im, x0 + 14, x1 - 14, y0 + 186)
    pill_slider(im, (x0 + 56, y0 + 196, x1 - 16, y0 + 226), 0.32, "sun")
    pill_slider(im, (x0 + 56, y0 + 234, x1 - 16, y0 + 264), 0.72, "speaker")
    hairline(im, x0 + 14, x1 - 14, y0 + 276)
    for i, s in enumerate(["Lock Screen", "Suspend", "Restart", "Shut Down"]):
        text(im, (x0 + 20 + i * 76, y0 + 284), s, 10, (255, 255, 255, 190))
    text(im, (x0 + 20, y0 + 304), "All Settings", 11, ACCENT + (255,), True)
    text(im, (x0 + 112, y0 + 304), "Software Update", 11, ACCENT + (255,), True)
    text(im, (x1 - 20, y0 + 306), "TIER A · LIQUID", 8, (255, 255, 255, 110), anchor="ra")

def mock_cc():
    im = WALL.copy().convert("RGBA")
    panel_and_island(im)
    cc_sheet(im, (916, 78, 1262, 410))
    dock(im)
    im.convert("RGB").save(f"{OUT}/cc-liquid-glass.png")
    print("cc-liquid-glass.png", im.size)

def mock_desktop():
    im = WALL.copy().convert("RGBA")
    panel_and_island(im)
    files_window(im, (60, 110, 860, 690))
    dock(im)
    im.convert("RGB").save(f"{OUT}/desktop-overview.png")
    print("desktop-overview.png", im.size)

def mock_anatomy():
    base = Image.open(f"{OUT}/desktop-overview.png")
    win = base.crop((60, 110, 860, 690))
    S = 1.15
    win = win.resize((int(win.width * S), int(win.height * S)), Image.LANCZOS)
    im = Image.new("RGBA", (1280, 770), (10, 12, 15, 255))
    dr = ImageDraw.Draw(im, "RGBA")
    ox, oy = 24, 56
    im.paste(win, (ox, oy))
    rr(dr, (ox - 1, oy - 1, ox + win.width, oy + win.height), 14,
       outline=(255, 255, 255, 40), width=1)
    def pt(lx, ly): return (ox + int(lx * S), oy + int(ly * S))
    legend = [
        (1, pt(400, 20), "44px titleband = Chrome Glass", "dark ink + hairline lip (W67 rule)"),
        (2, pt(46, 20), "Traffic lights + centered title", "untouched"),
        (3, pt(110, 115), "Sidebar is CONTENT: solid", "34px rows, pill alpha 0.8 — no glass here"),
        (4, pt(480, 170), "Card grid (W64 Small)", "solid plates + hairline rims (fd24476)"),
        (5, pt(796, 6), "Window rim: 1px white/30", "the v1.6 specular carries the shape"),
    ]
    ly = 92
    for n, anchor, t1, t2 in legend:
        cy = ly + 8
        dr.line((anchor[0], anchor[1], 966, cy), fill=(90, 140, 210, 180), width=1)
        dr.ellipse((anchor[0] - 5, anchor[1] - 5, anchor[0] + 5, anchor[1] + 5),
                   outline=(120, 170, 235, 230), width=2)
        dr.ellipse((958, cy - 11, 980, cy + 11), fill=ACCENT + (255,))
        dr.text((969, cy), str(n), font=font(11, True), fill=(255, 255, 255, 255), anchor="mm")
        dr.text((992, cy - 8), t1, font=font(12, True), fill=(235, 238, 245, 255))
        dr.text((992, cy + 10), t2, font=font(10), fill=(170, 178, 190, 255))
        ly += 118
    dr.text((24, 742), "Anatomy — what stays glass and what stays solid in app windows (W67 + fd24476 applied)",
            font=font(13, True), fill=(150, 170, 200, 255))
    im.convert("RGB").save(f"{OUT}/window-anatomy.png")
    print("window-anatomy.png", im.size)

def mock_before_after():
    im = Image.new("RGBA", (1280, 940), (13, 15, 19, 255))
    dr = ImageDraw.Draw(im, "RGBA")
    dr.text((30, 20), "ICONS — before (v0.6.78, real captures) vs after (the pack masters)", font=font(16, True), fill=(150, 180, 220, 255))
    # BEFORE: the real settings sidebar rows
    crop = SET.crop((192, 240, 398, 542))
    crop = crop.resize((int(crop.width * 1.55), int(crop.height * 1.55)), Image.LANCZOS)
    dr.text((30, 52), "BEFORE — Settings sidebar, 1:1.55 from 04-settings.png", font=font(12, True), fill=(255, 120, 110, 255))
    im.paste(crop, (30, 72))
    # AFTER: the full sidebar rebuilt — clear mode, owner orders applied
    dr.text((470, 52), "AFTER — clear mode: no brand header, Aegis ID first",
            font=font(12, True), fill=(80, 220, 140, 255))
    rr(dr, (470, 72, 900, 578), 12, fill=(20, 21, 25, 255),
       outline=(255, 255, 255, 30), width=1)
    ov, d2 = overlay(im)
    d2.ellipse((488, 84, 526, 122), fill=(255, 255, 255, 28))
    d2.ellipse((488, 84, 526, 122), outline=(255, 255, 255, 70), width=1)
    commit(im, ov)
    mk = MARK.resize((20, 20), Image.LANCZOS)
    im.paste(mk, (497, 93), mk)
    dr.text((536, 90), "Debian Live user", font=font(12, True), fill=(245, 246, 250, 255))
    dr.text((536, 106), "Aegis ID · Local account", font=font(10), fill=(170, 178, 190, 255))
    dr.text((878, 94), "›", font=font(18), fill=(170, 178, 190, 255))
    hairline(im, 484, 886, 134)
    rows = [("mountain", "Wallpaper"), ("palette", "Appearance"), ("sparkles", "Desktop Effects"),
            ("chip", "Drivers & Firmware"), ("monitor", "Displays"), ("speaker", "Sound"),
            ("netWifi", "Network"), ("person", "Users")]
    y = 144
    for i, (g, lab) in enumerate(rows):
        ov, d2 = overlay(im)
        if i == 0: rr(d2, (478, y, 892, y + 40), 10, fill=ACCENT + (120,))
        commit(im, ov)
        icon(im, g, "white", 30, (494, y + 5))
        dr.text((536, y + 12), lab, font=font(13, True), fill=(245, 246, 250, 255))
        y += 46
    dr.text((470, 588), "no brand row · white glyphs · the selected pill carries the accent",
            font=font(10), fill=(150, 158, 170, 255))
    # verdicts
    dr.text((930, 52), "VERDICTS (the honest list)", font=font(12, True), fill=(150, 180, 220, 255))
    verdicts = [
        ("palette", "CRITICAL — the bezier blob reads as 'B'"),
        ("sparkles", "CRITICAL — plus-shaped noise, not stars"),
        ("chip", "MEDIUM — legs too short: reads as sun"),
        ("mountain", "MEDIUM — sun dot 1.1px: invisible"),
        ("person", "MEDIUM — optical size ~12px in 18px box"),
        ("wired", "LOW — reads as hamburger lines at 1x"),
        ("family", "SYSTEMIC — two geometries per glyph (panel vs CC)"),
        ("brand row", "REMOVED — owner order (Settings sidebar header)"),
        ("tints", "RETIRED — owner order: iOS-26 clear mode (white glyphs)"),
    ]
    y = 78
    for g, s in verdicts:
        dr.text((930, y), "✗ " + g, font=font(12, True), fill=(255, 120, 110, 255))
        dr.text((930, y + 18), s, font=font(10), fill=(200, 205, 215, 255))
        y += 52
    dr.text((30, 620), "CONTROL CENTER TILE GLYPHS — before (CC's local stroked set, 1.6px) vs after (unified masters @2.2px)",
            font=font(12, True), fill=(150, 180, 220, 255))
    ccrop = CC.crop((930, 115, 1268, 268))
    ccrop = ccrop.resize((int(ccrop.width * 1.35), int(ccrop.height * 1.35)), Image.LANCZOS)
    im.paste(ccrop, (30, 645))
    for i, (g, lab, act) in enumerate([("wired", "Ethernet", 1), ("bluetooth", "Bluetooth", 0),
                                       ("moon", "Calm", 0), ("half", "Dark Mode", 1)]):
        cx = 620 + i * 86
        dr.rounded_rectangle((cx - 34, 655, cx + 34, 723), 31, fill=(30, 33, 39, 255) if not act else ACCENT + (235,))
        dr.rounded_rectangle((cx - 34, 655, cx + 34, 723), 31, outline=(255, 255, 255, 60), width=2)
        ic = Image.open(f"{PACK}/{g}-white@3x.png").convert("RGBA").resize((30, 30), Image.LANCZOS)
        im.paste(ic, (cx - 15, 674), ic)
        dr.text((cx, 730), lab, font=font(9), fill=(210, 214, 222, 255), anchor="ma")
    dr.text((620, 756), "W68: the tiles become 62px circles — accent fill = ON, glass = OFF; glyphs at 2.2px stroke weight",
            font=font(10), fill=(160, 168, 180, 255))
    im.convert("RGB").save(f"{OUT}/icons-before-after.png")
    print("icons-before-after.png", im.size)

mock_cc()
mock_desktop()
mock_anatomy()
mock_before_after()
