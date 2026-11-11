import QtQuick
import Aegis.Util
import Aegis.Governor

// Top panel — 28 px of global status (§2.1, Table 3).
//
// Left cluster: mark + shell name. Right cluster (M2): Wi-Fi · volume ·
// battery · clock · Control Center glyph — status only, no applets; the
// whole right half is one click zone that always opens Control Center
// (Table 3: "Right half always opens Control Center or its popover").
// The panel never hosts notifications or media controls — live activities
// live in the Dynamic Island (§2.4) and everything else in Control
// Center, keeping the bar under 28 px forever.
Window {
    // KWin's alt+F4 must never destroy a shell surface: with no app window
    // focused, the focused layer surface receives the close and would die
    // (dock -> island -> panel cascade, observed on the v0.6.5 boot test).
    onClosing: (close) => { close.accepted = false }
    objectName: "panelWindow"
    visible: false
    color: "transparent"
    width: 1920
    height: Tokens.panelHeight
    flags: Qt.FramelessWindowHint

    id: panelRoot

    Item {
        anchors.fill: parent

        GlassPanel {
            anchors.fill: parent
            cornerRadius: 0
        }

        // hairline bottom edge only (Table 3)
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        // Left cluster — mark + shell name
        Row {
            anchors {
                left: parent.left
                leftMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 8

            Image {
                // Relative URL: resolves inside the installed tree AND the
                // qrc fallback — the qrc: prefix 404s when QML loads from disk.
                source: "aegis-mark.png"
                width: 14
                height: 14
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "Aegis"
                color: Tokens.fg
                font {
                    family: "Montserrat"
                    pixelSize: 12
                    weight: Font.DemiBold
                    letterSpacing: 0.4
                }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Right cluster — status only + one Control Center click zone
        MouseArea {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            width: cluster.width + 20
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Util.ccOpen = !Util.ccOpen

            Row {
                id: cluster
                anchors {
                    right: parent.right
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                spacing: 12

                // W12 — one shared glyph set: 16 px optical, 2 px stroke,
                // round caps, Tokens.fg at 90%, 18 px hit targets.
                // Battery is always on the bar — on machines without a
                // battery pack (the boot-test VM) it reads as AC power.
                PanelGlyph { painter: panelRoot.paintWifi
                             tint: Util.wifiEnabled ? panelRoot.statusTint
                                                    : panelRoot.dimTint }

                PanelGlyph { painter: panelRoot.paintSpeaker
                             muted: Util.muted
                             tint: Util.muted ? panelRoot.dimTint
                                              : panelRoot.statusTint }

                BatteryGlyph { }

                Text {
                    visible: Util.batteryPercent >= 0
                    text: Util.batteryPercent + "%"
                    color: panelRoot.batteryTint
                    font { family: "Montserrat"; pixelSize: 11 }
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: clock
                    color: Tokens.fg
                    font {
                        family: "Montserrat"
                        pixelSize: 12
                        weight: Font.DemiBold
                        letterSpacing: 0.2
                    }
                    anchors.verticalCenter: parent.verticalCenter

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
                    }
                }

                // Control Center glyph — accent while the sheet is open
                PanelGlyph { painter: panelRoot.paintSliders
                             tint: Util.ccOpen ? Tokens.accent
                                               : panelRoot.ccTint }
            }
        }
    }

    // ── W12 — the shared status-glyph set (Canvas — no emoji, no theme
    //    dependency). 18 px hit target, 16 px optical box, repaints when
    //    its tint binding moves (state changes no longer go stale). ──

    // Tokens.fg at 90% (dark rung: paper at 0.9)
    readonly property color statusTint: Qt.rgba(Tokens.fg.r, Tokens.fg.g,
                                                Tokens.fg.b, 0.9)
    readonly property color dimTint: Qt.rgba(Tokens.fg.r, Tokens.fg.g,
                                             Tokens.fg.b, 0.28)
    readonly property color ccTint: Qt.rgba(Tokens.fg.r, Tokens.fg.g,
                                            Tokens.fg.b, 0.55)
    // Low battery (≤ 20 %, discharging) reads in the danger token.
    readonly property color batteryTint: (Util.batteryPercent >= 0
                                          && Util.batteryPercent <= 20
                                          && !Util.charging) ? Tokens.danger
                                                             : statusTint

    component PanelGlyph: Item {
        property var painter
        property color tint: panelRoot.statusTint
        property bool muted: false

        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter

        Canvas {
            id: canvas
            anchors.centerIn: parent
            width: 16
            height: 16
            onPaint: if (painter)
                painter(getContext("2d"), width, height, tint, muted)
        }
        onTintChanged: canvas.requestPaint()
        onPainterChanged: canvas.requestPaint()
        onMutedChanged: canvas.requestPaint()
    }

    // Battery — always drawn (Table 3 right cluster): outline body + level
    // fill when a battery is present, a bolt when charging, and on AC-only
    // machines (the CI VM) the bolt alone marks powered. Repaints on the
    // Util battery signal so level/state changes never go stale.
    component BatteryGlyph: Item {
        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter

        Canvas {
            id: batteryCanvas
            anchors.centerIn: parent
            width: 16
            height: 16
            onPaint: panelRoot.paintBattery(
                         getContext("2d"), width, height,
                         panelRoot.batteryTint, Util.charging,
                         Util.batteryPercent)
        }
        Connections {
            target: Util
            function onBatteryChanged() { batteryCanvas.requestPaint() }
        }
    }

    // ── 16 px optical painters — 2 px stroke, round caps ──

    // Wi-Fi — filled fan (macOS weight): three solid wedges read at a
    // glance where the old stroked arcs went thin.
    function paintWifi(ctx, w, h, color) {
        ctx.reset()
        ctx.fillStyle = color
        const cx = w / 2, cy = h / 2 + 3.5
        const a0 = Math.PI * 1.25, a1 = Math.PI * 1.75
        // innermost slice
        ctx.beginPath()
        ctx.moveTo(cx, cy)
        ctx.arc(cx, cy, 2.4, a0, a1)
        ctx.closePath()
        ctx.fill()
        // two bands
        const bands = [[3.5, 5.2], [6.3, 7.7]]
        for (const [rin, rout] of bands) {
            ctx.beginPath()
            ctx.arc(cx, cy, rout, a0, a1)
            ctx.arc(cx, cy, rin, a1, a0, true)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Battery body — 2 px outline, level fill, bolt for charge/AC.
    function paintBattery(ctx, w, h, color, charging, percent) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.8
        ctx.lineJoin = "round"
        // body
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
        // terminal nub
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
            // level fill — inset clear of the stroke so the two never fuse
            const innerX = 3.4, innerMax = 10.6, innerH = 4.0
            const level = Math.max(0, Math.min(100, percent)) / 100.0
            ctx.globalAlpha = 0.9
            ctx.fillRect(innerX, 6.9, Math.max(1.2, (innerMax - innerX) * level), innerH)
            ctx.globalAlpha = 1.0
        }
        if (charging || !hasBattery) {
            // bolt — charge pulse or AC-only power
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

    function paintSpeaker(ctx, w, h, color, muted) {
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

    function paintSliders(ctx, w, h, color) {
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
}
