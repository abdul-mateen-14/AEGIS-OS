import QtQuick
import QtQuick.Controls
import Aegis.Util
import Aegis.Governor
import Aegis.Activity

// Control Center — a 348 px glass sheet hanging 12 px below the panel
// (proposal chapter 07, Plate 3 + Table 17 geometry).
//
// Four tiles toggle Wi-Fi, Bluetooth, Calm Mode and Dark Mode; the fifth
// wide tile is Do Not Disturb (banners then stack silently). Display and
// Sound sliders carry brightness and volume with 16 px mono glyphs. The
// footer links All Settings and Software Update. (T8 — the TIER chip and
// its governor popover were debug chrome: performance belongs to Calm Mode
// in the tile grid, not to a status chip that read as a build label.)
//
// Entry: spring 350 ms — sheet scales 0.96 → 1 with a 2 px drop, scrim
// fade skipped (the panel is already glass). Exit: instant (80 ms).
// Tier C fallback rung: opaque 94% tint + 80 ms crossfades.
Window {
    // KWin's alt+F4 must never destroy a shell surface: with no app window
    // focused, the focused layer surface receives the close and would die
    // (dock -> island -> panel cascade, observed on the v0.6.5 boot test).
    onClosing: (close) => { close.accepted = false }
    objectName: "ccWindow"
    id: ccRoot
    visible: Util.ccOpen
    color: "transparent"
    width: 348
    // W13 — Table 17 rhythm: 16 px margins, 12 px separations, snug height
    // (the old 452 left a dead band under the footer).
    // W68 — 446 -> 388: one row of four 64 px circles + captions replaces
    // the two 64 px rectangle rows; the sheet keeps the snug fit.
    // W69 — 388 -> 394: the two slider rows grow 32 -> 36 for the pill.
    // W70 — 394 -> 434: three 1 px section rules ride the 12 px flow.
    height: 434
    flags: Qt.FramelessWindowHint

    // Tier C shortens every motion token — Table 17 fallback rung.
    function dur(std) {
        return Governor.tier === "C" ? Tokens.durInstant : std
    }

    onVisibleChanged: {
        if (visible) {
            Util.refreshLinkStates()
            springIn.restart()
        }
    }

    Item {
        anchors.fill: parent
        transform: Translate { id: drop; y: 0 }

        Rectangle {
            id: sheet

            anchors.fill: parent
            // §5.4 — the Sonoma "sheet unclipping" tell: the sheet enters
            // at radius 22 and settles to the material's 18 over the first
            // 120 ms of the window's visibility.
            radius: (Window.window && Window.window.visible) ? 18 : 22
            Behavior on radius {
                NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
            }
            // §5.1 rung A — Sheet Glass (46% ink; sheets read thinner once
            // blur lands, W50). T20 — the Calm rung is flat AND opaque
            // (no compositor blur in tier C), but "flat" never means
            // "dark in light mode": the plate swaps with darkMode or the
            // ink text rides on ink glass (the v0.6.62 report: the CC
            // unreadable in light mode with Calm on).
            color: Governor.tier === "C"
                   ? (Util.darkMode ? Qt.rgba(16/255, 16/255, 18/255, 0.94)
                                    : Qt.rgba(244/255, 246/255, 250/255, 0.94))
                   : (Util.darkMode ? Tokens.sheetTint : Tokens.sheetTintLight)
            border.width: 1
            border.color: Util.darkMode ? Tokens.sheetBorder
                                        : Tokens.glassBorderLight

            // §5.2 layer (1) — top highlight band, the light source
            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 1
                    leftMargin: 18
                    rightMargin: 18
                }
                height: 8
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, ccRoot.sheen) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.02) }
                }
            }

            // W67 — the luminosity-adaptive scrim: white ink lowers text
            // contrast on bright wallpaper bands, so a 1-stop black wash
            // (0.10 at the header fading out by 40% height) rises BEHIND
            // the text rows only when the wallpaper under the sheet is
            // bright (Util.backdropLuminance > 140). Declared after the
            // highlight and before the content Column: it tints the glass,
            // never the glyphs. The probe asserts fg-vs-plate contrast
            // from the capture; this is the shell-side half of that rule.
            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 1
                    leftMargin: 1
                    rightMargin: 1
                }
                height: parent.height * 0.4
                visible: Util.darkMode && Util.backdropLuminance() > 140
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.10) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── header: mark + title ──────────────────────
                // D6 — the CC header carries the 18 px mark (reviewer
                // carry-over on v0.6.34; the v1.3 ruling stands)
                Item {
                    width: parent.width
                    height: 30

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Image {
                            source: Util.darkMode ? "aegis-mark.png"
                                                  : "aegis-mark-ink.png"
                            sourceSize: Qt.size(18, 18)
                            width: 18; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Control Center"
                            color: Tokens.fg
                            font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // ── main pane: tiles ──────────────────────────
                Column {
                    width: parent.width
                    spacing: 12

                    // ============ tiles pane ============
                    Column {
                        width: parent.width
                        spacing: 12

                        Grid {
                            // W68 — one row of four glass circles (the
                            // mockup's connectivity group; the 2x2 sketch
                            // was superseded by the approved render)
                            columns: 4
                            columnSpacing: 12
                            rowSpacing: 12
                            width: parent.width

                            // T15-D6 (W43) — the tile tells the story the
                            // machine actually has. A radio-less VM (NAT =
                            // ethernet) shows the wired glyph + accent when
                            // connected and toggles Disconnect/Reconnect —
                            // CC and Settings agree.
                            CcTile {
                                label: Util.hasWifi ? "Wi-Fi" : "Ethernet"
                                checked: Util.hasWifi
                                         ? Util.wifiEnabled
                                         : Util.wiredConnected
                                painter: Util.hasWifi ? ccRoot.paintWifi
                                                      : ccRoot.paintWired
                                onToggled: {
                                    if (Util.hasWifi)
                                        Util.setWifiEnabled(!Util.wifiEnabled)
                                    else if (Util.wiredConnected)
                                        Util.disconnectWired(Util.wiredIface)
                                    else
                                        Util.reconnectWired(Util.wiredIface)
                                }
                            }
                            CcTile {
                                label: "Bluetooth"
                                checked: Util.bluetoothEnabled
                                painter: ccRoot.paintBluetooth
                                onToggled: Util.setBluetoothEnabled(!Util.bluetoothEnabled)
                            }
                            // M3 — Calm Mode is now the full contract: the tile
                            // pins the governor to Tier C (80 ms rung swaps) AND
                            // sets Activity.calm, which quiets banners (dnd comes
                            // with calm in the service) and collapses the panel
                            // chrome. Off: tier machine back to auto; dnd keeps
                            // the user's own switch.
                            CcTile {
                                label: "Calm Mode"
                                checked: Activity.calm
                                painter: ccRoot.paintMoon
                                onToggled: {
                                    if (Activity.calm) {
                                        Activity.calm = false
                                        // W41 vmware bug report (2026-11-17):
                                        // "tapping on calm doesn't reverse it".
                                        // The old off-branch re-enabled auto
                                        // mode — on a software rasterizer
                                        // (VMware llvmpipe) every animated
                                        // frame violates the 22 ms rung, so
                                        // the machine demoted straight back
                                        // to C within 2 s and the exit looked
                                        // one-way. Leaving Calm is an explicit
                                        // user choice: PIN Tier A (the battery
                                        // rule still overrides a pin —
                                        // evaluate() checks batteryCalm before
                                        // any pinned tier). Auto mode stays
                                        // the default at startup.
                                        Governor.setTier("A")
                                    } else {
                                        Activity.calm = true
                                        Governor.setTier("C")
                                    }
                                }
                            }
                            CcTile {
                                label: "Dark Mode"
                                checked: Util.darkMode
                                painter: ccRoot.paintHalf
                                onToggled: Util.setDarkMode(!Util.darkMode)
                            }
                        }

                        // W70 — hairline separators: 1 px white 0.14
                        // (never scales — the glassBorder rule) between
                        // the CC sections; they are what makes a glass
                        // plate read as organized glass rather than a
                        // floating gray box.
                        component SectionRule: Rectangle {
                            width: parent ? parent.width : 0
                            height: 1
                            color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.14)
                                                 : Qt.rgba(0, 0, 0, 0.10)
                        }

                        SectionRule { }

                        // fifth tile — Do Not Disturb (Table 17 footnote)
                        CcTile {
                            label: "Do Not Disturb"
                            checked: Activity.dnd
                            painter: ccRoot.paintBell
                            wide: true
                            onToggled: Activity.dnd = !Activity.dnd
                        }

                        SectionRule { }

                        // sliders — Display + Sound, 16 px mono glyphs
                        CcSlider {
                            painter: ccRoot.paintSun
                            value: Math.max(0, Util.brightness)
                            enabled: Util.brightness >= 0
                            onCommitted: Util.setBrightness(value)
                        }
                        CcSlider {
                            painter: ccRoot.paintSpeaker
                            value: Util.muted ? 0 : Math.min(1.0, Util.volume)
                            muted: Util.muted
                            onCommitted: {
                                if (Util.muted)
                                    Util.setMuted(false)
                                Util.setVolume(value)
                            }
                        }

                        SectionRule { }

                        // power row — Table 17 row height, airy hit targets
                        Row {
                            width: parent.width
                            height: 36
                            spacing: 10

                            Repeater {
                                // W41 — "Lock Screen" leads the row (macOS
                                // order). The row sits BELOW the sliders, so
                                // adding the fourth button cannot shift the
                                // w66 calibrated strip; the row height (36)
                                // is unchanged.
                                model: [
                                    { label: "Lock Screen", action: "lock" },
                                    { label: "Suspend",   action: "suspend" },
                                    { label: "Restart",   action: "reboot" },
                                    { label: "Shut Down", action: "shutdown" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    width: (parent.width - 30) / 4
                                    height: 36
                                    radius: 10
                                    color: powerMa.containsMouse
                                           ? (Util.darkMode ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.06))
                                           : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.label
                                        color: Tokens.fgMuted
                                        font { family: "Montserrat"; pixelSize: 11 }
                                    }
                                    MouseArea {
                                        id: powerMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Util.ccOpen = false
                                            Util.powerAction(parent.modelData.action)
                                        }
                                    }
                                }                            }
                        }
                    }

                }

                // ── footer: All Settings + session echo (mono) ────────
                Item {
                    width: parent.width
                    height: 26

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "All Settings"
                        color: Tokens.accent
                        font { family: "Montserrat"; pixelSize: 11 }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Util.ccOpen = false
                                Util.launch("aegis-settings")   // first-party Settings (aegis-apps)
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Software Update"
                        color: Tokens.accent
                        font { family: "Montserrat"; pixelSize: 11 }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Util.ccOpen = false
                                Util.launch("aegis-updates")
                            }
                        }
                    }

                    // W63 companion — the live tier badge (chapter 06:
                    // "the tier badge in Control Center updates live").
                    // T8 retired the old TIER chip + governor popover as
                    // debug chrome, but the proposal's clause stands: the
                    // badge binds Governor.tier / Governor.autoMode (live
                    // on tierChanged) and clicking deep-links the Desktop
                    // Effects pane ("aegis-settings 2"), where every
                    // effect key has its row (W66).
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TIER " + Governor.tier
                              + (Governor.autoMode ? "" : " · PINNED")
                        color: Tokens.fgMuted
                        font {
                            family: "Montserrat"; pixelSize: 10
                            weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Util.ccOpen = false
                                Util.launch("aegis-settings 2")
                            }
                        }
                    }
                }
            }
        }
    }

    // W71 — the liquid entrance: the plate ARRIVES. Scale 0.96 -> 1 +
    // opacity over 200 ms (governor-gated: tier C lands at 80 ms instant,
    // the Table 17 fallback rule), anchored to the island's bottom edge
    // via the existing 2 px drop. The v1.6 OutBack overshoot reads as a
    // bounce, not a liquid arrival — OutCubic is the kit's ease.
    // Blur-in is the honest cut: per-window blur strength has no KWin
    // animation API, and faking it with a shader breaks the no-shader
    // rule — the scale+opacity+sheen carry the arrival.
    property real sheen: 0.12

    SequentialAnimation {
        id: springIn

        ParallelAnimation {
            NumberAnimation {
                target: drop
                property: "y"
                from: -2
                to: 0
                duration: ccRoot.dur(200)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: sheet
                property: "scale"
                from: 0.96
                to: 1
                duration: ccRoot.dur(200)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: sheet
                property: "opacity"
                from: 0
                to: 1
                duration: ccRoot.dur(160)
            }
        }
        // the sheen sweep — one gradient stop's alpha 0.12 -> 0.18 ->
        // 0.12 over 600 ms: a light pass across the glass, no shader
        SequentialAnimation {
            NumberAnimation {
                target: ccRoot
                property: "sheen"
                from: 0.12
                to: 0.18
                duration: ccRoot.dur(300)
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: ccRoot
                property: "sheen"
                from: 0.18
                to: 0.12
                duration: ccRoot.dur(300)
                easing.type: Easing.InOutQuad
            }
        }
    }

    // ── mono glyphs — DELEGATED to Glyphs (v0.6.81, the reviewer's icon
    // pack): the geometry lives ONLY in Glyphs.qml now, emitted from the
    // same 24-grid masters as the SVG/PNG pack (the guide §1(b) "one
    // glyph, two geometries" duplication dies). Same function names and
    // signatures — every call site above keeps working; the CC's local
    // 1.6 px family is replaced by the pack's 2.2 px tile family at the
    // 26 px optical size.

    function paintWifi(ctx, w, h, color) { Glyphs.wifi(ctx, w, h, color) }

    function paintWired(ctx, w, h, color) { Glyphs.wired(ctx, w, h, color) }

    function paintBluetooth(ctx, w, h, color) {
        Glyphs.bluetooth(ctx, w, h, color)
    }

    function paintMoon(ctx, w, h, color) { Glyphs.moon(ctx, w, h, color) }

    function paintHalf(ctx, w, h, color) { Glyphs.half(ctx, w, h, color) }

    function paintBell(ctx, w, h, color, checked) {
        Glyphs.bell(ctx, w, h, color, checked)
    }

    function paintSun(ctx, w, h, color) { Glyphs.sun(ctx, w, h, color) }

    function paintSpeaker(ctx, w, h, color, muted) {
        Glyphs.speaker(ctx, w, h, color, muted)
    }

    // ── inline components ────────────────────────────────────────────

    // W13 — the wide tile is the macOS wide-toggle pattern: bell + label
    // left-aligned, a real switch at the right end. The tile stays glass;
    // the switch carries the accent state. Narrow tiles keep the centered
    // icon-above-label look and fill with the accent when checked.
    // W68 — narrow tiles are 64 px glass circles in ONE row of four (the
    // mockup's connectivity group: 4 circles, 12 px gaps — the sheet's
    // 316 px inner width holds 4x64 + 3x12 exactly). The checked state is
    // iOS 26's active toggle: solid accent, white glyph, no half-measures;
    // unchecked is the sheet's own glass — white 0.12 under the v1.7 ink
    // flip — with a 0.22 hairline rim. Captions (W70: 11 px semibold
    // white/85) live UNDER the circle. The wide DND card stays a
    // radius-18 glass card with its 36x20 switch row.
    component CcTile: Item {
        id: ccTile
        property string label
        property bool checked
        property bool wide: false
        property var painter
        signal toggled()

        width: wide ? (parent ? parent.width : 320)
                    : ((parent ? parent.width : 320) - 36) / 4
        height: wide ? 44 : 82

        // the WHOLE tile toggles — wide tiles included. The v0.6.20 boot
        // test caught the regression: this MouseArea once carried
        // visible: !wide, so the DND tile body was dead and only the
        // switch responded — five tags shipped identical "DND on"
        // captures. Declared FIRST so the wide switch keeps its own hit
        // area above it.
        MouseArea {
            id: tileClick
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggled()
        }

        HoverHandler {
            id: tileHover
            cursorShape: Qt.PointingHandCursor
        }

        // W71 — press feedback: the tile dips to 0.94 on press and
        // springs back over 80 ms (the same OutQuad family; tier C's
        // durInstant keeps it readable). Read off the tile's own
        // MouseArea (tileClick) — no second grab.
        property bool pressed: tileClick.pressed

        // W80 — a QML Canvas only paints when something calls
        // requestPaint(): the first paint is correct, but a checked flip
        // or a dark-mode flip re-binds the plate and leaves the OLD ink
        // on it (the v0.6.83 report: the Ethernet circle kept a dark
        // plug after a state flip). Repaint both glyphs on every state
        // that feeds their paint.
        onCheckedChanged: {
            glyphNarrow.requestPaint()
            wideGlyph.requestPaint()
        }
        onPainterChanged: {
            glyphNarrow.requestPaint()
            wideGlyph.requestPaint()
        }
        Connections {
            target: Util
            function onDarkModeChanged() {
                glyphNarrow.requestPaint()
                wideGlyph.requestPaint()
            }
        }

        Rectangle {
            id: plate
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            width: wide ? parent.width : 64
            height: wide ? parent.height : 64
            radius: wide ? 18 : 32
            // §5.4 — tiles answer the pointer: scale 1.02 (90 ms OutQuad)
            scale: ccTile.pressed ? 0.94
                                  : (tileHover.hovered ? 1.02 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: ccRoot.dur(80); easing.type: Easing.OutQuad }
            }
            color: (!wide && checked)
                       ? Tokens.accent
                       : (Util.darkMode
                              ? (tileHover.hovered ? Qt.rgba(1, 1, 1, 0.18)
                                                   : Qt.rgba(1, 1, 1, 0.12))
                              : (tileHover.hovered ? Qt.rgba(0, 0, 0, 0.04)
                                                   : Qt.rgba(0, 0, 0, 0.06)))
            border.width: 1
            border.color: (!wide && checked) ? Qt.rgba(1, 1, 1, 0.25)
                                             : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.22)
                                                              : Qt.rgba(0, 0, 0, 0.08))
            Behavior on color {
                ColorAnimation { duration: ccRoot.dur(Tokens.durQuick) }
            }

            // narrow — the 26 px glyph alone rides the circle (the pack's
            // 2.2 px stroke family); white 0.92 unchecked (W68), white on
            // accent checked
            Canvas {
                id: glyphNarrow
                visible: !wide
                anchors.centerIn: parent
                width: 26
                height: 26
                onPaint: if (painter)
                    painter(getContext("2d"), width, height,
                            checked ? "#FFFFFF"
                                    : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.92)
                                                     : Qt.rgba(0, 0, 0, 0.72)),
                            checked)
            }

            // wide — content row: icon + label left, switch right
            Item {
                visible: wide
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                Canvas {
                    id: wideGlyph
                    width: 18
                    height: 18
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: if (painter)
                        painter(getContext("2d"), width, height,
                                checked ? Tokens.accent
                                        : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.85)
                                                         : Qt.rgba(0, 0, 0, 0.72)),
                                checked)
                }

                Text {
                    text: label
                    color: Tokens.fg
                    elide: Text.ElideRight
                    font { family: "Montserrat"; pixelSize: 11; weight: Font.Medium }
                    anchors.left: wideGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: dndSwitch.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                }

                // 36×20 switch — knob rides the state with the standard easing
                Item {
                    id: dndSwitch
                    width: 36
                    height: 20
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: checked ? Tokens.accent
                                       : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.14)
                                                        : Qt.rgba(0, 0, 0, 0.12))
                        border.width: 1
                        border.color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.10)
                                                    : Qt.rgba(0, 0, 0, 0.08)
                        Behavior on color {
                            ColorAnimation {
                                duration: ccRoot.dur(Tokens.durQuick)
                            }
                        }
                    }

                    Rectangle {
                        x: checked ? parent.width - 18 : 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        color: "#FFFFFF"
                        Behavior on x {
                            NumberAnimation {
                                duration: ccRoot.dur(Tokens.durStandard)
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: toggled()
                    }
                }
            }
        }

        // W70 caption — under the circle, horizontal-fit (Calm Mode is the
        // long one and must not ellipsize at 1x)
        Text {
            visible: !wide
            anchors {
                top: plate.bottom
                topMargin: 4
                horizontalCenter: plate.horizontalCenter
            }
            width: ccTile.width
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            text: label
            color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.85)
                                 : Qt.rgba(0, 0, 0, 0.75)
            font { family: "Montserrat"; pixelSize: 11; weight: Font.DemiBold }
        }
    }

    
    // W13 — anchor layout: both tracks end at the SAME right margin
    component CcSlider: Item {
        property var painter
        property bool muted: false
        property alias value: slider.value
        property alias enabled: slider.enabled
        signal committed()

        width: parent ? parent.width : 320
        // W69 — the pill is fat: 28 px track in a 36 px row (the 16 px
        // mono glyphs ride vertically centered as before)
        height: 36

        // W80 — same stale-canvas ruling as the tiles: repaint the
        // glyph on every state that feeds its paint.
        onMutedChanged: sliderGlyph.requestPaint()
        onPainterChanged: sliderGlyph.requestPaint()
        Connections {
            target: Util
            function onDarkModeChanged() { sliderGlyph.requestPaint() }
        }

        Canvas {
            id: sliderGlyph
            width: 18
            height: 18
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            onPaint: if (painter)
                painter(getContext("2d"), width, height,
                        Util.darkMode ? Qt.rgba(1, 1, 1, 0.75)
                                      : Qt.rgba(0, 0, 0, 0.62),
                        muted)
        }

        Slider {
            id: slider
            anchors.left: sliderGlyph.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            from: 0
            to: 1
            stepSize: 0.01
            onMoved: committed()

            // W69 — glass pill sliders (the kit dropped accent-filled
            // levels: volume/brightness read as white liquid; accent
            // stays reserved for toggles and links — color = state,
            // white = level). Track 28 px radius 14, white 0.22 fill
            // (W80: 0.16 left the empty track nearly invisible against
            // the sheet — the brightness pill read as a hole), 0.18
            // hairline, the v1.6 lens-depth 2 px inner bottom shadow;
            // the level fills white 0.80 up to the knob (W80: 0.85 sat
            // one hairline from the 0.92 knob and the two merged into
            // one white slab at high values).
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - 14
                width: slider.availableWidth
                height: 28
                radius: 14
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.22)
                                     : Qt.rgba(0, 0, 0, 0.10)
                border.width: 1
                border.color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.18)
                                            : Qt.rgba(0, 0, 0, 0.14)

                // the level — white liquid up to the knob
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 14
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.80)
                                         : Qt.rgba(0, 0, 0, 0.55)
                }

                // lens depth — the v1.6 inner bottom shadow, pill-sized
                Rectangle {
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                        bottomMargin: 2
                        leftMargin: 6
                        rightMargin: 6
                    }
                    height: 2
                    color: Qt.rgba(0, 0, 0, 0.10)
                }
            }

            // W69 — the knob is a 24x20 rounded bar (radius 10), white
            // 0.92. W80 — its rim is INK on the dark rung: the old white
            // 0.25 rim vanished against the white level fill and the
            // knob disappeared into the slab at high values (the
            // volume pill read as one solid bar). macOS wears the same
            // dark rim on white knobs.
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * slider.availableWidth - 12
                y: slider.topPadding + slider.availableHeight / 2 - 10
                width: 24
                height: 20
                radius: 10
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.92) : "#FFFFFF"
                border.width: 1
                border.color: Util.darkMode ? Qt.rgba(0, 0, 0, 0.32)
                                            : Qt.rgba(0, 0, 0, 0.2)
            }
        }
    }
}
