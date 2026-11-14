#!/usr/bin/env python3
"""T5 + T16-W53§5.3 — regenerate the AegisLights Aurorae decoration frame
SVGs at the shell's glass recipe, now WITH the Lane B shadow ring.

History:
  T5/v0.6.20 — band painted at the shell glass tint (kills the
    "two anatomies" bug: the terminal band must measure like the Files
    glass band; the T7 capture assert checks it numerically).
  v0.6.27 — ONE rounded window anatomy: radius-18 top arcs matching the
    ShapeCorners effect (kwinrc Radius=18).
  T16 (review round 7 §5.3.1) — the theme declares real 4 px resize
    borders (W44) and now carries a two-layer shadow ring: ambient
    (spread 20 px, alpha ~0.22) + key (offset-y 4 px, blur 32 px,
    alpha ~0.28), approximated as one gradient band per edge —
    24 px left/right, 20 px top, 36 px bottom (key offset+blur).

How the aurorae v2 shadow works (verified against
invent.kde.org/plasma/aurorae v2/decoration.cpp @ KWin 6.6):

  updateShadow(): image = frame grown by the theme's [Layout] Padding*;
  paintFrame into it; the interior (window rect) is erased with
  DestinationOut; the remaining RING is the DecorationShadow.
  paint(): paints the same frame at offset (-padding.left, -padding.top)
  — so the window-visible glass content must sit at +padding inside the
  SVG, with the shadow ring painted in the outer band.
  updateBlur(): blur mask = the mask-* elements translated back by
  (-padding + 1) — the mask elements carry the window shape at +padding.
  Maximized windows: prefix "decoration-maximized" if the theme ships
  it (else the shifted "decoration" prefix would misplace the band) —
  we ship maximized elements at the OLD unshifted geometry (NoBorder:
  only what painted before paints again, byte-identical look).

FrameSvg part margins come from the SVG ELEMENT sizes, so the element
sizes below MUST match the rc Padding* values (24/20/24/36).

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

# §5.3.1 shadow ring — margins MUST equal the rc [Layout] Padding* values
PAD_L = 24
PAD_T = 20
PAD_B = 36
RING_IN = "0.28"     # alpha at the window edge (ambient+key combined)
RING_IN_BOTTOM = "0.32"
RING_OUT = "0"

TOPLEFT_PATH = "M0 18 A18 18 0 0 1 18 0 L18 44 L0 44 Z"
TOPLEFT_ARC = "M0.7 18 A17.3 17.3 0 0 1 18 0.7"
INNER_ARC = "M0.7 18.3 A17.0 17.0 0 0 0 18 42"
BOTTOM_PATH = "M0 0 L18 0 L18 18 A18 18 0 0 1 0 0 Z"
PARTW = 18   # corner-part width = ShapeCorners Radius


def frame_svg(prefix: str, edge: str, band_bottom: str) -> str:
    """Emit one SHADOWED decoration frame SVG (active or inactive).

    Glass content sits at (+PAD_L, +PAD_T) inside every element; the
    outer band carries the shadow ring gradient. Element sizes match the
    rc Padding* (FrameSvg derives its stretch margins from elements).
    """
    p = prefix  # "" for active, "inactive-" for the unfocused frame
    cx, cy = PAD_L, PAD_T  # content origin shift in the corner elements
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <defs>
    <linearGradient id="ringsh-{p}l" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="{RING_OUT}"/>
      <stop offset="1" stop-color="#000" stop-opacity="{RING_IN}"/>
    </linearGradient>
    <linearGradient id="ringsh-{p}r" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="{RING_IN}"/>
      <stop offset="1" stop-color="#000" stop-opacity="{RING_OUT}"/>
    </linearGradient>
    <linearGradient id="ringsh-{p}t" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#000" stop-opacity="{RING_OUT}"/>
      <stop offset="1" stop-color="#000" stop-opacity="{RING_IN}"/>
    </linearGradient>
    <linearGradient id="ringsh-{p}b" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#000" stop-opacity="{RING_IN_BOTTOM}"/>
      <stop offset="1" stop-color="#000" stop-opacity="{RING_OUT}"/>
    </linearGradient>
    <radialGradient id="ringcorner-{p}tl" cx="1" cy="1" r="1">
      <stop offset="0" stop-color="#000" stop-opacity="{RING_IN}"/>
      <stop offset="1" stop-color="#000" stop-opacity="{RING_OUT}"/>
    </radialGradient>
  </defs>

  <g id="decoration-{p}topleft">
    <rect x="0" y="0" width="{PAD_L}" height="{PAD_T}" fill="url(#ringcorner-{p}tl)"/>
    <rect x="0" y="{PAD_T}" width="{PAD_L}" height="44" fill="url(#ringsh-{p}l)"/>
    <rect x="{PAD_L}" y="0" width="{PARTW}" height="{PAD_T}" fill="url(#ringsh-{p}t)"/>
    <g transform="translate({cx},{cy})">
      <path d="{TOPLEFT_PATH}" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
      <path d="{TOPLEFT_ARC}" fill="none" stroke="{edge}" stroke-width="1"/>
      <path d="M0 43 L18 43" stroke="{band_bottom}" stroke-width="1"/>
      <path d="{INNER_ARC}" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8" opacity="0.5"/>
    </g>
  </g>

  <g id="decoration-{p}top">
    <rect x="0" y="0" width="18" height="{PAD_T}" fill="url(#ringsh-{p}t)"/>
    <g transform="translate(0,{PAD_T})">
      <rect x="0" y="0" width="18" height="44" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
      <rect x="0" y="0" width="18" height="1" fill="{edge}"/>
      <rect x="0" y="43" width="18" height="1" fill="{band_bottom}"/>
    </g>
  </g>

  <g id="decoration-{p}topright">
    <g transform="translate({PAD_L + PARTW},0) scale(-1,1)">
      <rect x="0" y="0" width="{PAD_L}" height="{PAD_T}" fill="url(#ringcorner-{p}tl)"/>
      <rect x="0" y="{PAD_T}" width="{PAD_L}" height="44" fill="url(#ringsh-{p}l)"/>
      <rect x="{PAD_L}" y="0" width="{PARTW}" height="{PAD_T}" fill="url(#ringsh-{p}t)"/>
      <g transform="translate({cx},{cy})">
        <path d="{TOPLEFT_PATH}" fill="{GLASS}" fill-opacity="{GLASS_OP}"/>
        <path d="{TOPLEFT_ARC}" fill="none" stroke="{edge}" stroke-width="1"/>
        <path d="M0 43 L18 43" stroke="{band_bottom}" stroke-width="1"/>
        <path d="{INNER_ARC}" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8" opacity="0.5"/>
      </g>
    </g>
  </g>

  <g id="decoration-{p}left">
    <rect x="0" y="0" width="{PAD_L}" height="12" fill="url(#ringsh-{p}l)"/>
    <g transform="translate({PAD_L},0)">
      <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
      <rect x="0" y="0" width="1" height="12" fill="{EDGE_INNER}"/>
    </g>
  </g>
  <g id="decoration-{p}right">
    <g transform="translate(0,0)">
      <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
      <rect x="11" y="0" width="1" height="12" fill="{EDGE_INNER}"/>
    </g>
    <rect x="12" y="0" width="{PAD_L}" height="12" fill="url(#ringsh-{p}r)"/>
  </g>
  <g id="decoration-{p}bottomleft">
    <rect x="0" y="18" width="{PAD_L + PARTW}" height="{PAD_B}" fill="url(#ringsh-{p}b)"/>
    <rect x="0" y="0" width="{PAD_L}" height="18" fill="url(#ringsh-{p}l)"/>
    <g transform="translate({PAD_L},0)">
      <path d="{BOTTOM_PATH}" fill="{BODY}"/>
      <path d="M0.8 0 A11.2 11.2 0 0 0 12 11.2" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8"/>
    </g>
  </g>
  <g id="decoration-{p}bottom">
    <rect x="0" y="18" width="12" height="{PAD_B}" fill="url(#ringsh-{p}b)"/>
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
  </g>
  <g id="decoration-{p}bottomright">
    <rect x="18" y="0" width="{PAD_L}" height="18" fill="url(#ringsh-{p}r)"/>
    <rect x="0" y="18" width="{PAD_L + PARTW}" height="{PAD_B}" fill="url(#ringsh-{p}b)"/>
    <g transform="translate({PARTW},0) scale(-1,1)">
      <path d="{BOTTOM_PATH}" fill="{BODY}"/>
      <path d="M0.8 0 A11.2 11.2 0 0 0 12 11.2" fill="none" stroke="{EDGE_INNER}" stroke-width="0.8"/>
    </g>
  </g>
  <g id="decoration-{p}center">
    <rect x="0" y="0" width="12" height="12" fill="{BODY}"/>
  </g>

  <g id="mask-{p}topleft"><g transform="translate({PAD_L},{PAD_T})"><path d="{TOPLEFT_PATH}" fill="#000"/></g></g>
  <g id="mask-{p}top"><rect x="0" y="{PAD_T}" width="18" height="44" fill="#000"/></g>
  <g id="mask-{p}topright"><g transform="translate({PAD_L + PARTW},0) scale(-1,1)"><g transform="translate({PAD_L},{PAD_T})"><path d="{TOPLEFT_PATH}" fill="#000"/></g></g></g>
  <g id="mask-{p}left"><rect x="{PAD_L}" y="0" width="12" height="12" fill="#000"/></g>
  <g id="mask-{p}right"><rect x="0" y="0" width="12" height="12" fill="#000"/></g>
  <g id="mask-{p}bottomleft"><g transform="translate({PAD_L},0)"><path d="{BOTTOM_PATH}" fill="#000"/></g></g>
  <g id="mask-{p}bottom"><rect x="0" y="0" width="12" height="18" fill="#000"/></g>
  <g id="mask-{p}bottomright"><g transform="translate(0,0)"><path d="{BOTTOM_PATH}" fill="#000"/></g></g>
  <g id="mask-{p}center"><rect width="12" height="12" fill="#000"/></g>
</svg>
'''


def maximized_svg(prefix: str, edge: str, band_bottom: str) -> str:
    """Emit the UNshifted frame (prefix decoration-maximized-): maximized
    windows paint at (0,0) with NoBorder — the v0.6.27 geometry, byte-
    identical look, no shadow ring."""
    p = prefix
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
    "decoration-maximized.svgz": maximized_svg("maximized-", EDGE_ACTIVE,
                                               EDGE_ACTIVE),
}

for name, svg in FRAMES.items():
    path = os.path.join(OUT, name)
    with open(path, "wb") as fh:
        fh.write(gzip.compress(svg.encode("utf-8"), 9))
    print("wrote", os.path.relpath(path))
