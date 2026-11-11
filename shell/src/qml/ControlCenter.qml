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
    height: 446
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
            radius: 22
            color: Governor.tier === "C"
                   ? Qt.rgba(16/255, 16/255, 18/255, 0.94)
                   : (Util.darkMode ? Tokens.glassTint : Tokens.glassTintLight)
            border.width: 1
            border.color: Util.darkMode ? Tokens.glassBorder
                                        : Tokens.glassBorderLight

            // inner top highlight — the light source (§3 layer 4)
            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 1
                    leftMargin: 22
                    rightMargin: 22
                }
                height: 1
                color: Tokens.glassHighlight
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── header: title ─────────────────────────────
                Item {
                    width: parent.width
                    height: 30

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Control Center"
                        color: Tokens.fg
                        font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
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
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 12
                            width: parent.width

                            CcTile {
                                label: "Wi-Fi"
                                checked: Util.wifiEnabled
                                painter: ccRoot.paintWifi
                                onToggled: Util.setWifiEnabled(!Util.wifiEnabled)
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
                                        Governor.setAutoMode(true)
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

                        // fifth tile — Do Not Disturb (Table 17 footnote)
                        CcTile {
                            label: "Do Not Disturb"
                            checked: Activity.dnd
                            painter: ccRoot.paintBell
                            wide: true
                            onToggled: Activity.dnd = !Activity.dnd
                        }

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

                        // power row — Table 17 row height, airy hit targets
                        Row {
                            width: parent.width
                            height: 36
                            spacing: 10

                            Repeater {
                                model: [
                                    { label: "Suspend",   action: "suspend" },
                                    { label: "Restart",   action: "reboot" },
                                    { label: "Shut Down", action: "shutdown" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    width: (parent.width - 20) / 3
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
                }
            }
        }
    }

    SequentialAnimation {
        id: springIn

        ParallelAnimation {
            NumberAnimation {
                target: drop
                property: "y"
                from: -2
                to: 0
                duration: Tokens.durSpring
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: sheet
                property: "scale"
                from: 0.96
                to: 1
                duration: Tokens.durSpring
                easing.type: Easing.OutBack
                easing.overshoot: 1.35
            }
            NumberAnimation {
                target: sheet
                property: "opacity"
                from: 0
                to: 1
                duration: Tokens.durInstant
            }
        }
    }

    // ── mono glyphs (Canvas — no emoji, no theme dependency) ────────

    function paintWifi(ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.6
        ctx.lineCap = "round"
        const cx = w / 2, cy = h / 2 + 3.5
        for (let i = 1; i <= 3; ++i) {
            ctx.beginPath()
            ctx.arc(cx, cy, i * 3.4, Math.PI * 1.25, Math.PI * 1.75, false)
            ctx.stroke()
        }
        ctx.beginPath()
        ctx.arc(cx, cy, 1.6, 0, Math.PI * 2)
        ctx.fill()
    }

    function paintBluetooth(ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.lineWidth = 1.6
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        const cx = w / 2
        ctx.beginPath()
        ctx.moveTo(cx, 2)
        ctx.lineTo(cx, h - 2)
        ctx.moveTo(cx, 2)
        ctx.lineTo(cx + 4.5, 6.5)
        ctx.lineTo(cx - 4.5, h - 6.5)
        ctx.moveTo(cx, h - 2)
        ctx.lineTo(cx + 4.5, h - 6.5)
        ctx.lineTo(cx - 4.5, 6.5)
        ctx.stroke()
    }

    function paintMoon(ctx, w, h, color) {
        ctx.reset()
        ctx.fillStyle = color
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        ctx.arc(cx, cy, 7, 0, Math.PI * 2)
        ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        ctx.beginPath()
        ctx.arc(cx + 3.5, cy - 2.5, 6.5, 0, Math.PI * 2)
        ctx.fill()
        ctx.globalCompositeOperation = "source-over"
    }

    function paintHalf(ctx, w, h, color) {
        ctx.reset()
        const cx = w / 2, cy = h / 2
        ctx.fillStyle = color
        ctx.beginPath()
        ctx.arc(cx, cy, 6.5, -Math.PI / 2, Math.PI / 2)
        ctx.closePath()
        ctx.fill()
        ctx.strokeStyle = color
        ctx.lineWidth = 1.4
        ctx.beginPath()
        ctx.arc(cx, cy, 6.5, 0, Math.PI * 2)
        ctx.stroke()
    }

    // Bell — the W13 wide-tile glyph, redrawn: a true bell silhouette
    // (nub, flaring dome, straight lip, clapper) on the 2 px stroke
    // family. DND on fills the dome solid in the accent; off is outline.
    function paintBell(ctx, w, h, color, checked) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 2
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        const cx = w / 2
        // top nub — sits on the dome crown
        ctx.beginPath()
        ctx.arc(cx, 3.4, 1.3, 0, Math.PI * 2)
        ctx.fill()
        // dome — narrow crown, trumpet flare to the lip
        ctx.beginPath()
        ctx.moveTo(cx - 1.5, 4.9)
        ctx.bezierCurveTo(cx - 4.2, 6.0, cx - 3.3, 9.0, cx - 5.2, 12.6)
        ctx.lineTo(cx + 5.2, 12.6)
        ctx.bezierCurveTo(cx + 3.3, 9.0, cx + 4.2, 6.0, cx + 1.5, 4.9)
        ctx.closePath()
        if (checked)
            ctx.fill()
        else
            ctx.stroke()
        // lip — a hair wider than the dome feet
        ctx.beginPath()
        ctx.moveTo(cx - 6.0, 12.6)
        ctx.lineTo(cx + 6.0, 12.6)
        ctx.stroke()
        // clapper
        if (!checked) {
            ctx.beginPath()
            ctx.arc(cx, 14.6, 1.5, Math.PI * 0.15, Math.PI * 0.85)
            ctx.stroke()
        }
    }

    function paintSun(ctx, w, h, color) {
        ctx.reset()
        ctx.fillStyle = color
        ctx.strokeStyle = color
        ctx.lineWidth = 1.4
        ctx.lineCap = "round"
        const cx = w / 2, cy = h / 2
        ctx.beginPath()
        ctx.arc(cx, cy, 3.2, 0, Math.PI * 2)
        ctx.fill()
        for (let i = 0; i < 8; ++i) {
            const a = i * Math.PI / 4
            ctx.beginPath()
            ctx.moveTo(cx + Math.cos(a) * 5.2, cy + Math.sin(a) * 5.2)
            ctx.lineTo(cx + Math.cos(a) * 7.8, cy + Math.sin(a) * 7.8)
            ctx.stroke()
        }
    }

    function paintSpeaker(ctx, w, h, color, muted) {
        ctx.reset()
        ctx.fillStyle = color
        ctx.strokeStyle = color
        ctx.lineWidth = 1.5
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        const cx = w / 2 - 2, cy = h / 2
        ctx.beginPath()
        ctx.moveTo(cx - 5, cy - 2.5)
        ctx.lineTo(cx - 2, cy - 2.5)
        ctx.lineTo(cx + 2, cy - 6.5)
        ctx.lineTo(cx + 2, cy + 6.5)
        ctx.lineTo(cx - 2, cy + 2.5)
        ctx.lineTo(cx - 5, cy + 2.5)
        ctx.closePath()
        ctx.fill()
        if (muted) {
            ctx.beginPath()
            ctx.moveTo(cx + 4.5, cy - 3.5)
            ctx.lineTo(cx + 9, cy + 3.5)
            ctx.moveTo(cx + 9, cy - 3.5)
            ctx.lineTo(cx + 4.5, cy + 3.5)
            ctx.stroke()
        } else {
            ctx.beginPath()
            ctx.arc(cx + 3.5, cy, 3, -Math.PI / 3, Math.PI / 3)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cx + 3.5, cy, 6, -Math.PI / 3, Math.PI / 3)
            ctx.stroke()
        }
    }

    // ── inline components ────────────────────────────────────────────

    // W13 — the wide tile is the macOS wide-toggle pattern: bell + label
    // left-aligned, a real switch at the right end. The tile stays glass;
    // the switch carries the accent state. Narrow tiles keep the centered
    // icon-above-label look and fill with the accent when checked.
    component CcTile: Rectangle {
        property string label
        property bool checked
        property bool wide: false
        property var painter
        signal toggled()

        width: wide ? (parent ? parent.width : 320)
                    : ((parent ? parent.width : 320) - 12) / 2
        height: wide ? 44 : 64
        radius: 16
        color: !wide && checked ? Tokens.accent
                                : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.07)
                                                 : Qt.rgba(0, 0, 0, 0.05))
        border.width: 1
        border.color: (!wide && checked) ? Qt.rgba(1, 1, 1, 0.25)
                                         : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.10)
                                                          : Qt.rgba(0, 0, 0, 0.08))
        Behavior on color {
            ColorAnimation { duration: ccRoot.dur(Tokens.durQuick) }
        }

        // the WHOLE tile toggles — wide tiles included. The v0.6.20 boot
        // test caught the regression: this MouseArea carried visible: !wide,
        // so the Do Not Disturb tile body was dead and only the 36x20
        // switch responded — five tags shipped identical "DND on" captures
        // because the capture clicks the tile body. Declared FIRST so the
        // narrow column and the wide content row stack above it and the
        // switch keeps its own hit area.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggled()
        }

        // narrow tile — icon above label, centered
        Column {
            visible: !wide
            anchors.centerIn: parent
            spacing: 5

            Canvas {
                width: 18
                height: 18
                onPaint: if (painter)
                    painter(getContext("2d"), width, height,
                            checked ? "#FFFFFF"
                                    : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.85)
                                                     : Qt.rgba(0, 0, 0, 0.72)),
                            checked)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: label
                color: checked ? "#FFFFFF" : Tokens.fg
                font { family: "Montserrat"; pixelSize: 10; weight: Font.Medium }
            }
        }

        // wide tile — content row: icon + label left, switch right
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
                        ColorAnimation { duration: ccRoot.dur(Tokens.durQuick) }
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

    // W13 — anchor layout: both tracks end at the SAME right margin
    component CcSlider: Item {
        property var painter
        property bool muted: false
        property alias value: slider.value
        property alias enabled: slider.enabled
        signal committed()

        width: parent ? parent.width : 320
        height: 32

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

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.14)
                                     : Qt.rgba(0, 0, 0, 0.12)

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Tokens.accent
                }
            }

            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * slider.availableWidth - 7
                y: slider.topPadding + slider.availableHeight / 2 - 7
                width: 14
                height: 14
                radius: 7
                color: "#FFFFFF"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.2)
            }
        }
    }
}
