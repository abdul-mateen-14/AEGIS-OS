#!/usr/bin/env python3
"""Regenerate the Aegis icon theme (proposal plate 09).

- One squircle mask + sheen + hairline for EVERY app icon (identical path data)
- White glyph ~52% of the tile; cutouts use the tile gradient url(#g)
- Flat single-color glyphs for places/ (Dolphin sidebar rail) and devices/
- Aliases aegis-files / aegis-terminal / aegis-settings / aegis-trash so the
  dock config references the family names instead of stock theme names
"""
import re, os, sys

THEME = "/home/z/my-project/work/aegis-os/debian-live/config/includes.chroot/usr/share/icons/Aegis"
APPS = f"{THEME}/apps/scalable"

# reference squircle template (identical for all icons)
REF = open(f"{APPS}/system-file-manager.svg").read()
BG_PATH = re.search(r'<path d="(M99\.00[^"]+)" fill="url\(#g\)"/>', REF).group(1)
HAIR_PATH = re.search(r'<path d="(M98\.40[^"]+)" fill="none" stroke="#ffffff"', REF).group(1)

OCTOCAT = ("M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 "
           "0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13 "
           "-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66 "
           ".07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15 "
           "-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 "
           "1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 "
           "1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 "
           "1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z")

XMARK = ("M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68"
         "l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z")

def svg(gradient_stops, glyph):
    """Build one icon: squircle bg + sheen + hairline + glyph."""
    g = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in gradient_stops)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
            f'  <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">{g}</linearGradient>\n'
            f'  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">\n'
            f'    <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/>\n'
            f'    <stop offset="0.5" stop-color="#ffffff" stop-opacity="0.03"/>\n'
            f'    <stop offset="1" stop-color="#000000" stop-opacity="0.12"/>\n'
            f'  </linearGradient>\n'
            f' <path d="{BG_PATH}" fill="url(#g)"/>\n'
            f' <path d="{BG_PATH}" fill="url(#sheen)"/>\n'
            f' <path d="{HAIR_PATH}" fill="none" stroke="#ffffff" stroke-opacity="0.14" stroke-width="0.8"/>\n'
            f'{glyph}\n</svg>\n')

# glyph snippets (white primary, url(#g) cutouts) — 100x100 grid, glyph ≈52%
FOLDER = ('<path d="M26 34 q0 -5 5 -5 h11 l5 5 h22 q5 0 5 5 v4 H26 Z" fill="#ffffff" fill-opacity="0.9"/>\n'
          ' <path d="M26 42 h48 q3 0 3 3 v19 q0 5 -5 5 H31 q-5 0 -5 -5 Z" fill="#ffffff"/>')
TERMINAL = ('<rect x="26" y="30" width="48" height="40" rx="7" fill="#ffffff"/>\n'
            ' <path d="M34 41 L43 50 L34 59" fill="none" stroke="url(#g)" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>\n'
            ' <path d="M49 60 H66" fill="none" stroke="url(#g)" stroke-width="5.5" stroke-linecap="round"/>')
GEAR = ('<g fill="#ffffff">'
        + "".join(f'<rect x="46.5" y="26" width="7" height="12" rx="2.2" transform="rotate({a} 50 50)"/>' for a in range(0, 360, 45))
        + '<circle cx="50" cy="50" r="14.5"/></g>\n'
          '<circle cx="50" cy="50" r="6.5" fill="url(#g)"/>')
TRASH = ('<rect x="43" y="24" width="14" height="6" rx="2.4" fill="#ffffff"/>\n'
         '<rect x="30" y="31" width="40" height="5.5" rx="2.75" fill="#ffffff"/>\n'
         '<path d="M33 40 h34 l-2.6 27.5 q-0.5 6 -6.5 6 H42.1 q-6 0 -6.5 -6 Z" fill="#ffffff"/>\n'
         '<path d="M44 46 V67 M56 46 V67" fill="none" stroke="url(#g)" stroke-width="4.5" stroke-linecap="round"/>')
GLOBE = ('<circle cx="50" cy="50" r="23" fill="none" stroke="#ffffff" stroke-width="5.5"/>\n'
         '<ellipse cx="50" cy="50" rx="10.5" ry="23" fill="none" stroke="#ffffff" stroke-width="4"/>\n'
         '<path d="M27 50 H73" fill="none" stroke="#ffffff" stroke-width="4"/>')
ENVELOPE = ('<rect x="24" y="34" width="52" height="32" rx="6" fill="#ffffff"/>\n'
            '<path d="M27 38 L50 55 L73 38" fill="none" stroke="url(#g)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>')
