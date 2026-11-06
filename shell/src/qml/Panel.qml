import QtQuick
import Aegis.Util

// Top panel — 28 px of global status (§2.1, Table 3).
// M1 right cluster: battery · clock · power. The full global menu
// (focused app + File/Edit/View/Go) and the keyboard/network/volume cluster
// land in M2 with Control Center.
Window {
    objectName: "panelWindow"
    visible: false
    color: "transparent"
    width: 1920
    height: Tokens.panelHeight
    flags: Qt.FramelessWindowHint

    id: panelRoot

    property bool powerMenuOpen: false

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
                color: Tokens.paper
                font {
                    family: "Montserrat"
                    pixelSize: 12
                    weight: Font.DemiBold
                    letterSpacing: 0.4
                }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Right cluster — status only, no applets (§2.1)
        Row {
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 14

            Text {
                visible: Util.batteryPercent >= 0
                text: Util.batteryPercent + "%"
                color: Qt.rgba(1, 1, 1, 0.82)
                font { family: "Montserrat"; pixelSize: 11 }
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: clock
                color: Tokens.paper
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

            // Control Center glyph placeholder — opens the power popover in M1
            Item {
                width: 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 5
                    color: panelRoot.powerMenuOpen ? Tokens.accent : Qt.rgba(1, 1, 1, 0.55)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panelRoot.powerMenuOpen = !panelRoot.powerMenuOpen
                }
            }
        }

        // Power popover (Sheet Glass simplified for M1; full Control Center is M2)
        Rectangle {
            visible: panelRoot.powerMenuOpen
            width: 148
            height: 3 * 30 + 10
            radius: 12
            color: Qt.rgba(16/255, 16/255, 18/255, 0.92)
            border.color: Tokens.glassBorder
            anchors {
                right: parent.right
                rightMargin: 8
                top: parent.top
                topMargin: Tokens.panelHeight + 4
            }

            Column {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 0

                Repeater {
                    model: [
                        { label: "Suspend",   action: "suspend" },
                        { label: "Restart",   action: "reboot" },
                        { label: "Shut Down", action: "shutdown" }
                    ]

                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 30

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: Tokens.paper
                            font { family: "Montserrat"; pixelSize: 11.5 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panelRoot.powerMenuOpen = false
                                Util.powerAction(modelData.action)
                            }
                        }
                    }
                }
            }
        }
    }
}
