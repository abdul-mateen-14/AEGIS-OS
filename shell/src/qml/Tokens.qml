pragma Singleton
import QtQuick
import Aegis.Util

// Aegis OS design tokens — the proposal's tables as code (docs/DESIGN-TOKENS.md
// maps every value back to its table). v1.3 defaults with one v1.4 override:
// the Dynamic Island idle capsule, shrank to the iPhone Pro-class pill.

QtObject {
    objectName: "AegisTokens"

    // ── Accent & inks ──────────────────────────────────────────────
    readonly property color accent: "#3E8BFF"
    readonly property color ink: "#101216"
    readonly property color inkDeep: "#08090C"
    readonly property color paper: "#F2F4F8"

    // ── Foreground pair — dark rung default, light rung on request ─
    // (M2 surfaces read these; the full light-theme audit is M4.)
    readonly property color fg: Util.darkMode ? paper : ink
    readonly property color fgMuted: Util.darkMode ? Qt.rgba(1, 1, 1, 0.55)
                                                   : Qt.rgba(0, 0, 0, 0.55)

    // ── Top panel (§2.1, Table 3) ─────────────────────────────────
    readonly property int panelHeight: 28

    // ── Floating dock (§2.2, Table 4 + v1.4 user override) ────────
    // v1.4 (user): "This is the kind of dock i like" — real macOS dock
    // geometry: 64 px icons, tight pitch, wide smooth magnification,
    // always-visible light glass tray (no auto-hide), hugging the edge.
    readonly property int dockMargin: 6             // px above bottom edge
    // v1.5 (user): "like macOS but in small size" — 48 px icons. The tray
    // reads as a dock again (≈62% of a 1280 px screen with the default 13
    // apps, was ≈95%), and the §2.2 magnification numbers are restored.
    readonly property int tileWidth: 58             // B
    readonly property int tileHeight: 68
    readonly property int tileRadius: 13
    readonly property int tileGap: 2                // macOS-tight packing
    readonly property int trayRadius: 22            // capsule radius
    readonly property int trayPadding: 10           // capsule inner padding
    readonly property int iconSize: 48
    readonly property real magPeak: 1.85            // 1.85·B at d = 0 (§2.2)
    readonly property real magFalloff: 2.4          // falloff over ±2.4 tiles
    readonly property real magStrength: 0.85
    // spring-mass solver, §2.2 step 3 (mass 0.1 · stiffness 170 · damping 13)
    readonly property real dockSpringMass: 0.1
    readonly property real dockSpringStiffness: 170
    readonly property real dockSpringDamping: 13
    // running dot — 4 px, floats 4 px clear of the icon
    readonly property int dotSize: 4
    readonly property int dotGap: 4
    // sliver — 120×4 pill, probe = bottom 8 px held for 150 ms
    readonly property int sliverWidth: 120
    readonly property int sliverHeight: 4
    readonly property int sliverProbeZone: 8
    readonly property int sliverProbeMs: 150
    readonly property int sliverSpringMs: 350
    // auto-hide after idle — DISABLED (0): the user's macOS dock is always
    // visible; Esc still folds to the sliver, bottom-edge probe reopens.
    readonly property int idleHideMs: 0
    // launch bounce — y keyframes [0, −0.32B, 0, −0.12B, 0] over 0.65 s
    readonly property real bounceHopHigh: 0.32
    readonly property real bounceHopLow: 0.12
    readonly property int bounceMs: 650

    // ── Dynamic Island (§2.4, Table 5b + v1.4 override) ───────────
    // v1.4 (user): idle capsule shrank from the proposal's 148×30 to the
    // iPhone Pro-class pill (~1.5 cm wide ≈ 104×32 px at 1× density).
    // Split and Charging track the idle height; radius tracks height (r = h/2,
    // capped at 32) so the capsule never pinches.
    // M2: states are data rows — the Live Activity API maps an activity
    // kind to one record here; timer and generic were added without
    // touching the geometry engine (§2.4: "a new activity type is a data
    // row, not new code").
    readonly property int islandIdleWidth: 104
    readonly property int islandIdleHeight: 32
    readonly property int islandTopMargin: panelHeight + 2
    // morph spring — mass 1 · stiffness 420 · damping 28 (the Apple "boing")
    readonly property real islandSpringMass: 1.0
    readonly property real islandSpringStiffness: 420
    readonly property real islandSpringDamping: 28
    readonly property int islandMaxRadius: 32
    readonly property int islandCrossfadeMs: 140
    readonly property int islandCrossfadeDelayMs: 90
    readonly property var islandStates: ({
        idle:       { w: islandIdleWidth,          h: islandIdleHeight,   r: islandIdleHeight / 2 },
        nowPlaying: { w: 356,                      h: 96,                 r: 32 },
        split:      { w: 128 + 8 + 104,            h: islandIdleHeight,   r: islandIdleHeight / 2 },
        call:       { w: 300,                      h: 64,                 r: 32 },
        charging:   { w: 216,                      h: islandIdleHeight,   r: islandIdleHeight / 2 },
        aegisId:    { w: 200,                      h: 56,                 r: 28 },
        timer:      { w: 200,                      h: 56,                 r: 28 },
        generic:    { w: 300,                      h: 56,                 r: 28 }
    })

    // ── Panel Glass (§3, Table 7 — dark rung; blur is KWin's job) ──
    readonly property color glassTint: Qt.rgba(16/255, 16/255, 18/255, 0.52)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.14)   // hairline, 1 px, never scales
    readonly property color glassHighlight: Qt.rgba(1, 1, 1, 0.10)
    // dock tray — light glass over any wallpaper (macOS dark-mode dock look)
    readonly property color dockGlassTint: Qt.rgba(1, 1, 1, 0.13)
    readonly property color dockGlassBorder: Qt.rgba(1, 1, 1, 0.26)
    readonly property color dockGlassHighlight: Qt.rgba(1, 1, 1, 0.30)
    // light rung — used by M2 surfaces when Dark Mode is off (audit in M4)
    readonly property color glassTintLight: Qt.rgba(244/255, 246/255, 250/255, 0.55)
    readonly property color glassBorderLight: Qt.rgba(0, 0, 0, 0.10)
    readonly property int glassBlurPx: 28
    readonly property real glassSaturation: 1.6
    readonly property real glassBrightness: 1.06

    // ── Motion (§4, Table 9 — six tokens, nothing outside them) ───
    readonly property int durInstant: 80     // fades, reduced-motion replacement
    readonly property int durQuick: 120      // hovers, tile lifts
    readonly property int durStandard: 180   // sheets, panel reveal
    readonly property int durSmooth: 240     // window open/close, dock fold
    readonly property int durSpring: 350     // dock spring from sliver, magnify
    readonly property int durFlow: 420       // workspace swipe, Glass Fold

    function islandRadius(height) {
        return Math.min(height / 2, islandMaxRadius)
    }
}

