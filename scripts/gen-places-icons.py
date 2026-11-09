#!/usr/bin/env python3
"""Generate the Aegis icon theme additions: places/, devices/ and the four
first-party app squircles (aegis-files, aegis-settings, aegis-terminal,
aegis-calculator). Matches the existing squircle style in the repo
(superellipse body + sheen + hairline + white glyph, plate 9 language)."""
import math, os

ROOT = "/home/z/my-project/work/aegis-v052/debian-live/config/includes.chroot/usr/share/icons/Aegis"

def squircle_path(a, n=4.5, cx=50.0, cy=50.0, steps=96):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(c) ** (2 / n), c)
        y = cy + a * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.2f} {y:.2f}")
    return "M" + " L".join(pts) + " Z"

def app_svg(c_top, c_bottom, glyph):
    body = squircle_path(49.0)
    hair = squircle_path(47.6)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{c_top}"/>
    <stop offset="1" stop-color="{c_bottom}"/>
  </linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/>
    <stop offset="0.5" stop-color="#ffffff" stop-opacity="0.03"/>
    <stop offset="1" stop-color="#000000" stop-opacity="0.12"/>
  </linearGradient>
 <path d="{body}" fill="url(#g)"/>
 <path d="{body}" fill="url(#sheen)"/>
 <path d="{hair}" fill="none" stroke="#ffffff" stroke-opacity="0.14" stroke-width="0.8"/>
{glyph}
</svg>
'''

def place_svg(tint, glyph):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g fill="none" stroke="{tint}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
{glyph}
  </g>
</svg>
'''

FOLDER_BODY = "M22 38 q0-6 6-6 h14 l6 6 h24 q6 0 6 6 v30 q0 6-6 6 H28 q-6 0-6-6 Z"

APPS = {
    "aegis-files": ("#5B8BFF", "#1D4FEA", '''
 <path d="M28 35 q0-4 4-4 h10 l5 5 h21 q4 0 4 4 v5 H28 Z" fill="#ffffff" fill-opacity="0.9"/>
 <path d="M28 43 h44 q4 0 4 4 v16 q0 5-5 5 H33 q-5 0-5-5 Z" fill="#ffffff"/>'''),
    "aegis-settings": ("#3E8BFF", "#1D4FEA", '''
 <path d="M50 36 a14 14 0 1 0 0.01 0 Z M50 42 a8 8 0 1 1 -0.01 0 Z" fill="#ffffff" fill-rule="evenodd"/>
''' + "\n".join(
        f' <rect x="47" y="24" width="6" height="9" rx="2" fill="#ffffff" transform="rotate({k*45} 50 50)"/>'
        for k in range(8))),
    "aegis-terminal": ("#454C56", "#191D23", '''
 <path d="M32 36 L44 48 L32 60" fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
 <path d="M50 62 H70" fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round"/>'''),
    "aegis-calculator": ("#FF9F0A", "#E8820A", '''
 <rect x="30" y="28" width="40" height="12" rx="4" fill="#ffffff"/>
''' + "\n".join(
        f' <circle cx="{x}" cy="{y}" r="4" fill="#ffffff"/>'
        for y in (52, 64, 76) for x in (36, 50, 64))),
}

PLACES = {
    "user-home": "#3E8BFF", "folder": "#5B8BFF",
    "folder-documents": "#4A9BFF", "folder-download": "#28C840",
    "folder-music": "#FA2D48", "folder-pictures": "#8B5CF6",
    "folder-videos": "#FF9F0A", "trash-can-empty": "#8A909C",
    "trash-can-full": "#8A909C",
}

TRASH_BODY = '''M32 34 H68 M50 27 v7
 M35 41 l3.5 33 q0.3 3 3.3 3 h16.4 q3 0 3.3-3 L65 41
 M44 48 v21 M56 48 v21'''

GLYPHS = {
    "user-home": ' <path d="M24 52 L50 30 L76 52"/>\n <path d="M31 47 V74 H69 V47"/>',
    "folder": f' <path d="{FOLDER_BODY}"/>',
    "folder-documents": f' <path d="{FOLDER_BODY}"/>\n <path d="M38 56 H62 M38 66 H56"/>',
    "folder-download": f' <path d="{FOLDER_BODY}"/>\n <path d="M50 47 V60 M43.5 54.5 L50 61.5 L56.5 54.5"/>',
    "folder-music": f' <path d="{FOLDER_BODY}"/>\n <circle cx="45" cy="62" r="4.5"/>\n <path d="M49.5 62 V45 L59 42.5 V53"/>',
    "folder-pictures": f' <path d="{FOLDER_BODY}"/>\n <path d="M36 63 l8-10 6 6.5 7-9.5 11 13"/>\n <circle cx="41" cy="49" r="2.6"/>',
    "folder-videos": f' <path d="{FOLDER_BODY}"/>\n <path d="M45 47 L61 56.5 L45 66 Z"/>',
    "trash-can-empty": " " + TRASH_BODY,
    "trash-can-full": " " + TRASH_BODY + "\n <path d=\"M38 34 L44 27 L50 33 L57 26 L62 34\"/>",
}

DEVICES = {
    "drive-harddisk": "#8A909C",
    "drive-removable": "#3E8BFF",
}
DRIVE_GLYPH = (' <rect x="26" y="36" width="48" height="28" rx="6"/>\n'
               ' <path d="M36 56 H64"/>\n <circle cx="31.5" cy="56" r="0.8"/>')

os.makedirs(f"{ROOT}/apps/scalable", exist_ok=True)
os.makedirs(f"{ROOT}/places/scalable", exist_ok=True)
os.makedirs(f"{ROOT}/devices/scalable", exist_ok=True)

for name, (top, bot, glyph) in APPS.items():
    with open(f"{ROOT}/apps/scalable/{name}.svg", "w") as f:
        f.write(app_svg(top, bot, glyph))

for name, tint in PLACES.items():
    with open(f"{ROOT}/places/scalable/{name}.svg", "w") as f:
        f.write(place_svg(tint, GLYPHS[name]))

for name, tint in DEVICES.items():
    with open(f"{ROOT}/devices/scalable/{name}.svg", "w") as f:
        f.write(place_svg(tint, DRIVE_GLYPH))

print("written:", sum(len(files) for _, _, files in os.walk(ROOT)))
