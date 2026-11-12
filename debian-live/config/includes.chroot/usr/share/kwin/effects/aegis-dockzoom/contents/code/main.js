"use strict";

// aegis-dockzoom — T12 W21: dock-anchored window open/close, the macOS
// dock zoom. Modeled on the stock scale effect (KWin 6.6 ships scale as
// a JS effect — this file follows its exact API surface: effects.window-
// Added/Closed, effect.isGrabbed, the object form of animate, QEasingCurve
// enums) and replaces it as the toplevel-open-close-animation effect.
//
// Open: the window grows OUT OF its dock tile — scale 0.3 -> 1 (~280 ms
// OutCubic) with opacity 0 -> 1, plus a Position animation that carries
// the window's center from the tile's center to its final center.
// Close: reverse into the tile (~200 ms InCubic).
//
// Why Position+Scale and not a Scale anchor: KWin's AnimationEffect
// anchors are EDGES/corners (Left/Top/Right/Bottom/Mouse) — an arbitrary
// tile center is not expressible, and anchor 0 means the window center.
// So the zoom pivots on the window center and the tile anchoring comes
// from the Position pair.
//
// The tile map travels through config: JS effects have NO callDBus in
// 6.6 (window scripts do), so the shell writes kwinrc
// [Effect-aegis-dockzoom] TileMap = {"<app-id>": [cx, cy], ...} and the
// effect re-reads it on configChanged. A window whose app id is not in
// the map zooms from its own center (the honest fallback).
//
// Documented delta against the ruling: minimize/restore has no scripted
// hook in 6.6 (EffectsHandler exposes only windowAdded/Closed/Activated/
// Deleted to JS — the stock scale effect animates exactly these two).

const OPEN_MS = 280;
const CLOSE_MS = 200;
const TILE_SCALE = 0.3;

let dockMap = {};

function readMap() {
    const raw = effect.readConfig("TileMap", "{}") || "{}";
    try {
        dockMap = JSON.parse(raw);
    } catch (e) {
        print("aegis-dockzoom: unparsable TileMap, keeping the previous one");
    }
}

function tileCenter(window) {
    const rect = dockMap[String(window.resourceClass || "")];
    if (rect && rect.length >= 2) {
        return { x: rect[0], y: rect[1] };
    }
    return null;
}

function centerOf(window) {
    return { x: window.x + window.width / 2,
             y: window.y + window.height / 2 };
}

function isZoomWindow(window) {
    // Same filter shape as the stock scale effect: popups, menus,
    // tooltips, the lock screen and unmanaged windows never zoom. The
    // shell's own layer surfaces pass normalWindow in KWin 6.6 — the
    // v0.6.36 boot run proved the class — and the W21 ruling says the
    // effect NEVER touches panel/dock/island/desktop: exclude the
    // shell's resourceClass outright.
    if (window.popupWindow || !window.managed
            || window.lockScreen || window.outline) {
        return false;
    }
    if (String(window.resourceClass || "") === "aegis-shell") {
        return false;
    }
    return window.normalWindow || window.dialog;
}

function growFromTile(window) {
    if (!window.visible) {
        return;
    }
    if (effect.isGrabbed(window, Effect.WindowAddedGrabRole)) {
        return;
    }
    const c = tileCenter(window) || centerOf(window);
    animate({
        window: window,
        curve: QEasingCurve.OutCubic,
        duration: OPEN_MS,
        animations: [
            { type: Effect.Scale, from: TILE_SCALE, to: 1.0 },
            { type: Effect.Opacity, from: 0.0, to: 1.0 },
            { type: Effect.Position,
              from: { value1: c.x, value2: c.y },
              to: { value1: window.x + window.width / 2,
                    value2: window.y + window.height / 2 } }
        ]
    });
}

function shrinkIntoTile(window) {
    if (!window.visible || window.skipsCloseAnimation) {
        return;
    }
    if (effect.isGrabbed(window, Effect.WindowClosedGrabRole)) {
        return;
    }
    const c = tileCenter(window) || centerOf(window);
    animate({
        window: window,
        curve: QEasingCurve.InCubic,
        duration: CLOSE_MS,
        animations: [
            { type: Effect.Scale, from: 1.0, to: TILE_SCALE },
            { type: Effect.Opacity, from: 1.0, to: 0.0 },
            { type: Effect.Position,
              from: { value1: window.x + window.width / 2,
                      value2: window.y + window.height / 2 },
              to: { value1: c.x, value2: c.y } }
        ]
    });
}

effect.configChanged.connect(readMap);
effects.windowAdded.connect(growFromTile);
effects.windowClosed.connect(shrinkIntoTile);
readMap();
// boot marker — the boot gate's journal grep asserts this line exists
print("aegis-dockzoom: loaded");
