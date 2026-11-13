import QtQuick
import QtQuick.Controls
import Aegis.Util
import Aegis.Governor

// T15-D10 (W47) — the glass calendar popover. The reviewer's §2 W47 item:
// the shell had NO calendar at all (the panel clock had no click handler),
// so the calendar interpretation of "calender traffic lights are not
// working" ships as the §2.4-native surface: click the panel clock -> a
// glass sheet hangs below the panel (same architecture as the Control
// Center sheet). ~300x340: month grid, today in the accent, prev/next
// chevrons. No traffic lights — it is a popover, not a window. Closes on
// focus loss (a normal window opening) and when the Control Center opens
// — one sheet at a time, like macOS.
Window {
    // KWin's alt+F4 must never destroy a shell surface (the v0.6.5 cascade)
    onClosing: (close) => { close.accepted = false }
    objectName: "calendarWindow"
    id: calRoot
    visible: Util.calendarOpen
    color: "transparent"
    width: 300
    height: 340
    flags: Qt.FramelessWindowHint

    property date viewDate: new Date()

    function monthStart(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), 1)
        // Monday-first grid: JS Sunday = 0 -> shift back 6 days
        const dow = (m.getDay() + 6) % 7
        m.setDate(m.getDate() - dow)
        return m
    }

    onVisibleChanged: if (visible) { viewDate = new Date(); springIn.restart() }

    // ── the W20-style predicates: one sheet at a time, gone on focus loss ──
    Connections {
        target: Util
        function onCcOpenChanged() { if (Util.ccOpen) Util.setCalendarOpen(false) }
        function onWindowTrackingChanged() {
            if (Util.workspaceWindows > 0 && Util.calendarOpen)
                Util.setCalendarOpen(false)
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
                spacing: 8

                // ── header: month + chevrons ─────────────────
                Row {
                    width: parent.width
                    height: 30
                    spacing: 6

                    Text {
                        text: Qt.formatDate(calRoot.viewDate, "MMMM yyyy")
                        color: Tokens.fg
                        font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 72
                        elide: Text.ElideRight
                    }

                    AbstractButton {
                        id: prevBtn
                        width: 32; height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        contentItem: Text {
                            text: "\u2039"
                            font.pixelSize: 18
                            color: prevBtn.hovered ? Tokens.fg : Tokens.fgMuted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 10
                            color: prevBtn.hovered ? (Util.darkMode ? "#262930" : "#E8ECF4")
                                                   : "transparent"
                        }
                        onClicked: {
                            calRoot.viewDate = new Date(
                                calRoot.viewDate.getFullYear(),
                                calRoot.viewDate.getMonth() - 1, 1)
                        }
                    }
                    AbstractButton {
                        id: nextBtn
                        width: 32; height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        contentItem: Text {
                            text: "\u203a"
                            font.pixelSize: 18
                            color: nextBtn.hovered ? Tokens.fg : Tokens.fgMuted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 10
                            color: nextBtn.hovered ? (Util.darkMode ? "#262930" : "#E8ECF4")
                                                   : "transparent"
                        }
                        onClicked: {
                            calRoot.viewDate = new Date(
                                calRoot.viewDate.getFullYear(),
                                calRoot.viewDate.getMonth() + 1, 1)
                        }
                    }
                }

                // ── weekday row (Monday first) ───────────────
                Row {
                    width: parent.width
                    height: 20
                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Text {
                            required property int index
                            text: modelData
                            width: parent.width / 7
                            height: parent.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font { family: "Montserrat"; pixelSize: 10; weight: Font.DemiBold }
                            color: index >= 5 ? Tokens.fgMuted : Tokens.fg
                            opacity: 0.85
                        }
                    }
                }

                // ── the month grid (6 rows × 7) ──────────────
                Grid {
                    width: parent.width
                    columns: 7
                    rows: 6
                    spacing: 2

                    Repeater {
                        model: 42

                        delegate: Item {
                            required property int index
                            width: (parent.width - 12) / 7
                            height: 40

                            readonly property var cellDate: {
                                const start = calRoot.monthStart(calRoot.viewDate)
                                const d = new Date(start)
                                d.setDate(start.getDate() + index)
                                return d
                            }
                            readonly property bool inMonth:
                                cellDate.getMonth() === calRoot.viewDate.getMonth()
                            readonly property bool isToday:
                                cellDate.toDateString() === new Date().toDateString()

                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                visible: isToday
                                color: Tokens.accent
                            }
                            Text {
                                anchors.centerIn: parent
                                text: cellDate.getDate()
                                font { family: "Montserrat"; pixelSize: 11; weight: isToday ? Font.DemiBold : Font.Normal }
                                color: isToday ? "#FFFFFF"
                                     : inMonth ? Tokens.fg
                                     : Tokens.fgMuted
                                opacity: inMonth ? 1.0 : 0.45
                            }
                        }
                    }
                }
            }
        }

        // entry spring — the Control Center's sheet motion verbatim
        // (0.96 -> 1 OutBack + 2 px drop + fade, Tokens.durSpring)
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
                    duration: Tokens.durSpring
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
