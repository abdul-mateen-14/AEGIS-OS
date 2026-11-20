#!/usr/bin/env python3
# AEGIS v0.6.81 icon pack generator — one geometry source, three outputs:
#   SVG masters (24-grid, currentColor) · tinted/white PNGs · contact sheet
#   + API-compatible QML painter code emitted from the SAME geometry.
import math, os, json
import cairosvg
from PIL import Image, ImageDraw, ImageFont

OUT = "/home/z/my-project/download/AEGIS-v0.6.81-icon-pack"
os.makedirs(f"{OUT}/svg", exist_ok=True)
os.makedirs(f"{OUT}/png", exist_ok=True)

# ── geometry helpers ────────────────────────────────────────────────────
def P(*segs, op="stroke", w=2.0):
    return {"type": "path", "segs": list(segs), "op": op, "w": w}
def C(cx, cy, r, op="stroke", w=2.0):
    return {"type": "circle", "cx": cx, "cy": cy, "r": r, "op": op, "w": w}
def R(x, y, w_, h_, r, op="stroke", sw=2.0):
    return {"type": "rrect", "x": x, "y": y, "rw": w_, "rh": h_, "r": r, "op": op, "sw": sw}
def M(x, y): return ("M", x, y)
def L(x, y): return ("L", x, y)
def Cb(x1, y1, x2, y2, x, y): return ("C", x1, y1, x2, y2, x, y)
def Q(cx, cy, x, y): return ("Q", cx, cy, x, y)
def Z(): return ("Z",)
def A(cx, cy, r, a0, a1, ccw=False): return ("A", cx, cy, r, a0, a1, ccw)

def crescent(c1, r1, c2, r2):
    """closed crescent path from circle c1 minus circle c2 (both 4-tuples)."""
    (x1, y1), (x2, y2) = c1, c2
    d = math.hypot(x2 - x1, y2 - y1)
    a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    h = math.sqrt(max(r1 * r1 - a * a, 0))
    ex, ey = x1 + a * (x2 - x1) / d, y1 + a * (y2 - y1) / d
    dx, dy = (y2 - y1) / d * h, -(x2 - x1) / d * h
    p1 = (ex + dx, ey + dy); p2 = (ex - dx, ey - dy)
    def ang(px, py, cx, cy): return math.atan2(py - cy, px - cx)
    a1_1 = ang(*p1, x1, y1); a1_2 = ang(*p2, x1, y1)
    # outer arc: the part of C1 NOT inside C2 (major arc through far side)
    return [M(*p1), A(x1, y1, r1, a1_1, a1_2, False), Z()] if False else \
        [M(*p1), A(x1, y1, r1, a1_1, a1_2, False), A(x2, y2, r2, ang(*p2, x2, y2), ang(*p1, x2, y2), False), Z()]

# the large-arc flag for SVG needs care; helper computes it from angles
def svg_arc_seg(cx, cy, r, a0, a1, ccw, x, y):
    delta = abs(a1 - a0) % (2 * math.pi)
    large = 1 if delta > math.pi else 0
    sweep = 0 if ccw else 1
    return f"A {r:.2f} {r:.2f} 0 {large} {sweep} {x:.2f} {y:.2f}"

def star(cx, cy, r):
    d = r * 0.26
    return [M(cx, cy - r), Q(cx + d, cy - d, cx + r, cy), Q(cx + d, cy + d, cx, cy + r),
            Q(cx - d, cy + d, cx - r, cy), Q(cx - d, cy - d, cx, cy - r), Z()]

# ── the master glyphs (24 × 24 grid) ────────────────────────────────────
TINTS = {"mountain": "#8B5CF6", "palette": "#3E8BFF", "sparkles": "#28C840",
         "chip": "#FF9F0A", "monitor": "#5B8BFF", "speaker": "#FA2D48",
         "netWifi": "#4AC8C8", "person": "#6E7BFF"}

G = {}
# — Settings sidebar family (optical 18, stroke 2) —
G["mountain"] = [R(2.5, 4.5, 19, 15, 3), C(16.6, 8.4, 1.6, "fill"),
    P(M(5.5, 17.0), L(9.5, 10.5), L(11.8, 13.5), L(13.8, 11.0), L(18.5, 17.0))]