YT = ('<rect x="22" y="32" width="56" height="36" rx="10" fill="#ffffff"/>\n'
      '<path d="M43.5 41 L63.5 50 L43.5 59 Z" fill="url(#g)"/>')
OCTO = f'<path transform="translate(24 24) scale(3.25)" fill="#ffffff" d="{OCTOCAT}"/>'
XMARKSVG = f'<path transform="translate(24 24) scale(2.1667)" fill="#ffffff" d="{XMARK}"/>'
WA = ('<path d="M50 26 a23.5 23.5 0 1 0 11.6 43.9 L74 74 L70.6 62.4 A23.5 23.5 0 0 0 50 26 Z" fill="#ffffff"/>\n'
      '<path d="M41.8 41.2 c-1.8 -2.4 1.2 -4.6 2.9 -3 l3 3 c0.9 0.9 -0.3 2.6 -1.3 3.5 1.4 2.6 3.4 4.6 6 6 0.9 -1 2.6 -2.2 3.5 -1.3 l3 3 c1.6 1.7 -0.6 4.7 -3 2.9 -5.5 -2.4 -11.7 -8.6 -14.1 -14.1 Z" fill="url(#g)"/>')
PHOTOS = ('<rect x="26" y="30" width="48" height="40" rx="7" fill="#ffffff"/>\n'
          '<circle cx="60" cy="41" r="5.5" fill="url(#g)"/>\n'
          '<path d="M27 68 L41 50 L50 59 L57 52 L73 68 L73 69 L27 69 Z" fill="url(#g)"/>')

# per-icon gradient + glyph; None glyph = "recolor accents in existing glyph"
SPECS = {
    "system-file-manager": (((0, "#5B8BFF"), (1, "#1D4FEA")), FOLDER),
    "utilities-terminal":  (((0, "#454C56"), (1, "#191D23")), TERMINAL),
    "preferences-system":  (((0, "#5A636F"), (1, "#2B323B")), GEAR),
    "user-trash":          (((0, "#5A636F"), (1, "#2B323B")), TRASH),
    "web-browser":         (((0, "#2E6BFF"), (1, "#0B42C4")), GLOBE),
    "aegis-gmail":         (((0, "#FF6B6B"), (1, "#E8453C")), ENVELOPE),
    "aegis-youtube":       (((0, "#FF3434"), (1, "#CC0000")), YT),
    "aegis-github":        (((0, "#4A5568"), (1, "#1A202C")), OCTO),
    "aegis-x":             (((0, "#2A2A30"), (1, "#08080A")), XMARKSVG),
    "aegis-whatsapp":      (((0, "#2BE06B"), (1, "#128C7E")), WA),
    "aegis-photos":        (((0, "#3F8CFF"), (1, "#1B5FD1")), PHOTOS),
}

RECOLOR = {  # accent fill -> tile-gradient cutout (keep existing glyph art)
    "aegis-chatgpt": ["#0B7A61"], "aegis-corex": ["#0E8F84"],
    "aegis-calendar": ["#FF5A52", "#2A2C33"], "aegis-gmaps": ["#188038"],
    "aegis-binance": [], "aegis-cloud": [], "aegis-editor": [],
    "aegis-monitor": [], "aegis-music": [], "aegis-store": [],
    "aegis-google": [], "application-x-executable": ["#23262D"],
}

# 1) rewrite/normalize app icons
for name, (stops, glyph) in SPECS.items():
    open(f"{APPS}/{name}.svg", "w").write(svg(stops, glyph))
    print("rewrote", name)

for name, accents in RECOLOR.items():
    p = f"{APPS}/{name}.svg"
    s = open(p).read()
    for a in accents:
        s = s.replace(f'fill="{a}"', 'fill="url(#g)"')
    open(p, "w").write(s)
    print("recolored", name)

# 2) aliases — dock config references the aegis-* family names
ALIAS = {"aegis-files": "system-file-manager", "aegis-terminal": "utilities-terminal",
         "aegis-settings": "preferences-system", "aegis-trash": "user-trash"}
for alias, srcf in ALIAS.items():
    open(f"{APPS}/{alias}.svg", "w").write(open(f"{APPS}/{srcf}.svg").read())
    print("alias", alias, "<-", srcf)

# 3) places/ + devices/ — flat light glyphs for the Files/Settings sidebars
FLAT = "#C9D4E6"
def flat_svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n{body}\n</svg>\n')

