pragma Singleton
import QtQuick

// T15-D8 (W45) — ONE shared glyph family, many consumers.
//
// The review's W45 ruling: the Settings sidebar read cramped and thin
// because its painters carried a different drawing contract from the
// panel family the user approved. This singleton is that contract in one
// place: 16 px optical box, 2 px stroke (1.8 where the geometry demands),
// round caps/joins, painters take (ctx, w, h, color[, args]) and are
// consumed by Panel.qml (the status cluster) and SettingsApp.qml (the
// sidebar rows — white ink at 92% inside the tint circle).
//
// The Panel painters moved here VERBATIM — every tuned geometry comment
// travels with its painter (the wifi fan's asymmetric ink centering, the
// battery's 0.9 px lift, the wired plug's ink band). Panel.qml delegates;
// no pixel moved.
QtObject {
    // ── the Panel status family (moved verbatim from Panel.qml) ────────

    // Wi-Fi — filled fan (macOS weight): three solid wedges read at a
    // glance where the old stroked arcs went thin. The fan's ink is
    // asymmetric around the apex: it spans [cy − rout, cy], so its ink
    // center is cy − rout/2 = cy − 3.85. Centering THAT on the glyph
    // midline (canvas y 8 — the speaker's ink center) gives
    // cy = 11.85 → cy = h/2+4. (v0.6.26 used h/2+2 and still read
    // ~3 px high against the speaker, battery and clock — the "icons not
    // in a line" report.)
    function wifi(ctx, w, h, color) {
        ctx.reset()
        ctx.fillStyle = color
        const cx = w / 2, cy = h / 2 + 4
        const a0 = Math.PI * 1.25, a1 = Math.PI * 1.75
        ctx.beginPath()
        ctx.moveTo(cx, cy)
        ctx.arc(cx, cy, 2.4, a0, a1)
        ctx.closePath()
        ctx.fill()
        const bands = [[3.5, 5.2], [6.3, 7.7]]
        for (const [rin, rout] of bands) {
            ctx.beginPath()
            ctx.arc(cx, cy, rout, a0, a1)
            ctx.arc(cx, cy, rin, a1, a0, true)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Wired ethernet (T15-D6, W43) — an RJ45 plug: connector body +
    // three contact pins + cable nub. Ink spans y 4.5..11.5 (center 8,
    // on the speaker/clock midline).
    function wired(ctx, w, h, color) {
        ctx.reset()
        ctx.fillStyle = color
        ctx.strokeStyle = color
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        const cx = w / 2
        ctx.beginPath()
        ctx.moveTo(cx - 3.5, 4.5)
        ctx.lineTo(cx + 3.5, 4.5)
        ctx.lineTo(cx + 3.5, 11.5)
        ctx.moveTo(cx - 3.5, 4.5)
        ctx.lineTo(cx - 3.5, 11.5)
        ctx.stroke()
        for (const off of [-1.8, 0, 1.8]) {
            ctx.beginPath()
            ctx.moveTo(cx + off, 4.5)
            ctx.lineTo(cx + off, 7.5)
            ctx.stroke()
        }
        ctx.beginPath()
        ctx.moveTo(cx, 11.5)
        ctx.lineTo(cx, 13.2)
        ctx.stroke()
    }

    // Battery body — 2 px outline, level fill, bolt for charge/AC. The
    // ink runs y 5.5..12.3 → center 8.9, a hair low against the
    // speaker/clock midline (8): translate up 0.9 px to sit on the line.
    function battery(ctx, w, h, color, charging, percent) {
        ctx.reset()
        ctx.translate(0, -0.9)
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.8
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(3, 5.5)
        ctx.lineTo(11, 5.5)
        ctx.quadraticCurveTo(12.5, 5.5, 12.5, 7)
        ctx.lineTo(12.5, 10.5)
        ctx.quadraticCurveTo(12.5, 12, 11, 12)
        ctx.lineTo(3, 12)
        ctx.quadraticCurveTo(1.5, 12, 1.5, 10.5)
        ctx.lineTo(1.5, 7)
        ctx.quadraticCurveTo(1.5, 5.5, 3, 5.5)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(13.6, 7.4)
        ctx.lineTo(14.4, 7.4)
        ctx.quadraticCurveTo(15, 7.4, 15, 8)
        ctx.lineTo(15, 9.5)
        ctx.quadraticCurveTo(15, 10.1, 14.4, 10.1)
        ctx.lineTo(13.6, 10.1)
        ctx.closePath()
        ctx.fill()
        const hasBattery = percent >= 0
        if (hasBattery) {
            const innerX = 3.4, innerMax = 10.6, innerH = 4.0
            const level = Math.max(0, Math.min(100, percent)) / 100.0
            ctx.globalAlpha = 0.9
            ctx.fillRect(innerX, 6.9, Math.max(1.2, (innerMax - innerX) * level), innerH)
            ctx.globalAlpha = 1.0
        }
        if (charging || !hasBattery) {
            ctx.beginPath()
            ctx.moveTo(7.6, 6.2)
            ctx.lineTo(5.4, 9.6)
            ctx.lineTo(6.9, 9.6)
            ctx.lineTo(6.1, 12.3)
            ctx.lineTo(8.5, 8.9)
            ctx.lineTo(7.0, 8.9)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Speaker — filled driver body + one stroked wave (the one glyph the
    // review called correct as-is). The muted X replaces the wave.
    function speaker(ctx, w, h, color, muted) {
        ctx.reset()
        ctx.fillStyle = color
        ctx.strokeStyle = color
        ctx.lineWidth = 2
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        const cx = w / 2 - 2, cy = h / 2
        ctx.beginPath()
        ctx.moveTo(cx - 3.5, cy - 2.5)
        ctx.lineTo(cx - 1, cy - 2.5)
        ctx.lineTo(cx + 2.5, cy - 6)
        ctx.lineTo(cx + 2.5, cy + 6)
        ctx.lineTo(cx - 1, cy + 2.5)
        ctx.lineTo(cx - 3.5, cy + 2.5)
        ctx.closePath()
        ctx.fill()
        if (muted) {
            ctx.beginPath()
            ctx.moveTo(cx + 4.5, cy - 2.5)
            ctx.lineTo(cx + 7.5, cy + 2.5)
            ctx.moveTo(cx + 7.5, cy - 2.5)
            ctx.lineTo(cx + 4.5, cy + 2.5)
            ctx.stroke()
        } else {
            ctx.beginPath()
            ctx.arc(cx + 3.5, cy, 3, -Math.PI / 3, Math.PI / 3)
            ctx.stroke()
        }
    }

    // Sliders (the Control Center glyph) — three rails + knobs.
    function sliders(ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 2
        ctx.lineCap = "round"
        for (let i = 0; i < 3; ++i) {
            const y = 3.5 + i * 4.5
            ctx.beginPath()
            ctx.moveTo(1.5, y)
            ctx.lineTo(w - 1.5, y)
            ctx.stroke()
            const knob = i === 0 ? 9.5 : i === 1 ? 4.5 : 11
            ctx.beginPath()
            ctx.arc(knob, y, 2.2, 0, Math.PI * 2)
            ctx.fill()
        }
    }

    // ── the Settings sidebar row set (W45 contract: outline, not filled,
    //    except the speaker body; 16 px optical box, 1.8 px stroke) ────

    function _pen(ctx, color) {
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.8
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
    }

    function _rrect(ctx, x, y, rw, rh, r) {
        // manual rounded rect — Context2D has no roundRect in the QML API
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + rw, y, x + rw, y + rh, r)
        ctx.arcTo(x + rw, y + rh, x, y + rh, r)
        ctx.arcTo(x, y + rh, x, y, r)
        ctx.arcTo(x, y, x + rw, y, r)
        ctx.closePath()
    }

    // Wallpaper — mountain: rounded 14×12 frame, two peaks (small then
    // large), sun dot upper-right.
    function mountain(ctx, w, h, color) {
        ctx.reset()
        _pen(ctx, color)
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        _rrect(ctx, cx - 7, cy - 6, 14, 12, 2)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(cx - 5, cy + 3)
        ctx.lineTo(cx - 1.5, cy - 2)
        ctx.lineTo(cx + 0.5, cy + 1)
        ctx.lineTo(cx + 2, cy - 1)
        ctx.lineTo(cx + 5, cy + 3)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx + 3.2, cy - 3.4, 1.1, 0, Math.PI * 2)
        ctx.fill()
    }

    // Appearance — palette: the blob with a thumb hole + three paint wells.
    function palette(ctx, w, h, color) {
        ctx.reset()
        _pen(ctx, color)
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        ctx.moveTo(cx - 6.2, cy - 1)
        ctx.bezierCurveTo(cx - 6.4, cy - 4.6, cx - 3.4, cy - 6.4, cx - 0.4, cy - 6.3)
        ctx.bezierCurveTo(cx + 3.6, cy - 6.2, cx + 6.4, cy - 4, cx + 6.4, cy - 0.4)
        ctx.bezierCurveTo(cx + 6.4, cy + 2.6, cx + 4.6, cy + 4.2, cx + 2.2, cy + 4.6)
        ctx.bezierCurveTo(cx + 0.6, cy + 4.9, cx + 0.8, cy + 3.8, cx + 0.4, cy + 3)
        ctx.bezierCurveTo(cx - 0.2, cy + 1.8, cx - 1.6, cy + 2.2, cx - 2.4, cy + 2.8)
        ctx.bezierCurveTo(cx - 3.4, cy + 3.6, cx - 3, cy + 5, cx - 4.4, cy + 5.4)
        ctx.bezierCurveTo(cx - 5.6, cy + 5.6, cx - 6.1, cy + 1.8, cx - 6.2, cy - 1)
        ctx.stroke()
        // thumb hole
        ctx.beginPath()
        ctx.arc(cx + 1.6, cy - 2.6, 1.5, 0, Math.PI * 2)
        ctx.stroke()
        // three paint wells
        ctx.beginPath()
        ctx.arc(cx - 3.2, cy - 2.4, 0.9, 0, Math.PI * 2)
        ctx.fill()
        ctx.beginPath()
        ctx.arc(cx - 3.6, cy + 0.6, 0.9, 0, Math.PI * 2)
        ctx.fill()
        ctx.beginPath()
        ctx.arc(cx + 3.6, cy + 0.4, 0.9, 0, Math.PI * 2)
        ctx.fill()
    }

    // Desktop Effects — sparkles: one large + two small four-point stars
    // (the review: "current star painter is correct — reuse it").
    function sparkles(ctx, w, h, color) {
        ctx.reset()
        _pen(ctx, color)
        const cx = w / 2, cy = h / 2
        const star = (sx, sy, r) => {
            ctx.beginPath()
            ctx.moveTo(sx, sy - r)
            ctx.quadraticCurveTo(sx + 0.6, sy - 0.6, sx + r, sy)
            ctx.quadraticCurveTo(sx + 0.6, sy + 0.6, sx, sy + r)
            ctx.quadraticCurveTo(sx - 0.6, sy + 0.6, sx - r, sy)
            ctx.quadraticCurveTo(sx - 0.6, sy - 0.6, sx, sy - r)
            ctx.closePath()
            ctx.stroke()
        }
        star(cx - 1.5, cy - 0.5, 4.4)
        star(cx + 4.6, cy - 4.4, 2.0)
        star(cx + 4.2, cy + 4.4, 1.7)
    }

    // Drivers & Firmware — chip: rounded body + inner die + 3 legs per side.
    function chip(ctx, w, h, color) {
        ctx.reset()
        _pen(ctx, color)
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        _rrect(ctx, cx - 4.5, cy - 4.5, 9, 9, 1.6)
        ctx.stroke()
        ctx.beginPath()
        _rrect(ctx, cx - 2.2, cy - 2.2, 4.4, 4.4, 0.8)
        ctx.stroke()
        for (const off of [-2.6, 0, 2.6]) {
            ctx.beginPath()
            ctx.moveTo(cx + off, cy - 4.5)
            ctx.lineTo(cx + off, cy - 6.6)
            ctx.moveTo(cx + off, cy + 4.5)
            ctx.lineTo(cx + off, cy + 6.6)
            ctx.stroke()
        }
        ctx.beginPath()
        ctx.moveTo(cx - 4.5, cy - 1.6)
        ctx.lineTo(cx - 6.6, cy - 1.6)
        ctx.moveTo(cx - 4.5, cy + 1.6)
        ctx.lineTo(cx - 6.6, cy + 1.6)
        ctx.moveTo(cx + 4.5, cy - 1.6)
        ctx.lineTo(cx + 6.6, cy - 1.6)
        ctx.moveTo(cx + 4.5, cy + 1.6)
        ctx.lineTo(cx + 6.6, cy + 1.6)
        ctx.stroke()
    }

    // Displays — monitor: rounded screen + stem + base.
    function monitor(ctx, w, h, color) {
        ctx.reset()
        _pen(ctx, color)
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        _rrect(ctx, cx - 6.5, cy - 5.5, 13, 9, 1.8)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(cx, cy + 3.5)
        ctx.lineTo(cx, cy + 5.8)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(cx - 3.5, cy + 6.3)
        ctx.lineTo(cx + 3.5, cy + 6.3)
        ctx.stroke()
    }

    // Network — the Panel wifi fan (the review: reuse, not a redraw).
    function netWifi(ctx, w, h, color) {
        wifi(ctx, w, h, color)
    }

    // Users — person: head circle + shoulder arc.
    function person(ctx, w, h, color) {
        ctx.reset()
        _pen(ctx, color)
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        ctx.arc(cx, cy - 2.6, 2.9, 0, Math.PI * 2)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx, cy + 5.6, 4.8, Math.PI * 1.13, Math.PI * 1.87, false)
        ctx.stroke()
    }
}
