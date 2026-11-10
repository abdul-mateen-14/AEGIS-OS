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
// signature element is the tier badge — "TIER A · FULL EFFECTS" — wired
// to the adaptive effects governor; clicking it opens the governor
// popover. Performance is not a settings page the user will never find;
// it is a status the shell admits to in plain sight. The footer links
// All Settings and echoes the session in mono type.
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

    property bool governorOpen: false

    // Tier C shortens every motion token — Table 17 fallback rung.
    function dur(std) {
        return Governor.tier === "C" ? Tokens.durInstant : std
    }

    onVisibleChanged: {
        if (visible) {
            governorOpen = false
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

                // ── header: title + tier badge ────────────────────────
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

                    // the signature element — live governor tier (§7)
                    Rectangle {
                        id: tierBadge
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: badgeText.implicitWidth + 20
                        height: 24
                        radius: 12
                        color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                       Tokens.accent.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                              Tokens.accent.b, 0.35)

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: Governor.tier === "A" ? "TIER A · FULL EFFECTS"
                                  : Governor.tier === "B" ? "TIER B · BALANCED GLASS"
                                  : "TIER C · CALM MODE"
                            color: Util.darkMode ? "#8FB8FF" : "#2B66C8"
                            font { family: "Montserrat"; pixelSize: 9; letterSpacing: 0.6; weight: Font.DemiBold }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ccRoot.governorOpen = !ccRoot.governorOpen
                        }
                    }
                }

                // ── main pane: tiles OR governor popover ─────────────
                Column {
                    width: parent.width
                    spacing: 12

                    // ============ tiles pane ============
                    Column {
                        visible: !ccRoot.governorOpen
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
                            CcTile {
                                label: "Calm Mode"
                                checked: Governor.tier === "C"
                                painter: ccRoot.paintMoon
                                onToggled: Governor.tier === "C"
                                           ? Governor.setAutoMode(true)
                                           : Governor.setTier("C")
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

                    // ============ governor popover ============
                    Column {
                        visible: ccRoot.governorOpen
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Effects governor"
                            color: Tokens.fg
                            font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
                        }

                        Repeater {
                            model: [
                                { k: "A", name: "Full glass",
                                  desc: "Live blur · springs · full shadows" },
                                { k: "B", name: "Cached glass",
                                  desc: "Cached wallpaper blur · halved shadows" },
                                { k: "C", name: "Calm Mode",
                                  desc: "Opaque panels · 80 ms crossfades" }
                            ]

                            delegate: Rectangle {
                                id: tierCard
                                required property var modelData
                                width: parent.width
                                height: 50
                                radius: 14
                                color: Governor.tier === tierCard.modelData.k
                                       ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.12)
                                       : (Util.darkMode ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04))
                                border.width: 1
                                border.color: Governor.tier === tierCard.modelData.k
                                              ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.4)
                                              : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 14
                                        height: 14
                                        radius: 7
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Governor.tier === tierCard.modelData.k
                                               ? Tokens.accent : "transparent"
                                        border.width: 1.5
                                        border.color: Governor.tier === tierCard.modelData.k
                                                      ? Tokens.accent : Tokens.fgMuted
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Text {
                                            text: tierCard.modelData.k
                                                  + " · " + tierCard.modelData.name
                                            color: Tokens.fg
                                            font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
                                        }
                                        Text {
                                            text: tierCard.modelData.desc
                                            color: Tokens.fgMuted
                                            font { family: "Montserrat"; pixelSize: 10 }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Governor.setTier(tierCard.modelData.k)
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            height: 24
                            spacing: 8

                            Rectangle {
                                width: autoText.implicitWidth + 20
                                height: 24
                                radius: 12
                                color: Governor.autoMode
                                       ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)
                                       : (Util.darkMode ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.06))

                                Text {
                                    id: autoText
                                    anchors.centerIn: parent
                                    text: "Auto"
                                    color: Tokens.fg
                                    font { family: "Montserrat"; pixelSize: 11; weight: Font.DemiBold }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Governor.setAutoMode(true)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Governor.batteryPercent >= 0
                                      ? (Governor.batteryPercent + "% · "
                                         + (Governor.onBattery ? "battery" : "AC"))
                                      : "AC power"
                                color: Tokens.fgMuted
                                font { family: "Montserrat"; pixelSize: 11 }
                            }
                        }

                        Text {
                            width: parent.width
                            text: "Demotions apply instantly — the badge always shows the live tier. Calm Mode stays on until you turn it off."
                            color: Tokens.fgMuted
                            wrapMode: Text.WordWrap
                            font { family: "Montserrat"; pixelSize: 10 }
                        }

                        Text {
                            text: "‹  Back"
                            color: Tokens.fgMuted
                            font { family: "Montserrat"; pixelSize: 11 }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ccRoot.governorOpen = false
                            }
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

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        // W13 — repurposed: the mono echo is the LIVE accent
                        // value (W5's one token, in plain sight), not a
                        // platform debug label.
                        text: Tokens.accent.toString().toUpperCase()
                        color: Tokens.fgMuted
                        font { family: "DejaVu Sans Mono"; pixelSize: 10 }
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

    function paintBell(ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.5
        ctx.lineCap = "round"
        const cx = w / 2
        ctx.beginPath()
        ctx.moveTo(cx - 5, 11)
        ctx.bezierCurveTo(cx - 5, 4, cx + 5, 4, cx + 5, 11)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(cx - 6.5, 12.5)
        ctx.lineTo(cx + 6.5, 12.5)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx, 14.5, 1.3, 0, Math.PI * 2)
        ctx.fill()
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

        MouseArea {
            visible: !wide
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggled()
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
