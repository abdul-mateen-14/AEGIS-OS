pragma Singleton
import QtQuick
import Aegis.Util

// Aegis OS design tokens — the proposal's tables as code (docs/DESIGN-TOKENS.md
// maps every value back to its table). v1.3 defaults with one v1.4 override:
// the Dynamic Island idle capsule, shrank to the iPhone Pro-class pill.

QtObject {
    objectName: "AegisTokens"

    // ── Accent & inks ──────────────────────────────────────────────
    // W5 — the accent is THE settable token: it persists at
    // $XDG_CONFIG_HOME/aegis/tokens.conf and every surface (shell + both
    // apps) reads it from here. Six presets live in Settings → Appearance.
    property color accent: Util.accent
    readonly property color ink: "#101216"
    readonly property color inkDeep: "#08090C"
    readonly property color paper: "#F2F4F8"
    // Status danger — low-battery tint in the top bar (§2.1 right cluster)
    // and any destructive status readout. Same red as the Files kind tint.
    readonly property color danger: "#FA2D48"

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
    // v1.5 (user, pass 2): the tray HUGS the icons — tray = 48 + 2·6 + 4 =
    // 64 px, so the icon fills 75% of it (v1.3 reference plate: 79%). Was
    // 10 px padding → 72 px tray, icon at 67%: an airy box, not a shelf.
    readonly property int trayRadius: 18            // capsule radius — retuned for the 64 px tray
    readonly property int trayPadding: 6            // capsule inner padding
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

    // ── Panel Glass (§3, Table 7 — Liquid Glass v1.6 pass) ───────────
    // W50 — the backdrop blur is REAL: every glass surface requests it
    // through KWindowEffects::enableBlurBehind (org_kde_kwin_blur),
    // gated by Governor.blurLive / blurAny (W57).
    // LIQUID GLASS (v1.6, user ask: "truly transparent liquid glass
    // vibe in every section and everywhere" — the iOS 26 material):
    // every tint dropped ~40% (the wallpaper now reads THROUGH every
    // plate), and the shape is carried by the specular system instead
    // of the fill — brighter rims (GlassPanel), kwinrc BlurStrength=14,
    // and the app window bodies went translucent (0.84/0.86) so blur
    // shows through them too (apps-main already blurs the full window;
    // KWin manifests it only where alpha < 1). Tier C (0.94) stays the
    // deliberate calm-mode opacity — accessibility beats aesthetics
    // there.
    // LIQUID GLASS v1.7 (W67 — the ink flip): glass that sits on the
    // WALLPAPER carries WHITE-based ink and lets the saturated, blurred
    // backdrop supply the color and luminosity (the dock tray's white
    // 0.08 was the in-tree proof; the reference kit's plates are
    // 10-25% white ink). Glass that sits on CONTENT (the 44 px
    // titleband) keeps dark ink for contrast. v1.6's near-black
    // rgba(16,16,18,0.32) composited to a charcoal plate — the "liquid"
    // is the backdrop showing through, not the fill.
    readonly property color glassTint: Qt.rgba(1, 1, 1, 0.14)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.28)   // hairline, 1 px, never scales — carries the shape now that the plate is thin
    readonly property color glassHighlight: Qt.rgba(1, 1, 1, 0.18)
    // W80 — the TOP BAR rung (GlassPanel's panel default; the top panel
    // is its only user now that the dock tray/island wear "sheet"): INK
    // glass, not white-lens. The status glyphs are fg 0.9 — over a
    // bright wallpaper region the white-lens plate composited to a
    // washed grey band (the v0.6.83 report: the status strip read grey
    // over the same wallpaper that kept the dock tray dark). macOS
    // carries the same ink menubar; wallpaper surfaces keep the white
    // lens above.
    readonly property color barTint: Qt.rgba(16/255, 16/255, 18/255, 0.38)
    readonly property color barTintLight: Qt.rgba(244/255, 246/255, 250/255, 0.34)
    // dock tray — light glass over any wallpaper (macOS dark-mode dock look)
    readonly property color dockGlassTint: Qt.rgba(1, 1, 1, 0.08)
    readonly property color dockGlassBorder: Qt.rgba(1, 1, 1, 0.38)
    readonly property color dockGlassHighlight: Qt.rgba(1, 1, 1, 0.42)
    // light rung — used by M2 surfaces when Dark Mode is off (audit in M4).
    // W67 — 0.38 → 0.30 (more liquid; the light ink is already white-based).
    readonly property color glassTintLight: Qt.rgba(244/255, 246/255, 250/255, 0.30)
    readonly property color glassBorderLight: Qt.rgba(0, 0, 0, 0.16)

    // ── Material rungs (§5.1 — one system, three rungs, no per-screen
    // values). Blur amount / saturation / brightness per rung are the
    // compositor's stock blur job (glassBlurPx etc. below document the
    // spec); the tints here are what the shell paints.
    // Sheet Glass — CC sheet, calendar popover, launcher sheet, menus.
    // W67 ink flip: white 0.12 — slightly thinner than glassTint, the
    // rungs' relative ordering preserved from the dark-ink era.
    readonly property color sheetTint: Qt.rgba(1, 1, 1, 0.12)
    readonly property color sheetBorder: Qt.rgba(1, 1, 1, 0.30)
    readonly property color sheetTintLight: Qt.rgba(244/255, 246/255, 250/255, 0.32)
    // Chrome Glass — the AppWindow 44 px titleband only. Titlebars must
    // be MORE transparent than sheets; the window body stays opaque.
    // W67: STAYS dark ink (fd24476's ruling — the titleband sits on app
    // content, where the §0 rule says dark).
    readonly property color chromeTint: Qt.rgba(16/255, 16/255, 18/255, 0.20)
    readonly property color chromeBorder: Qt.rgba(1, 1, 1, 0.24)
    readonly property color chromeTintLight: Qt.rgba(244/255, 246/255, 250/255, 0.28)
    // dock tray — the 12 px vertical wash inside the top edge (§5.2;
    // formalizes the measured 56→52 top-to-bottom drift)
    readonly property color dockWash: Qt.rgba(1, 1, 1, 0.08)

    // W67 — the reference's color bleed is saturation-driven: the
    // compositor knobs notch up on tier A/B (kwinrc BlurStrength rides
    // 14 → 15, the stock effect's ceiling). Tier C's 0.94 opaque calm
    // plate is untouched — it is the readability fallback.
    readonly property int glassBlurPx: 40
    readonly property real glassSaturation: 2.0
    readonly property real glassBrightness: 1.12

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

