import QtQuick
import Aegis.Util
import Aegis.Governor
import Aegis.Activity

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

    // ── M3 — Calm Mode: the panel's chrome collapses to fully clear glass
    // (opacity 0) while Activity.calm holds. The exclusive zone stays 28 px
    // (no maximized-window relayout — calm is quiet, not disruptive) and the
    // surface stays mapped, so hovering the top strip peeks the chrome back;
    // leaving re-collapses after 1.5 s. The probe is the topmost item but
    // accepts no buttons — clicks fall through to the right-cluster zone —
    // and only arms during calm so the normal hand cursor survives. ──
    property bool calmPeek: false
    readonly property bool calmActive: Activity.calm
    readonly property bool chromeHidden: calmActive && !calmPeek
    readonly property real chromeOpacity: chromeHidden ? 0 : 1

    function peek() { calmPeek = true; peekTimer.stop() }
    function collapseSoon() { if (calmActive) peekTimer.restart() }

    Timer {
        id: peekTimer
        interval: 1500
        onTriggered: panelRoot.calmPeek = false
    }

    MouseArea {
        id: calmProbe
        anchors.fill: parent
        enabled: panelRoot.calmActive
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 50
        onContainsMouseChanged: containsMouse ? panelRoot.peek()
                                              : panelRoot.collapseSoon()
    }

    Item {
        id: chrome
        anchors.fill: parent
        opacity: panelRoot.chromeOpacity
        Behavior on opacity { NumberAnimation { duration: 180 } }

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
                // T15-D6 (W43) — the link glyph picks the story the
                // machine actually has: wired ethernet when there is no
                // radio or the wired link is up (VMs expose NAT as
                // ethernet — a Wi-Fi fan on those machines is a lie),
                // the fan otherwise; dim when nothing is connected.
                PanelGlyph { painter: (Util.hasWifi && !Util.wiredConnected)
                                       ? panelRoot.paintWifi
                                       : panelRoot.paintWired
                             tint: (Util.wiredConnected
                                    || (Util.hasWifi && Util.wifiEnabled))
                                   ? panelRoot.statusTint
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

                    // T15-D10 (W47) — the clock is a BUTTON now: it opens the
                    // glass calendar popover (CalendarPopover.qml). The hit
                    // target is the clock's own box plus padding.
                    MouseArea {
                        id: clockHit
                        anchors { fill: parent; margins: -8 }
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Util.toggleCalendar()
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
    // T15-D8 (W45) — the painters moved VERBATIM into the shared
    // Glyphs singleton (one family, one contract); Panel keeps the
    // names and delegates. Every tuned geometry comment lives next to
    // its painter in Glyphs.qml now.

    function paintWifi(ctx, w, h, color) { Glyphs.wifi(ctx, w, h, color) }
    function paintWired(ctx, w, h, color) { Glyphs.wired(ctx, w, h, color) }
    function paintBattery(ctx, w, h, color, charging, percent) { Glyphs.battery(ctx, w, h, color, charging, percent) }
    function paintSpeaker(ctx, w, h, color, muted) { Glyphs.speaker(ctx, w, h, color, muted) }
    function paintSliders(ctx, w, h, color) { Glyphs.sliders(ctx, w, h, color) }
}
