#!/usr/bin/env python3
"""W10 — regenerate the AegisLights Aurorae button SVGs at 12 px optical.

The old buttons were drawn on a 20x20 canvas (r=6 circle = 12 px optical at
ButtonWidth=20). With the W10 ruling (ButtonWidth=12) a 20x20 SVG scales to
0.6 and the circle shrinks to 7.2 px — the exact "size one" bug. These are
drawn 1:1 on a 12x12 canvas: 12 px circle, 1 px inset border, hover glyphs
in the shell's light style.

T6 — the shell's Qt.lighter(hue, 3.4) clamps HSV value at 1.0 for the close
and minimize hues (V already ~= 1.0), which renders the hover glyph at the
SAME color as the circle — i.e. invisible. Both TrafficLights.qml and this
generator therefore use an explicit hue-tinted white per button: same hue,
saturation x 0.15, value 1.0 — the "hue lift, not white" intent that the
factor-3.4 formula was reaching for, visible on all three hues.

Group IDs follow the Aurorae convention the theme already used:
  active-center, hover-center, pressed-center,
  deactivated-center, inactive-center, hover-inactive-center,
  pressed-inactive-center

Run from the repo root; writes into the includes tree and gzips in place.
"""
import gzip
import os

OUT = os.path.join(os.path.dirname(__file__), "..",
                   "debian-live/config/includes.chroot/usr/share/aurorae"
                   "/themes/AegisLights")

# hue, border(=hue*0.6), pressed fill(=hue*0.6) — same palette the 20px SVGs used
# tint = hover glyph color: hue-tinted white (S*0.15, V=1), shared with TrafficLights.qml
BUTTONS = {
    "close":    {"hue": "#FF5F57", "tint": "#FFE7E6", "border": "#993934", "press": "#993934",
                 "glyph": '<path d="M3.6 3.6 L8.4 8.4 M8.4 3.6 L3.6 8.4" '
                          'stroke="{c}" stroke-width="1.1" stroke-linecap="round"/>'},
    "minimize": {"hue": "#FEBC2E", "tint": "#FFF5E0", "border": "#98711B", "press": "#98711B",
                 "glyph": '<path d="M3.7 6 L8.3 6" '
                          'stroke="{c}" stroke-width="1.1" stroke-linecap="round"/>'},
    "maximize": {"hue": "#28C840", "tint": "#E0FFE5", "border": "#187826", "press": "#187826",
                 "glyph": '<path d="M3.7 6 L8.3 6 M6 3.7 L6 8.3" '
                          'stroke="{c}" stroke-width="1.1" stroke-linecap="round"/>'},
    "restore":  {"hue": "#28C840", "tint": "#E0FFE5", "border": "#187826", "press": "#187826",
                 "glyph": '<path d="M3.9 8.1 L8.1 3.9 M3.9 8.1 L3.9 5.7 '
                          'M3.9 8.1 L6.3 8.1 M8.1 3.9 L8.1 6.3 '
                          'M8.1 3.9 L5.7 3.9" '
                          'stroke="{c}" stroke-width="0.9" '
                          'stroke-linecap="round" stroke-linejoin="round"/>'},
}

# inactive rungs — grey, 50% — lifted verbatim from the old SVGs
INACTIVE = {
    "deactivated": {"fill": "#8A8F9C", "fill_op": "0.5",
                    "border": "#6A6E78", "border_op": "0.45"},
    "inactive":    {"fill": "#9BA1AD", "fill_op": "0.5",
                    "border": "#71767F", "border_op": "0.45"},
    "hover-inactive": {"fill": "#B7BCC6", "fill_op": "0.5",
                       "border": "#8A8E96", "border_op": "0.45"},
    "pressed-inactive": {"fill": "#71767F", "fill_op": None,
                         "border": None, "border_op": None},
}
INACTIVE_GLYPH_STROKE = "#45494f"


def svg(name):
    b = BUTTONS[name]
    hue, border = b["hue"], b["border"]
    lines = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12">',
        # active
        f'  <g id="active-center"><circle cx="6" cy="6" r="6" fill="{hue}" '
        f'fill-opacity="1"/><circle cx="6" cy="6" r="5.5" fill="none" '
        f'stroke="{border}" stroke-opacity="0.8" stroke-width="1"/></g>',
        # hover — light glyph in the button's hue-tinted white (T6, shared
        # with TrafficLights.qml's hover Text color)
        f'  <g id="hover-center"><circle cx="6" cy="6" r="6" fill="{hue}" '
        f'fill-opacity="1"/><circle cx="6" cy="6" r="5.5" fill="none" '
        f'stroke="{border}" stroke-opacity="0.8" stroke-width="1"/>'
        f'{b["glyph"].format(c=b["tint"])}</g>',
        # pressed — darker fill + glyph
        f'  <g id="pressed-center"><circle cx="6" cy="6" r="6" '
        f'fill="{b["press"]}"/>{b["glyph"].format(c="#FFFFFF")}</g>',
    ]
    for key, spec in INACTIVE.items():
        gid = f"{key}-center"
        glyph = b["glyph"].format(c=INACTIVE_GLYPH_STROKE) if key.startswith(
            ("hover", "pressed")) else ""
        border_part = ""
        if spec["border"]:
            border_part = (f'<circle cx="6" cy="6" r="5.5" fill="none" '
                           f'stroke="{spec["border"]}" '
                           f'stroke-opacity="{spec["border_op"]}" '
                           f'stroke-width="1"/>')
        fill_op = f' fill-opacity="{spec["fill_op"]}"' if spec["fill_op"] else ""
        lines.append(
            f'  <g id="{gid}"><circle cx="6" cy="6" r="6" fill="{spec["fill"]}"'
            f'{fill_op}/>{border_part}{glyph}</g>')
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


for name in BUTTONS:
    path = os.path.join(OUT, f"{name}.svgz")
    with open(path, "wb") as fh:
        fh.write(gzip.compress(svg(name).encode("utf-8"), 9))
    print("wrote", os.path.relpath(path))