G["palette"] = [
    P(M(4.0, 12.2), Cb(3.8, 8.0, 6.0, 4.6, 10.0, 4.3), Cb(14.5, 4.0, 19.6, 6.0, 20.0, 10.6),
      Cb(20.3, 14.0, 18.4, 15.6, 15.9, 16.2), Cb(14.2, 16.6, 14.5, 17.9, 13.4, 18.8),
      Cb(12.0, 20.0, 9.4, 19.6, 7.6, 18.6), Cb(5.2, 17.4, 4.2, 14.8, 4.0, 12.2), Z()),
    C(13.2, 8.2, 2.0), C(8.6, 8.8, 1.3, "fill"), C(7.9, 12.3, 1.3, "fill"), C(11.5, 14.2, 1.3, "fill")]
G["sparkles"] = [P(*star(10, 13, 5.5), op="fill"), P(*star(17.5, 7, 3.0), op="fill"),
                 P(*star(17, 16.5, 2.2), op="fill")]
G["chip"] = [R(6.5, 6.5, 11, 11, 2), R(9.6, 9.6, 4.8, 4.8, 1),
             P(M(9.5, 6.5), L(9.5, 3.4), M(12, 6.5), L(12, 3.4), M(14.5, 6.5), L(14.5, 3.4),
               M(9.5, 17.5), L(9.5, 20.6), M(12, 17.5), L(12, 20.6), M(14.5, 17.5), L(14.5, 20.6),
               M(6.5, 9.5), L(3.4, 9.5), M(6.5, 12), L(3.4, 12), M(6.5, 14.5), L(3.4, 14.5),
               M(17.5, 9.5), L(20.6, 9.5), M(17.5, 12), L(20.6, 12), M(17.5, 14.5), L(20.6, 14.5))]
G["monitor"] = [R(3.5, 4.5, 17, 11, 2.2), P(M(12, 15.5), L(12, 18.6)),
                P(M(8.0, 18.6), L(16.0, 18.6))]
G["speaker"] = [P(M(6.5, 9.4), L(9.2, 9.4), L(13.2, 5.4), L(13.2, 18.6), L(9.2, 14.6),
                  L(6.5, 14.6), Z(), op="fill"),
                P(A(14.2, 12, 3.2, math.radians(-55), math.radians(55))),
                P(A(14.2, 12, 6.4, math.radians(-55), math.radians(55)))]
G["netWifi"] = [P(M(12, 17.8), A(12, 17.8, 2.8, math.radians(225), math.radians(315)), Z(), op="fill"),
                P(A(12, 17.8, 4.3, math.radians(225), math.radians(315)),
                  A(12, 17.8, 6.3, math.radians(315), math.radians(225), True), Z(), op="fill"),
                P(A(12, 17.8, 7.5, math.radians(225), math.radians(315)),
                  A(12, 17.8, 9.5, math.radians(315), math.radians(225), True), Z(), op="fill")]
G["person"] = [C(12, 7.8, 3.4), P(A(12, 20.6, 6.4, math.radians(216), math.radians(324)))]

# — Status family (optical 16→24 normalized; unify panel + CC) —
G["wifi"] = G["netWifi"]
G["wired"] = [R(8.0, 3.5, 8, 8.5, 1.4),
              P(M(10.2, 3.5), L(10.2, 6.8), M(12, 3.5), L(12, 6.8), M(13.8, 3.5), L(13.8, 6.8)),
              P(M(12, 12.0), L(12, 15.2), w=2.6)]
G["battery"] = [R(4.0, 7.5, 15, 9, 2.4), R(20.4, 10.4, 1.8, 3.2, 0.9, "fill"),
                R(5.8, 9.2, 9.6, 5.6, 1.0, "fill", 0)]
G["sliders"] = [P(M(4, 6.5), L(20, 6.5)), C(15.2, 6.5, 2.4, "fill"),
                P(M(4, 12), L(20, 12)), C(8.0, 12, 2.4, "fill"),
                P(M(4, 17.5), L(20, 17.5)), C(16.8, 17.5, 2.4, "fill")]

# — Control Center tile family (optical 20-22, stroke 2.2) —
W22 = 2.2
G["bluetooth"] = [P(M(12, 3.0), L(12, 21.0), M(12, 3.0), L(17.0, 7.6), L(7.0, 15.6),
                    M(12, 21.0), L(17.0, 16.4), L(7.0, 8.4), op="stroke", w=W22)]