ST = f'stroke="{FLAT}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" fill="none"'
PLACES = {
    "user-home": f'<path d="M26 50 L50 28 L74 50" {ST}/><path d="M33 46 V71 H67 V46" {ST}/><rect x="44" y="56" width="12" height="15" rx="2" fill="{FLAT}"/>',
    "folder": f'<path d="M24 36 q0 -4 4 -4 h13 l5 5 h22 q4 0 4 4 v26 q0 4 -4 4 H28 q-4 0 -4 -4 Z" fill="{FLAT}"/>',
    "folder-documents": f'<path d="M24 36 q0 -4 4 -4 h13 l5 5 h22 q4 0 4 4 v26 q0 4 -4 4 H28 q-4 0 -4 -4 Z" fill="{FLAT}"/><path d="M38 44 H62 V64 H38 Z" fill="#12161F"/>',
    "folder-download": f'<path d="M24 36 q0 -4 4 -4 h13 l5 5 h22 q4 0 4 4 v26 q0 4 -4 4 H28 q-4 0 -4 -4 Z" fill="{FLAT}"/><path d="M50 44 V60 M43 53 L50 60 L57 53 M42 65 H58" stroke="#12161F" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
    "folder-pictures": f'<path d="M24 36 q0 -4 4 -4 h13 l5 5 h22 q4 0 4 4 v26 q0 4 -4 4 H28 q-4 0 -4 -4 Z" fill="{FLAT}"/><circle cx="42" cy="48" r="3.5" fill="#12161F"/><path d="M36 62 L46 52 L52 58 L57 53 L64 62 Z" fill="#12161F"/>',
    "user-trash": f'<rect x="42" y="26" width="16" height="7" rx="3" fill="{FLAT}"/><path d="M30 36 H70" {ST}/><path d="M34 42 H66 L63.5 68 q-0.4 5 -5.5 5 H42 q-5.1 0 -5.5 -5 Z" fill="{FLAT}"/>',
    "network-wireless": f'<path d="M28 46 a31 31 0 0 1 44 0" {ST}/><path d="M36 55 a20 20 0 0 1 28 0" {ST}/><path d="M44 63 a10 10 0 0 1 12 0" {ST}/><circle cx="50" cy="71" r="4.5" fill="{FLAT}"/>',
    "preferences-desktop": f'<circle cx="50" cy="50" r="17" {ST}/><path d="M50 33 V24 M50 76 V67 M67 50 H76 M24 50 H33 M62 38 L68 32 M38 68 L32 74 M62 62 L68 68 M38 32 L32 26" {ST}/>',
}
DEVICES = {
    "drive-harddisk": f'<rect x="28" y="34" width="44" height="30" rx="7" {ST}/><circle cx="50" cy="49" r="5" fill="{FLAT}"/><path d="M36 72 H64" {ST}/>',
    "drive-removable-media": f'<rect x="30" y="28" width="40" height="44" rx="7" {ST}/><rect x="38" y="35" width="24" height="12" rx="3" fill="{FLAT}"/><circle cx="50" cy="58" r="5" fill="{FLAT}"/>',
    "media-flash": f'<rect x="34" y="26" width="32" height="48" rx="6" {ST}/><rect x="41" y="33" width="18" height="10" rx="2.5" fill="{FLAT}"/><path d="M42 50 H58 M42 58 H58 M42 66 H50" stroke="{FLAT}" stroke-width="4.5" stroke-linecap="round"/>',
}

os.makedirs(f"{THEME}/places/scalable", exist_ok=True)
os.makedirs(f"{THEME}/devices/scalable", exist_ok=True)
for n, b in PLACES.items():
    open(f"{THEME}/places/scalable/{n}.svg", "w").write(flat_svg(b))
    print("places/", n)
for n, b in DEVICES.items():
    open(f"{THEME}/devices/scalable/{n}.svg", "w").write(flat_svg(b))
    print("devices/", n)

# 4) index.theme — register the new contexts
open(f"{THEME}/index.theme", "w").write("""[Icon Theme]
Name=Aegis
Comment=Aegis OS squircle icon language (proposal plate 09)
Inherits=breeze,hicolor
Directories=apps/scalable,places/scalable,devices/scalable

[apps/scalable]
Size=48
Context=Applications
Type=Scalable
MinSize=8
MaxSize=512

[places/scalable]
Size=48
Context=Places
Type=Scalable
MinSize=8
MaxSize=512

[devices/scalable]
Size=48
Context=Devices
Type=Scalable
MinSize=8
MaxSize=512
""")
print("index.theme updated")
