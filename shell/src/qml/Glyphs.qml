pragma Singleton
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

    // wifi — pack master geometry (24-grid), size-normalized.

    function wifi(ctx, w, h, color, level) {
        // W81 — the SOLID fan (the reference plate): a wedge dot plus two
        // round-capped arc bands. `level` lights the arcs: 3 = all, 2 =
        // dot + mid, 1 = dot only; anything else (undefined from the old
        // callers) = all lit. Unlit bands ride at 0.28 alpha.
        ctx.reset()
        const s = Math.min(w, h) / 24
        const cx = 12 * s
        const cy = 17.8 * s
        const a0 = 3.9270       // 225°
        const a1 = 5.4978       // 315°
        const lit = (level === 1 || level === 2 || level === 3) ? level : 3
        ctx.fillStyle = color
        // dot — solid wedge, the fan's anchor
        ctx.beginPath()
        ctx.arc(cx, cy, 2.80 * s, a0, a1, false)
        ctx.closePath()
        ctx.fill()
        // the two bands — strokes with round caps read as the reference
        ctx.strokeStyle = color
        ctx.lineCap = "round"
        ctx.lineWidth = 2.6 * s
        const band = function(r, isLit) {
            ctx.globalAlpha = isLit ? 1.0 : 0.28
            ctx.beginPath()
            ctx.arc(cx, cy, r, a0, a1, false)
            ctx.stroke()
        }
        band(5.4 * s, lit >= 2)
        band(8.6 * s, lit >= 3)
        ctx.globalAlpha = 1.0
    }

    // wired — pack master geometry (24-grid), size-normalized.

    // W81 — the island pendant's state marks (the macOS notch pendant:
    // green check = connected, yellow ! = no internet, red X = dropped).
    function check(ctx, w, h, color) {
        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.4)
        ctx.beginPath()
        ctx.moveTo(6.0*s, 12.4*s)
        ctx.lineTo(10.2*s, 16.6*s)
        ctx.lineTo(18.0*s, 7.6*s)
        ctx.stroke()
    }

    function exclaim(ctx, w, h, color) {
        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.4)
        ctx.beginPath()
        ctx.moveTo(12.0*s, 5.4*s)
        ctx.lineTo(12.0*s, 13.6*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(12.0*s, 17.6*s, 1.35*s, 0, Math.PI * 2)
        ctx.fill()
    }

    function cross(ctx, w, h, color) {
        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.4)
        ctx.beginPath()
        ctx.moveTo(7.0*s, 7.0*s)
        ctx.lineTo(17.0*s, 17.0*s)
        ctx.moveTo(17.0*s, 7.0*s)
        ctx.lineTo(7.0*s, 17.0*s)
        ctx.stroke()
    }

    function wired(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        _rrectN(ctx, 8.00*s, 3.50*s, 8.00*s, 8.50*s, 1.40*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(10.20*s, 3.50*s)
        ctx.lineTo(10.20*s, 6.80*s)
        ctx.moveTo(12.00*s, 3.50*s)
        ctx.lineTo(12.00*s, 6.80*s)
        ctx.moveTo(13.80*s, 3.50*s)
        ctx.lineTo(13.80*s, 6.80*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(12.00*s, 12.00*s)
        ctx.lineTo(12.00*s, 15.20*s)
        ctx.stroke()
    }

    // Battery — W81 reference plate: a CHUNKY rounded outline, the level
    // as one rounded ink chunk, and a rounded nub tab (the old flat
    // fillRect + pin-thin outline read as a system-tray relic). The
    // charging bolt stays.
    function battery(ctx, w, h, color, charging, percent) {
        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.2)
        ctx.beginPath()
        _rrectN(ctx, 3.2*s, 6.6*s, 16.4*s, 11.0*s, 4.6*s)
        ctx.stroke()
        ctx.beginPath()
        // the nub — a rounded tab, not a pin
        _rrectN(ctx, 20.8*s, 10.2*s, 2.0*s, 3.8*s, 1.0*s)
        ctx.fill()
        const hasBattery = percent >= 0
        if (hasBattery) {
            const level = Math.max(0, Math.min(100, percent)) / 100.0
            ctx.beginPath()
            // the level — one rounded chunk growing from the left
            const lw = Math.max(3.6 * s, 12.4 * s * level)
            _rrectN(ctx, 5.2*s, 8.6*s, lw, 6.8*s, 2.8*s)
            ctx.fill()
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

    // speaker — pack master geometry (24-grid), size-normalized.

    function speaker(ctx, w, h, color, muted) {

        ctx.reset()
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

    // sliders — pack master geometry (24-grid), size-normalized.

    function sliders(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        ctx.moveTo(4.00*s, 6.50*s)
        ctx.lineTo(20.00*s, 6.50*s)
        ctx.stroke()
        ctx.beginPath(); ctx.arc(15.20*s, 6.50*s, 2.40*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath()
        ctx.moveTo(4.00*s, 12.00*s)
        ctx.lineTo(20.00*s, 12.00*s)
        ctx.stroke()
        ctx.beginPath(); ctx.arc(8.00*s, 12.00*s, 2.40*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath()
        ctx.moveTo(4.00*s, 17.50*s)
        ctx.lineTo(20.00*s, 17.50*s)
        ctx.stroke()
        ctx.beginPath(); ctx.arc(16.80*s, 17.50*s, 2.40*s, 0, Math.PI*2); ctx.fill()
    }

    // bluetooth — pack master geometry (24-grid), size-normalized.

    function bluetooth(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.2)
        ctx.beginPath()
        ctx.moveTo(12.00*s, 3.00*s)
        ctx.lineTo(12.00*s, 21.00*s)
        ctx.moveTo(12.00*s, 3.00*s)
        ctx.lineTo(17.00*s, 7.60*s)
        ctx.lineTo(7.00*s, 15.60*s)
        ctx.moveTo(12.00*s, 21.00*s)
        ctx.lineTo(17.00*s, 16.40*s)
        ctx.lineTo(7.00*s, 8.40*s)
        ctx.stroke()
    }

    // moon — pack master geometry (24-grid), size-normalized.

    function moon(ctx, w, h, color) {

        ctx.reset()
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

    // half — pack master geometry (24-grid), size-normalized.

    function half(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.2)
        ctx.beginPath(); ctx.arc(12.00*s, 12.00*s, 7.50*s, 0, Math.PI*2); ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(12.00*s, 4.50*s)
        ctx.arc(12.00*s, 12.00*s, 7.50*s, -1.5708, 1.5708, false)
        ctx.closePath()
        ctx.fill()
    }

    // bell — pack master geometry (24-grid), size-normalized.

    function bell(ctx, w, h, color, checked) {

        ctx.reset()
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
        if (!checked) {
            ctx.beginPath()
            ctx.arc(12*s, 17.9*s, 1.8*s, 0.35, 2.79); ctx.stroke()
        }
    }

    // sun — pack master geometry (24-grid), size-normalized.

    function sun(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.2)
        ctx.beginPath(); ctx.arc(12.00*s, 12.00*s, 4.00*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath()
        ctx.moveTo(12.00*s, 2.80*s)
        ctx.lineTo(12.00*s, 5.20*s)
        ctx.moveTo(12.00*s, 18.80*s)
        ctx.lineTo(12.00*s, 21.20*s)
        ctx.moveTo(2.80*s, 12.00*s)
        ctx.lineTo(5.20*s, 12.00*s)
        ctx.moveTo(18.80*s, 12.00*s)
        ctx.lineTo(21.20*s, 12.00*s)
        ctx.moveTo(5.60*s, 5.60*s)
        ctx.lineTo(7.30*s, 7.30*s)
        ctx.moveTo(16.70*s, 7.30*s)
        ctx.lineTo(18.40*s, 5.60*s)
        ctx.moveTo(5.60*s, 18.40*s)
        ctx.lineTo(7.30*s, 16.70*s)
        ctx.moveTo(16.70*s, 16.70*s)
        ctx.lineTo(18.40*s, 18.40*s)
        ctx.stroke()
    }

    // mountain — pack master geometry (24-grid), size-normalized.

    function mountain(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        _rrectN(ctx, 2.50*s, 4.50*s, 19.00*s, 15.00*s, 3.00*s)
        ctx.stroke()
        ctx.beginPath(); ctx.arc(16.60*s, 8.40*s, 1.60*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath()
        ctx.moveTo(5.50*s, 17.00*s)
        ctx.lineTo(9.50*s, 10.50*s)
        ctx.lineTo(11.80*s, 13.50*s)
        ctx.lineTo(13.80*s, 11.00*s)
        ctx.lineTo(18.50*s, 17.00*s)
        ctx.stroke()
    }

    // palette — pack master geometry (24-grid), size-normalized.

    function palette(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        ctx.moveTo(4.00*s, 12.20*s)
        ctx.bezierCurveTo(3.80*s, 8.00*s, 6.00*s, 4.60*s, 10.00*s, 4.30*s)
        ctx.bezierCurveTo(14.50*s, 4.00*s, 19.60*s, 6.00*s, 20.00*s, 10.60*s)
        ctx.bezierCurveTo(20.30*s, 14.00*s, 18.40*s, 15.60*s, 15.90*s, 16.20*s)
        ctx.bezierCurveTo(14.20*s, 16.60*s, 14.50*s, 17.90*s, 13.40*s, 18.80*s)
        ctx.bezierCurveTo(12.00*s, 20.00*s, 9.40*s, 19.60*s, 7.60*s, 18.60*s)
        ctx.bezierCurveTo(5.20*s, 17.40*s, 4.20*s, 14.80*s, 4.00*s, 12.20*s)
        ctx.closePath()
        ctx.stroke()
        ctx.beginPath(); ctx.arc(13.20*s, 8.20*s, 2.00*s, 0, Math.PI*2); ctx.stroke()
        ctx.beginPath(); ctx.arc(8.60*s, 8.80*s, 1.30*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath(); ctx.arc(7.90*s, 12.30*s, 1.30*s, 0, Math.PI*2); ctx.fill()
        ctx.beginPath(); ctx.arc(11.50*s, 14.20*s, 1.30*s, 0, Math.PI*2); ctx.fill()
    }

    // sparkles — pack master geometry (24-grid), size-normalized.

    function sparkles(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        ctx.moveTo(10.00*s, 7.50*s)
        ctx.quadraticCurveTo(11.43*s, 11.57*s, 15.50*s, 13.00*s)
        ctx.quadraticCurveTo(11.43*s, 14.43*s, 10.00*s, 18.50*s)
        ctx.quadraticCurveTo(8.57*s, 14.43*s, 4.50*s, 13.00*s)
        ctx.quadraticCurveTo(8.57*s, 11.57*s, 10.00*s, 7.50*s)
        ctx.closePath()
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(17.50*s, 4.00*s)
        ctx.quadraticCurveTo(18.28*s, 6.22*s, 20.50*s, 7.00*s)
        ctx.quadraticCurveTo(18.28*s, 7.78*s, 17.50*s, 10.00*s)
        ctx.quadraticCurveTo(16.72*s, 7.78*s, 14.50*s, 7.00*s)
        ctx.quadraticCurveTo(16.72*s, 6.22*s, 17.50*s, 4.00*s)
        ctx.closePath()
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(17.00*s, 14.30*s)
        ctx.quadraticCurveTo(17.57*s, 15.93*s, 19.20*s, 16.50*s)
        ctx.quadraticCurveTo(17.57*s, 17.07*s, 17.00*s, 18.70*s)
        ctx.quadraticCurveTo(16.43*s, 17.07*s, 14.80*s, 16.50*s)
        ctx.quadraticCurveTo(16.43*s, 15.93*s, 17.00*s, 14.30*s)
        ctx.closePath()
        ctx.fill()
    }

    // chip — pack master geometry (24-grid), size-normalized.

    function chip(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        _rrectN(ctx, 6.50*s, 6.50*s, 11.00*s, 11.00*s, 2.00*s)
        ctx.stroke()
        ctx.beginPath()
        _rrectN(ctx, 9.60*s, 9.60*s, 4.80*s, 4.80*s, 1.00*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(9.50*s, 6.50*s)
        ctx.lineTo(9.50*s, 3.40*s)
        ctx.moveTo(12.00*s, 6.50*s)
        ctx.lineTo(12.00*s, 3.40*s)
        ctx.moveTo(14.50*s, 6.50*s)
        ctx.lineTo(14.50*s, 3.40*s)
        ctx.moveTo(9.50*s, 17.50*s)
        ctx.lineTo(9.50*s, 20.60*s)
        ctx.moveTo(12.00*s, 17.50*s)
        ctx.lineTo(12.00*s, 20.60*s)
        ctx.moveTo(14.50*s, 17.50*s)
        ctx.lineTo(14.50*s, 20.60*s)
        ctx.moveTo(6.50*s, 9.50*s)
        ctx.lineTo(3.40*s, 9.50*s)
        ctx.moveTo(6.50*s, 12.00*s)
        ctx.lineTo(3.40*s, 12.00*s)
        ctx.moveTo(6.50*s, 14.50*s)
        ctx.lineTo(3.40*s, 14.50*s)
        ctx.moveTo(17.50*s, 9.50*s)
        ctx.lineTo(20.60*s, 9.50*s)
        ctx.moveTo(17.50*s, 12.00*s)
        ctx.lineTo(20.60*s, 12.00*s)
        ctx.moveTo(17.50*s, 14.50*s)
        ctx.lineTo(20.60*s, 14.50*s)
        ctx.stroke()
    }

    // monitor — pack master geometry (24-grid), size-normalized.

    function monitor(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath()
        _rrectN(ctx, 3.50*s, 4.50*s, 17.00*s, 11.00*s, 2.20*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(12.00*s, 15.50*s)
        ctx.lineTo(12.00*s, 18.60*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(8.00*s, 18.60*s)
        ctx.lineTo(16.00*s, 18.60*s)
        ctx.stroke()
    }

    function netWifi(ctx, w, h, color) { wifi(ctx, w, h, color) }

    // person — pack master geometry (24-grid), size-normalized.

    function person(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2)
        ctx.beginPath(); ctx.arc(12.00*s, 7.80*s, 3.40*s, 0, Math.PI*2); ctx.stroke()
        ctx.beginPath()
        ctx.arc(12.00*s, 20.60*s, 6.40*s, 3.7699, 5.6549, false)
        ctx.stroke()
    }

    // gear — pack master geometry (24-grid), size-normalized.

    function gear(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.2)
        ctx.beginPath(); ctx.arc(12.00*s, 12.00*s, 7.00*s, 0, Math.PI*2); ctx.stroke()
        ctx.beginPath(); ctx.arc(12.00*s, 12.00*s, 2.60*s, 0, Math.PI*2); ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(12.00*s, 1.80*s)
        ctx.lineTo(12.00*s, 4.00*s)
        ctx.moveTo(12.00*s, 20.00*s)
        ctx.lineTo(12.00*s, 22.20*s)
        ctx.moveTo(1.80*s, 12.00*s)
        ctx.lineTo(4.00*s, 12.00*s)
        ctx.moveTo(20.00*s, 12.00*s)
        ctx.lineTo(22.20*s, 12.00*s)
        ctx.moveTo(4.90*s, 4.90*s)
        ctx.lineTo(6.40*s, 6.40*s)
        ctx.moveTo(17.60*s, 6.40*s)
        ctx.lineTo(19.10*s, 4.90*s)
        ctx.moveTo(4.90*s, 19.10*s)
        ctx.lineTo(6.40*s, 17.60*s)
        ctx.moveTo(17.60*s, 17.60*s)
        ctx.lineTo(19.10*s, 19.10*s)
        ctx.stroke()
    }

    // folder — pack master geometry (24-grid), size-normalized.

    function folder(ctx, w, h, color) {

        ctx.reset()
        const s = Math.min(w, h) / 24
        _pen(ctx, color, 2.2)
        ctx.beginPath()
        _rrectN(ctx, 3.00*s, 7.00*s, 18.00*s, 12.50*s, 2.50*s)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(3.00*s, 7.00*s)
        ctx.lineTo(3.00*s, 5.50*s)
        ctx.quadraticCurveTo(3.00*s, 4.50*s, 4.00*s, 4.50*s)
        ctx.lineTo(9.00*s, 4.50*s)
        ctx.quadraticCurveTo(10.00*s, 4.50*s, 10.00*s, 5.50*s)
        ctx.lineTo(10.00*s, 7.00*s)
        ctx.stroke()
    }

}