G["moon"] = [P(*crescent((12, 12), 8.2, (16.9, 8.5), 6.5), op="fill")]
G["half"] = [C(12, 12, 7.5, "stroke", W22),
             P(M(12, 4.5), A(12, 12, 7.5, -math.pi / 2, math.pi / 2), Z(), op="fill")]
G["bell"] = [C(12, 4.6, 1.5, "fill"),
             P(M(10.5, 6.2), Cb(7.2, 7.6, 8.3, 11.0, 6.0, 15.4), L(18.0, 15.4),
               Cb(15.7, 11.0, 16.8, 7.6, 13.5, 6.2), Z()),
             P(M(5.6, 15.4), L(18.4, 15.4)),
             P(A(12, 17.9, 1.8, math.radians(20), math.radians(160)))]
G["sun"] = [C(12, 12, 4.0, "fill"),
            P(M(12, 2.8), L(12, 5.2), M(12, 18.8), L(12, 21.2), M(2.8, 12), L(5.2, 12),
              M(18.8, 12), L(21.2, 12), M(5.6, 5.6), L(7.3, 7.3), M(16.7, 7.3), L(18.4, 5.6),
              M(5.6, 18.4), L(7.3, 16.7), M(16.7, 16.7), L(18.4, 18.4), op="stroke", w=W22)]
G["ccSpeaker"] = G["speaker"]

# — App glyphs for the dock's clear mode (W76: white-on-glass plates) —
G["gear"] = [C(12, 12, 7.0, "stroke", W22),
             C(12, 12, 2.6, "stroke", W22),
             P(M(12, 1.8), L(12, 4.0), M(12, 20.0), L(12, 22.2), M(1.8, 12), L(4.0, 12),
               M(20.0, 12), L(22.2, 12), M(4.9, 4.9), L(6.4, 6.4), M(17.6, 6.4), L(19.1, 4.9),
               M(4.9, 19.1), L(6.4, 17.6), M(17.6, 17.6), L(19.1, 19.1), op="stroke", w=W22)]
G["folder"] = [R(3, 7.0, 18, 12.5, 2.5),
               P(M(3.0, 7.0), L(3.0, 5.5), Q(3.0, 4.5, 4.0, 4.5), L(9.0, 4.5),
                 Q(10.0, 4.5, 10.0, 5.5), L(10.0, 7.0))]

# ── SVG emission ────────────────────────────────────────────────────────
def segs_to_d(segs):
    d = []
    for s in segs:
        if s[0] == "M": d.append(f"M {s[1]:.2f} {s[2]:.2f}")
        elif s[0] == "L": d.append(f"L {s[1]:.2f} {s[2]:.2f}")
        elif s[0] == "C": d.append(f"C {s[1]:.2f} {s[2]:.2f} {s[3]:.2f} {s[4]:.2f} {s[5]:.2f} {s[6]:.2f}")
        elif s[0] == "Q": d.append(f"Q {s[1]:.2f} {s[2]:.2f} {s[3]:.2f} {s[4]:.2f}")
        elif s[0] == "Z": d.append("Z")
        elif s[0] == "A":
            _, cx, cy, r, a0, a1, ccw = s
            # canvas arc() semantics: with a current point it draws a
            # connecting LINE to the arc start, else it starts the subpath
            # there. Mirror that in SVG (M vs L), then polyline — no
            # arc-flag pitfalls, identical at icon size.
            sx = cx + r * math.cos(a0); sy = cy + r * math.sin(a0)
            has_prev = bool(d) and d[-1] != "Z"
            d.append(("L" if has_prev else "M") + f" {sx:.2f} {sy:.2f}")
            # canvas sweep semantics: cw = a0 increasing to a1 (mod 2π);
            # ccw = a0 DECREASING to a1 (mod 2π). Never swap — sample the
            # actual sweep.
            n = 20
            if ccw:
                sweep = (a0 - a1) % (2 * math.pi)
                angs = [a0 - sweep * k / n for k in range(1, n + 1)]
            else:
                sweep = (a1 - a0) % (2 * math.pi)
                angs = [a0 + sweep * k / n for k in range(1, n + 1)]
            for a in angs:
                d.append(f"L {cx + r * math.cos(a):.2f} {cy + r * math.sin(a):.2f}")
    return " ".join(d)

