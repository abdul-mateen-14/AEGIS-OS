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
                source: "qrc:/qml/aegis-mark.png"
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

                // Wi-Fi status glyph
                Item {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        anchors.fill: parent
                        onPaint: panelRoot.paintWifi(
                                     getContext("2d"), width, height,
                                     Util.wifiEnabled
                                         ? Qt.rgba(1, 1, 1, 0.82)
                                         : Qt.rgba(1, 1, 1, 0.28))
                    }
                }

                // volume status glyph
                Item {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        anchors.fill: parent
                        onPaint: panelRoot.paintSpeaker(
                                     getContext("2d"), width, height,
                                     Util.muted
                                         ? Qt.rgba(1, 1, 1, 0.28)
                                         : Qt.rgba(1, 1, 1, 0.82),
                                     Util.muted)
                    }
                }

                Text {
                    visible: Util.batteryPercent >= 0
                    text: Util.batteryPercent + "%"
                    color: Qt.rgba(1, 1, 1, 0.82)
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

                // Control Center glyph — mini sliders, 14 px stroke
                Item {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        anchors.fill: parent
                        onPaint: panelRoot.paintSliders(
                                     getContext("2d"), width, height,
                                     Util.ccOpen ? Tokens.accent
                                                 : Qt.rgba(1, 1, 1, 0.55))
                    }
                }
            }
        }
    }

    // ── 14 px stroke glyphs (Canvas — no emoji, no theme dependency) ──

    function paintWifi(ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.3
        ctx.lineCap = "round"
        const cx = w / 2, cy = h / 2 + 2.5
        for (let i = 1; i <= 2; ++i) {
            ctx.beginPath()
            ctx.arc(cx, cy, i * 2.8, Math.PI * 1.25, Math.PI * 1.75, false)
            ctx.stroke()
        }
        ctx.beginPath()
        ctx.arc(cx, cy, 1.3, 0, Math.PI * 2)
        ctx.fill()
    }

    function paintSpeaker(ctx, w, h, color, muted) {
        ctx.reset()
        ctx.fillStyle = color
        ctx.strokeStyle = color
        ctx.lineWidth = 1.2
        ctx.lineCap = "round"
        const cx = w / 2 - 1.5, cy = h / 2
        ctx.beginPath()
        ctx.moveTo(cx - 3.5, cy - 2)
        ctx.lineTo(cx - 1.5, cy - 2)
        ctx.lineTo(cx + 1.5, cy - 5)
        ctx.lineTo(cx + 1.5, cy + 5)
        ctx.lineTo(cx - 1.5, cy + 2)
        ctx.lineTo(cx - 3.5, cy + 2)
        ctx.closePath()
        ctx.fill()
        if (muted) {
            ctx.beginPath()
            ctx.moveTo(cx + 3, cy - 2.5)
            ctx.lineTo(cx + 6, cy + 2.5)
            ctx.moveTo(cx + 6, cy - 2.5)
            ctx.lineTo(cx + 3, cy + 2.5)
            ctx.stroke()
        } else {
            ctx.beginPath()
            ctx.arc(cx + 2.5, cy, 2.5, -Math.PI / 3, Math.PI / 3)
            ctx.stroke()
        }
    }

    function paintSliders(ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.3
        ctx.lineCap = "round"
        for (let i = 0; i < 3; ++i) {
            const y = 2.5 + i * 4.5
            ctx.beginPath()
            ctx.moveTo(1, y)
            ctx.lineTo(w - 1, y)
            ctx.stroke()
            const knob = i === 0 ? 9.5 : i === 1 ? 4 : 11
            ctx.beginPath()
            ctx.arc(knob, y, 2, 0, Math.PI * 2)
            ctx.fill()
        }
    }
}
