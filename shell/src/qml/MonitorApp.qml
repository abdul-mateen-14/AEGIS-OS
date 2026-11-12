import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aegis.Util
import Aegis.Monitor

// Aegis Monitor — M3 first-party app (proposal §8, plate 12).
//
// The system face of Tier A: a 2 s /proc walk (monitorbackend.h) feeding
// four stat cards (CPU · memory · uptime · network), a per-core strip, and
// a top-processes table sorted by CPU (top-style normalization — a busy
// core can read > 100 / core count). The card anatomy is the Settings
// pane card: glass hairline, radius 16, 14 px margins.
Window {
    id: win

    width: 820; height: 560
    minimumWidth: 560; minimumHeight: 420
    visible: true
    title: "Monitor"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: Monitor.refresh()
    }

    function fmtUptime(sec) {
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    function fmtRate(kbps) {
        return kbps >= 1024 ? (kbps / 1024).toFixed(1) + " MB/s"
                            : kbps.toFixed(0) + " KB/s"
    }

    AppWindow {
        id: appBody
        anchors.fill: parent
        title: "Monitor"

        toolbar: [
            Text {
                text: "System"
                font { pixelSize: 12; weight: Font.DemiBold }
                color: Tokens.fg
            },
            Rectangle {
                width: 7; height: 7; radius: 3.5
                color: "#28C840"
                Layout.alignment: Qt.AlignVCenter
            },
            Text {
                text: "live · 2 s"
                font.pixelSize: 10
                color: Tokens.fgMuted
            },
            Item { Layout.fillWidth: true },
            Text {
                text: Monitor.summary.processCount + " processes"
                font.pixelSize: 11
                color: Tokens.fgMuted
            },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 84
                contentItem: Text {
                    text: "Refresh"
                    font.pixelSize: 11
                    color: Tokens.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: Monitor.refresh()
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            // ── stat cards row ──────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                Layout.bottomMargin: 0
                spacing: 12

                component StatCard: Rectangle {
                    id: statCard
                    property string label: ""
                    property string value: ""
                    property string detail: ""
                    property real fraction: 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    ColumnLayout {
                        anchors { fill: parent; margins: 14 }
                        spacing: 4
                        Text {
                            text: statCard.label
                            font.pixelSize: 10
                            color: Tokens.fgMuted
                        }
                        Text {
                            text: statCard.value
                            font { family: "Montserrat"; pixelSize: 20; weight: Font.DemiBold }
                            color: Tokens.fg
                        }
                        // the fill bar doubles as the detail row
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.08) : "#E4E9F2"
                            visible: statCard.fraction >= 0
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * Math.min(1, statCard.fraction)
                                radius: 2
                                color: statCard.fraction > 0.9 ? Tokens.danger : Tokens.accent
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            text: statCard.detail
                            font.pixelSize: 10
                            color: Tokens.fgMuted
                            visible: statCard.detail.length > 0
                        }
                    }
                }

                StatCard {
                    label: "CPU"
                    value: Monitor.summary.cpu.toFixed(1) + " %"
                    detail: "load " + Monitor.summary.load1.toFixed(2)
                    fraction: Monitor.summary.cpu / 100
                }
                StatCard {
                    label: "Memory"
                    // W17 — honesty: with the /proc parser dead the card
                    // rendered "0.0 GB of 0.0 GB", which looks real. When
                    // meminfo is unavailable show an explicit dash state.
                    value: Monitor.summary.memTotalMb > 0
                           ? Monitor.summary.memPercent.toFixed(0) + " %"
                           : "\u2014"
                    detail: Monitor.summary.memTotalMb > 0
                            ? (Monitor.summary.memUsedMb / 1024).toFixed(1) + " GB of "
                              + (Monitor.summary.memTotalMb / 1024).toFixed(1) + " GB"
                            : "unavailable"
                    fraction: Monitor.summary.memTotalMb > 0
                              ? Monitor.summary.memPercent / 100 : -1
                }
                StatCard {
                    label: "Uptime"
                    value: fmtUptime(Monitor.summary.uptimeSec)
                    detail: "since boot"
                    fraction: -1
                }
                StatCard {
                    label: "Network"
                    value: fmtRate(Monitor.summary.netDownKbps) + " ↓"
                    detail: fmtRate(Monitor.summary.netUpKbps) + " ↑ up"
                    fraction: -1
                }
            }

            // ── per-core strip ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                radius: 16
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                border.color: Tokens.glassBorder
                RowLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 10
                    Text {
                        text: "Cores"
                        font.pixelSize: 10
                        color: Tokens.fgMuted
                        Layout.alignment: Qt.AlignVCenter
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 5
                        // W17 — honesty: an empty cores list must never
                        // render a blank card; say unavailable instead.
                        Text {
                            visible: Monitor.cores.length === 0
                            text: "per-core usage unavailable"
                            font.pixelSize: 10
                            color: Tokens.fgMuted
                        }
                        Repeater {
                            model: Monitor.cores
                            delegate: ColumnLayout {
                                spacing: 3
                                Rectangle {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 24
                                    radius: 4
                                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.08) : "#E4E9F2"
                                    Rectangle {
                                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: parent.height * Math.min(1, modelData / 100)
                                        radius: 4
                                        color: modelData > 90 ? Tokens.danger : Tokens.accent
                                        Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }
                                }
                                Text {
                                    text: index + 1
                                    font.pixelSize: 8
                                    color: Tokens.fgMuted
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // ── processes ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 14
                radius: 16
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                border.color: Tokens.glassBorder
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // header row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 12
                        Layout.bottomMargin: 4
                        spacing: 8
                        Text {
                            text: "Name"
                            font { pixelSize: 10; bold: true }
                            color: Tokens.fgMuted
                            Layout.preferredWidth: 260
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "PID"
                            font { pixelSize: 10; bold: true }
                            color: Tokens.fgMuted
                            Layout.preferredWidth: 70
                        }
                        Text {
                            text: "CPU"
                            font { pixelSize: 10; bold: true }
                            color: Tokens.fgMuted
                            Layout.preferredWidth: 60
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            text: "Memory"
                            font { pixelSize: 10; bold: true }
                            color: Tokens.fgMuted
                            Layout.preferredWidth: 80
                            horizontalAlignment: Text.AlignRight
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "State"
                            font { pixelSize: 10; bold: true }
                            color: Tokens.fgMuted
                            Layout.preferredWidth: 40
                        }
                    }

                    ListView {
                        id: procList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        Layout.bottomMargin: 10
                        clip: true
                        model: Monitor.processes
                        delegate: Rectangle {
                            width: procList.width
                            height: 26
                            color: index % 2 === 0 ? "transparent"
                                                   : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.03) : "#F0F3F9")
                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                spacing: 8
                                Text { text: modelData.name; font.pixelSize: 11; color: Tokens.fg; elide: Text.ElideMiddle; Layout.preferredWidth: 260 }
                                Text { text: modelData.pid; font.pixelSize: 11; color: Tokens.fgMuted; Layout.preferredWidth: 70 }
                                Text { text: modelData.cpu.toFixed(1) + " %"; font.pixelSize: 11; color: modelData.cpu > 50 ? Tokens.danger : Tokens.fg; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                                Text { text: modelData.rssMb.toFixed(1) + " MB"; font.pixelSize: 11; color: Tokens.fgMuted; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                                Item { Layout.fillWidth: true }
                                Text { text: modelData.state; font.pixelSize: 11; color: Tokens.fgMuted; Layout.preferredWidth: 40 }
                            }
                        }
                    }
                }
            }
        }
    }
}