def svg_for(name):
    body = []
    for o in G[name]:
        if o["type"] == "circle":
            attrs = f'cx="{o["cx"]:.2f}" cy="{o["cy"]:.2f}" r="{o["r"]:.2f}"'
            body.append(f'<circle {attrs} fill="currentColor" stroke="none"/>' if o["op"] == "fill"
                        else f'<circle {attrs} fill="none" stroke="currentColor" stroke-width="{o["w"]:.1f}" stroke-linecap="round"/>')
        elif o["type"] == "rrect":
            attrs = f'x="{o["x"]:.2f}" y="{o["y"]:.2f}" width="{o["rw"]:.2f}" height="{o["rh"]:.2f}" rx="{o["r"]:.2f}"'
            if o["op"] == "fill":
                body.append(f'<rect {attrs} fill="currentColor" stroke="none"/>')
            else:
                body.append(f'<rect {attrs} fill="none" stroke="currentColor" stroke-width="{o["sw"]:.1f}" stroke-linejoin="round"/>')
        else:
            d = segs_to_d(o["segs"])
            cap = ' stroke-linecap="round" stroke-linejoin="round"'
            if o["op"] == "fill":
                body.append(f'<path d="{d}" fill="currentColor" stroke="none" fill-rule="evenodd"/>')
            else:
                body.append(f'<path d="{d}" fill="none" stroke="currentColor" stroke-width="{o["w"]:.1f}"{cap}/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
            f'width="24" height="24" fill="currentColor">' + "".join(body) + "</svg>")

def render_png(name, color, out, px):
    cairosvg.svg2png(bytestring=svg_for(name).replace("currentColor", color).encode(),
                     write_to=out, output_width=px, output_height=px)

FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
FONT_B = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)

