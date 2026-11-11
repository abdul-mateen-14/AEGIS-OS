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

v0.6.27 geometry — ONE rounded window anatomy (user report: "the header is
smaller than body — they should be at the same place"):

  The Plasma 6.6 v2 engine CLAMPS the theme's Border* to the user's border
  size (decorationtheme.cpp borders(): BorderSize=Normal → clamp 4..6), so
  the declared 12 px side borders were really 6 px while the SVG still drew
  a 12 px frame with a radius-12 arc — the client sat 6 px inside a
  body-coloured strip and the band's arc floated inset from it.
  Fix: kwinrc BorderSize=None (borders 0/44/0/0 — the client is flush with
  the window edge, exactly the AppWindow.qml anatomy), the side/bottom
  frame parts now hide under the client, and the frame is regenerated with
  radius-18 top corners matching the ShapeCorners effect (kwinrc Radius=18)
  so its dark outline hugs the glass arc. FrameSvg part margins come from
  the SVG ELEMENT sizes (KSvg::FrameSvg), so topleft/topright elements are
  18 px wide; the rc Border* values only feed the (now zeroing) clamp.

FrameSvg part ids (decoration-<part>, mask-<part>) follow the aurorae
convention.

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

TOPLEFT_PATH = "M0 18 A18 18 0 0 1 18 0 L18 44 L0 44 Z"
TOPLEFT_ARC = "M0.7 18 A17.3 17.3 0 0 1 18 0.7"
INNER_ARC = "M0.7 18.3 A17.0 17.0 0 0 0 18 42"
BOTTOM_PATH = "M0 0 L18 0 L18 18 A18 18 0 0 1 0 0 Z"
PARTW = 18   # corner-part width = ShapeCorners Radius; also the FrameSvg
             # side margin (hidden under the flush client, but keeps the
             # arc unsquished when FrameSvg derives margins from elements)


def frame_svg(prefix: str, edge: str, band_bottom: str) -> str:
    """Emit one decoration frame SVG (active or inactive variant)."""
    p = prefix  # "" for active, "inactive-" for the unfocused frame
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <g id="decoration-{p}topleft">
    <path d="{TOPLEFT_PATH}" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
<path d="{TOPLEFT_ARC}" fill="none" stroke="{edge}" stroke-width="1"/>
<path d="M0 43 L18 43" stroke="{band_bottom}" stroke-width="1"/>
<path d="{INNER_ARC}" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8" opacity="0.5"/>
  </g>

  <g id="decoration-{p}top">
    <rect x="0" y="0" width="18" height="44" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
    <rect x="0" y="0" width="18" height="1" fill="{edge}"/>
    <rect x="0" y="43" width="18" height="1" fill="{band_bottom}"/>
  </g>

  <g id="decoration-{p}topright">
    <g transform="translate(18,0) scale(-1,1)">
      <path d="{TOPLEFT_PATH}" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
<path d="{TOPLEFT_ARC}" fill="none" stroke="{edge}" stroke-width="1"/>
<path d="M0 43 L18 43" stroke="{band_bottom}" stroke-width="1"/>
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
    <g transform="translate(18,0) scale(-1,1)">
      <path d="{BOTTOM_PATH}" fill="{BODY}"/>
    </g>
    <path d="M11.2 0 A11.2 11.2 0 0 1 0 11.2" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8"/>
  </g>
  <g id="decoration-{p}center">
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
  </g>

  <g id="mask-{p}topleft"><path d="{TOPLEFT_PATH}" fill="#000"/></g>
  <g id="mask-{p}top"><rect width="18" height="44" fill="#000"/></g>
  <g id="mask-{p}topright"><g transform="translate(18,0) scale(-1,1)"><path d="{TOPLEFT_PATH}" fill="#000"/></g></g>
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
