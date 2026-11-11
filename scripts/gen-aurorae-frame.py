#!/usr/bin/env python3
"""T5 — regenerate the AegisLights Aurorae decoration frame SVGs at the
shell's glass recipe.

The old frame painted the 44 px title band with a light two-stop gradient
(#343740 @0.94 -> #22242B @0.96). Measured on v0.6.20: the terminal band
read (44,47,55) -> (35,38,45) while the Files glass band (GlassPanel +
Tokens.glassTint over the same wallpaper) read a flat (19,19,23) — the
"two anatomies" bug this fix closes.

The shell recipe (Tokens.qml / GlassPanel.qml, dark rung):
  fill    rgba(16,16,18, 0.52)   glassTint
  border  white @ 0.14           glassBorder — 1 px, never scales
  highlight white @ 0.10 at y=1  glassHighlight (kept via the inner strokes)

Painting the aurorae band with the SAME tint over the SAME wallpaper makes
02-files and 03-terminal band pixels agree, which the T7 capture assert
checks numerically.

Geometry (corner radius 12, band 44, borders 12) is preserved verbatim from
the hand-drawn v0.6.20 SVGs; only fills/strokes change. FrameSvg part ids
(decoration-<part>, mask-<part>) follow the aurorae convention.

Run from the repo root; writes into the includes tree and gzips in place.
"""
import gzip
import os

OUT = os.path.join(os.path.dirname(__file__), "..",
                   "debian-live/config/includes.chroot/usr/share/aurorae"
                   "/themes/AegisLights")

# shell dark-rung glass recipe
GLASS = "#101012"        # rgb(16,16,18) = Tokens.glassTint color
GLASS_OP = "0.52"        # Tokens.glassTint alpha
BODY = "#17181D"         # opaque app body (AppWindow.qml body rectangle)

# hairlines — active vs inactive, shell border white 0.14 dimmed when unfocused
EDGE_ACTIVE = "#ffffff24"      # white @ 0.14 = Tokens.glassBorder
EDGE_INACTIVE = "#ffffff0f"    # white @ ~0.06
EDGE_INNER = "#ffffff0d"       # inner corner strokes (kept from v0.6.20)

TOPLEFT_PATH = "M0 12 A12 12 0 0 1 12 0 L12 44 L0 44 Z"
TOPLEFT_ARC = "M0.7 12 A11.3 11.3 0 0 1 12 0.7"
INNER_ARC = "M0.7 12.3 A10.7 10.7 0 0 0 12 42"
BOTTOM_PATH = "M0 0 L12 0 L12 12 A12 12 0 0 1 0 0 Z"


def frame_svg(prefix: str, edge: str, band_bottom: str) -> str:
    """Emit one decoration frame SVG (active or inactive variant)."""
    p = prefix  # "" for active, "inactive-" for the unfocused frame
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <g id="decoration-{p}topleft">
    <path d="{TOPLEFT_PATH}" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
<path d="{TOPLEFT_ARC}" fill="none" stroke="{edge}" stroke-width="1"/>
<path d="M0 43 L12 43" stroke="{band_bottom}" stroke-width="1"/>
<path d="{INNER_ARC}" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8" opacity="0.5"/>
  </g>

  <g id="decoration-{p}top">
    <rect x="0" y="0" width="12" height="44" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
    <rect x="0" y="0" width="12" height="1" fill="{edge}"/>
    <rect x="0" y="43" width="12" height="1" fill="{band_bottom}"/>
  </g>

  <g id="decoration-{p}topright">
    <g transform="translate(12,0) scale(-1,1)">
      <path d="{TOPLEFT_PATH}" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
<path d="{TOPLEFT_ARC}" fill="none" stroke="{edge}" stroke-width="1"/>
<path d="M0 43 L12 43" stroke="{band_bottom}" stroke-width="1"/>
<path d="{INNER_ARC}" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8" opacity="0.5"/>
    </g>
  </g>

  <g id="decoration-{p}left">
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
    <rect x="0" y="0" width="1" height="12" fill="{EDGE_INNER}"/>
  </g>
  <g id="decoration-{p}right">
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
    <rect x="11" y="0" width="1" height="12" fill="{EDGE_INNER}"/>
  </g>
  <g id="decoration-{p}bottomleft">
    <path d="{BOTTOM_PATH}" fill="{BODY}"/>
    <path d="M0.8 0 A11.2 11.2 0 0 0 12 11.2" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8"/>
  </g>
  <g id="decoration-{p}bottom">
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
    <rect x="0" y="11" width="12" height="1" fill="{EDGE_INNER}"/>
  </g>
  <g id="decoration-{p}bottomright">
    <g transform="translate(12,0) scale(-1,1)">
      <path d="{BOTTOM_PATH}" fill="{BODY}"/>
    </g>
    <path d="M11.2 0 A11.2 11.2 0 0 1 0 11.2" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8"/>
  </g>
  <g id="decoration-{p}center">
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
  </g>

  <g id="mask-{p}topleft"><path d="{TOPLEFT_PATH}" fill="#000"/></g>
  <g id="mask-{p}top"><rect width="12" height="44" fill="#000"/></g>
  <g id="mask-{p}topright"><g transform="translate(12,0) scale(-1,1)"><path d="{TOPLEFT_PATH}" fill="#000"/></g></g>
  <g id="mask-{p}left"><rect width="12" height="12" fill="#000"/></g>
  <g id="mask-{p}right"><rect width="12" height="12" fill="#000"/></g>
  <g id="mask-{p}bottomleft"><path d="{BOTTOM_PATH}" fill="#000"/></g>
  <g id="mask-{p}bottom"><rect width="12" height="12" fill="#000"/></g>
  <g id="mask-{p}bottomright"><path d="{BOTTOM_PATH}" fill="#000"/></g>
  <g id="mask-{p}center"><rect width="12" height="12" fill="#000"/></g>
</svg>
'''


FRAMES = {
    "decoration.svgz": frame_svg("", EDGE_ACTIVE, EDGE_ACTIVE),
    "decoration-inactive.svgz": frame_svg("inactive-", EDGE_INACTIVE,
                                          EDGE_INACTIVE),
}

for name, svg in FRAMES.items():
    path = os.path.join(OUT, name)
    with open(path, "wb") as fh:
        fh.write(gzip.compress(svg.encode("utf-8"), 9))
    print("wrote", os.path.relpath(path))