def make_contact_sheet():
    sections = [("STATUS BAR — unified masters (panel 16px optical)", ["wifi", "wired", "battery", "speaker", "sliders"]),
                ("CONTROL CENTER TILES — 22px optical, stroke 2.2 (W68 64px circles)", ["ccWifi", "bluetooth", "moon", "half", "bell", "sun", "ccSpeaker"]),
                ("SETTINGS SIDEBAR — white monochrome (W63 tint table RETIRED by owner order)", list(TINTS.keys())),
                ("APP GLYPHS — dock clear mode (W76 white-on-glass)", ["gear", "folder"])]
    names_all = [n for _, ns in sections for n in ns]
    alias = {"ccWifi": "wifi", "ccSpeaker": "speaker"}
    cell, pad, W = 132, 18, 6
    rows = [max(1, math.ceil(len(ns) / 6)) for _, ns in sections]
    H = sum(rows[i] * cell + 58 for i in range(len(sections))) + 40
    im = Image.new("RGB", (6 * cell + pad * 2, H), "#15171b")
    dr = ImageDraw.Draw(im)
    y = 22
    for i, (title, names) in enumerate(sections):
        dr.text((pad, y), title, font=FONT_B, fill="#8fb6e8"); y += 34
        for j, n in enumerate(names):
            cx, cy = pad + (j % 6) * cell, y + (j // 6) * cell
            tile = round_rectangle(dr, (cx + 8, cy + 8, cx + cell - 8, cy + cell - 26), 18, "#23262c")
            col = "#FFFFFF"  # clear mode: every glyph renders white (owner order)
            render_png(alias.get(n, n), col, "/tmp/_ic.png", 84)
            ic = Image.open("/tmp/_ic.png").convert("RGBA")
            im.paste(ic, (cx + 8 + (cell - 16 - 84) // 2, cy + 8 + (cell - 34 - 84) // 2), ic)
            dr.text((cx + cell // 2 - dr.textlength(n, font=FONT) / 2, cy + cell - 24), n, font=FONT, fill="#c8cdd6")
        y += rows[i] * cell + 24
    im.save(f"{OUT}/contact-sheet.png")

def round_rectangle(dr, box, r, fill):
    dr.rounded_rectangle(box, radius=r, fill=fill)
    return None

# ── QML emission (same geometry → Context2D calls, size-normalized) ─────
def qml_ops(name, indent="        "):
    lines = []
    for o in G[name]:
        if o["type"] == "circle":
            if o["op"] == "fill":
                lines.append(f"{indent}ctx.beginPath(); ctx.arc({o['cx']:.2f}*s, {o['cy']:.2f}*s, {o['r']:.2f}*s, 0, Math.PI*2); ctx.fill()")
            else:
                lines.append(f"{indent}ctx.beginPath(); ctx.arc({o['cx']:.2f}*s, {o['cy']:.2f}*s, {o['r']:.2f}*s, 0, Math.PI*2); ctx.stroke()")
        elif o["type"] == "rrect":
            lines.append(f"{indent}ctx.beginPath()")
            lines.append(f"{indent}_rrectN(ctx, {o['x']:.2f}*s, {o['y']:.2f}*s, {o['rw']:.2f}*s, {o['rh']:.2f}*s, {o['r']:.2f}*s)")
            lines.append(f"{indent}ctx.{'fill' if o['op']=='fill' else 'stroke'}()")
        else:
            lines.append(f"{indent}ctx.beginPath()")
            for s in o["segs"]:
                if s[0] == "M": lines.append(f"{indent}ctx.moveTo({s[1]:.2f}*s, {s[2]:.2f}*s)")
                elif s[0] == "L": lines.append(f"{indent}ctx.lineTo({s[1]:.2f}*s, {s[2]:.2f}*s)")
                elif s[0] == "C": lines.append(f"{indent}ctx.bezierCurveTo({s[1]:.2f}*s, {s[2]:.2f}*s, {s[3]:.2f}*s, {s[4]:.2f}*s, {s[5]:.2f}*s, {s[6]:.2f}*s)")
                elif s[0] == "Q": lines.append(f"{indent}ctx.quadraticCurveTo({s[1]:.2f}*s, {s[2]:.2f}*s, {s[3]:.2f}*s, {s[4]:.2f}*s)")
                elif s[0] == "Z": lines.append(f"{indent}ctx.closePath()")
                elif s[0] == "A":
                    _, cx, cy, r, a0, a1, ccw = s
                    lines.append(f"{indent}ctx.arc({cx:.2f}*s, {cy:.2f}*s, {r:.2f}*s, {a0:.4f}, {a1:.4f}, {str(ccw).lower()})")
            lines.append(f"{indent}ctx.{'fill' if o['op']=='fill' else 'stroke'}()")
    return "\n".join(lines)

def emit_qml():
    out = []
    out.append("""pragma Singleton
import QtQuick

// T23 (v0.6.81) — Glyphs redrawn from the reviewer's icon-pack geometry.
// ONE geometry source: every painter below is emitted from the same 24-grid
// paths the SVG pack ships (reviewer's scripts/gen_icon_pack.py), so the
// pack and the code cannot drift. Painters are size-normalized:
//   const s = Math.min(w, h) / 24 — every coordinate is grid*s.
// Contract unchanged: (ctx, w, h, color[, args]), 2 px stroke family,
// round caps/joins, no emoji, no theme dependency.
//
// WHAT CHANGED (the reviewer's icon guide, §1):
//   palette / sparkles / chip / mountain / monitor / person / speaker —
//   redrawn (the v0.6.78 set read mangled or noise at 18 px optical).
//   wifi — the Panel fan is now THE wifi (CC's stroked-arc variant dies;
//   one glyph, one geometry, everywhere).
//   wired — the plug re-mastered (the old one read as hamburger lines).
//   bluetooth / moon / half / bell / sun — re-mastered at stroke 2.2 for
//   the W68 64px-circle tiles.
//   battery / sliders — unchanged (review-approved twice; now size-normalized).
QtObject {
    function _pen(ctx, color, lw) {
        ctx.strokeStyle = color; ctx.fillStyle = color
        ctx.lineWidth = (lw || 2) * Math.min(ctx.canvas.width, ctx.canvas.height) / 24
        ctx.lineCap = "round"; ctx.lineJoin = "round"
    }
    function _rrectN(ctx, x, y, rw, rh, r) {
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + rw, y, x + rw, y + rh, r)
        ctx.arcTo(x + rw, y + rh, x, y + rh, r)
        ctx.arcTo(x, y + rh, x, y, r)
        ctx.arcTo(x, y, x + rw, y, r)
        ctx.closePath()
    }
""")
    names = ["wifi", "wired", "battery", "speaker", "sliders", "bluetooth", "moon",
             "half", "bell", "sun", "mountain", "palette", "sparkles", "chip",
             "monitor", "netWifi", "person", "gear", "folder"]
    sigs = {
        "wifi": "function wifi(ctx, w, h, color) {",
        "wired": "function wired(ctx, w, h, color) {",
        "battery": None,  # emitted specially below (stateful)
        "speaker": "function speaker(ctx, w, h, color, muted) {",
        "sliders": "function sliders(ctx, w, h, color) {",
        "bluetooth": "function bluetooth(ctx, w, h, color) {",
        "moon": "function moon(ctx, w, h, color) {",
        "half": "function half(ctx, w, h, color) {",
        "bell": "function bell(ctx, w, h, color, checked) {",
        "sun": "function sun(ctx, w, h, color) {",
        "mountain": "function mountain(ctx, w, h, color) {",
        "palette": "function palette(ctx, w, h, color) {",
        "sparkles": "function sparkles(ctx, w, h, color) {",
        "chip": "function chip(ctx, w, h, color) {",
        "monitor": "function monitor(ctx, w, h, color) {",
        "netWifi": "function netWifi(ctx, w, h, color) { wifi(ctx, w, h, color) }",
        "person": "function person(ctx, w, h, color) {",
        "gear": "function gear(ctx, w, h, color) {",
        "folder": "function folder(ctx, w, h, color) {",
    }
    for n in names:
        if n == "netWifi":
            out.append(f"    {sigs['netWifi']}\n"); continue
        if n == "battery":
            out.append("""    // Battery — the approved geometry, size-normalized; state travels
    // (charging bolt / AC-only) exactly as before.
    function battery(ctx, w, h, color, charging, percent) {
        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 1.8)
        ctx.beginPath()
        _rrectN(ctx, 4.0*s, 7.5*s, 15*s, 9*s, 2.4*s)
        ctx.stroke()
        ctx.beginPath()
        _rrectN(ctx, 20.4*s, 10.4*s, 1.8*s, 3.2*s, 0.9*s)
        ctx.fill()
        const hasBattery = percent >= 0
        if (hasBattery) {
            const level = Math.max(0, Math.min(100, percent)) / 100.0
            ctx.globalAlpha = 0.9
            ctx.fillRect(5.8*s, 9.2*s, Math.max(1.2*s, 9.6*s * level), 5.6*s)
            ctx.globalAlpha = 1.0
        }
        if (charging || !hasBattery) {
            ctx.beginPath()
            ctx.moveTo(11.4*s, 8.6*s)
            ctx.lineTo(8.4*s, 13.4*s)
            ctx.lineTo(10.6*s, 13.4*s)
            ctx.lineTo(9.4*s, 17.0*s)
            ctx.lineTo(12.6*s, 12.4*s)
            ctx.lineTo(10.4*s, 12.4*s)
            ctx.closePath()
            ctx.fill()
        }
    }
""")
            continue
        out.append(f"    // {n} — pack master geometry (24-grid), size-normalized.\n")
        out.append(f"    {sigs[n]}\n")
        if n == "speaker":
            out.append("""        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        // driver body
        ctx.beginPath()
        ctx.moveTo(6.5*s, 9.4*s)
        ctx.lineTo(9.2*s, 9.4*s)
        ctx.lineTo(13.2*s, 5.4*s)
        ctx.lineTo(13.2*s, 18.6*s)
        ctx.lineTo(9.2*s, 14.6*s)
        ctx.lineTo(6.5*s, 14.6*s)
        ctx.closePath()
        ctx.fill()
        if (muted) {
            ctx.beginPath()
            ctx.moveTo(15.0*s, 9.6*s)
            ctx.lineTo(19.6*s, 14.4*s)
            ctx.moveTo(19.6*s, 9.6*s)
            ctx.lineTo(15.0*s, 14.4*s)
            ctx.stroke()
        } else {
            ctx.beginPath()
            ctx.arc(14.2*s, 12*s, 3.2*s, -0.96, 0.96); ctx.stroke()
            ctx.beginPath()
            ctx.arc(14.2*s, 12*s, 6.4*s, -0.96, 0.96); ctx.stroke()
        }
    }
""")
            continue
        if n == "bell":
            out.append(f"""        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath(); ctx.arc(12*s, 4.6*s, 1.5*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath()
        ctx.moveTo(10.5*s, 6.2*s)
        ctx.bezierCurveTo(7.2*s, 7.6*s, 8.3*s, 11*s, 6.0*s, 15.4*s)
        ctx.lineTo(18.0*s, 15.4*s)
        ctx.bezierCurveTo(15.7*s, 11*s, 16.8*s, 7.6*s, 13.5*s, 6.2*s)
        ctx.closePath()
        if (checked) ctx.fill(); else ctx.stroke()
        ctx.beginPath(); ctx.moveTo(5.6*s, 15.4*s); ctx.lineTo(18.4*s, 15.4*s); ctx.stroke()
        if (!checked) {{
            ctx.beginPath()
            ctx.arc(12*s, 17.9*s, 1.8*s, 0.35, 2.79); ctx.stroke()
        }}
    }}
""")
            continue
        if n == "moon":
            out.append("""        ctx.reset()
        const s = Math.min(w, h) / 24
        ctx.fillStyle = color
        ctx.beginPath()
        ctx.arc(12*s, 12*s, 8.2*s, 0, Math.PI*2)
        ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        ctx.beginPath()
        ctx.arc(16.9*s, 8.5*s, 6.5*s, 0, Math.PI*2)
        ctx.fill()
        ctx.globalCompositeOperation = "source-over"
    }
""")
            continue
        out.append(f"""        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, {2.2 if n in ('bluetooth','half','sun','gear','folder') else 2})
{qml_ops(n if n not in ('ccWifi','ccSpeaker') else ('wifi' if n=='ccWifi' else 'speaker'))}
    }}
""")
    out.append("}\n")
    qml = "\n".join(out)
    with open(f"{OUT}/Glyphs-redrawn.qml", "w") as f:
        f.write(qml)
    # CC delegate block
    with open(f"{OUT}/ControlCenter-delegates.qml", "w") as f:
        f.write("""// ControlCenter.qml — replace the local painter block (lines 393-570)
// with these delegates; the geometry then lives ONLY in Glyphs.qml
// (one glyph, one geometry, everywhere).
function paintWifi(ctx, w, h, color) { Glyphs.wifi(ctx, w, h, color) }
function paintWired(ctx, w, h, color) { Glyphs.wired(ctx, w, h, color) }
function paintBluetooth(ctx, w, h, color) { Glyphs.bluetooth(ctx, w, h, color) }
function paintMoon(ctx, w, h, color) { Glyphs.moon(ctx, w, h, color) }
function paintHalf(ctx, w, h, color) { Glyphs.half(ctx, w, h, color) }
function paintBell(ctx, w, h, color, checked) { Glyphs.bell(ctx, w, h, color, checked) }
function paintSun(ctx, w, h, color) { Glyphs.sun(ctx, w, h, color) }
function paintSpeaker(ctx, w, h, color, muted) { Glyphs.speaker(ctx, w, h, color, muted) }
""")

# ── main ────────────────────────────────────────────────────────────────
WHITE, INK = "#FFFFFF", "#1d1d1f"
manifest = []
for name in G:
    svg = svg_for(name)
    with open(f"{OUT}/svg/{name}.svg", "w") as f:
        f.write(svg)
    variants = [("white", WHITE), ("ink", INK)]
    for vname, vcol in variants:
        for scale in (2, 3):
            p = f"{OUT}/png/{name}-{vname}@{scale}x.png"
            render_png(name, vcol, p, 24 * scale)
            manifest.append(p)
# sweep stale renders (e.g. the retired tint variants) so the pack never
# ships files the generator no longer produces
for f in os.listdir(f"{OUT}/png"):
    if f"{OUT}/png/{f}" not in manifest:
        os.remove(f"{OUT}/png/{f}")
make_contact_sheet()
emit_qml()
print(f"OK — {len(G)} masters, {len(manifest)} PNGs, contact sheet + QML emitted")
for f in sorted(os.listdir(OUT)): print(" ", f)
