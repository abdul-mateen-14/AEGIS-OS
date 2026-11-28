// Aegis ID — identity card. The island's glass language from
// docs/DESIGN-TOKENS.md: abyss base, one floating card, hairline border,
// the blue ramp for identity accents.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    width: 420
    height: 540
    visible: true
    title: qsTr("Aegis ID")
    color: "#0B1020" // abyss

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: parent.width - 64
        height: 392
        radius: 28
        color: "#11162B"
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 20

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 96
                height: 96
                radius: 48
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#5B8BFF" }
                    GradientStop { position: 1.0; color: "#1D4FEA" }
                }
                Text {
                    anchors.centerIn: parent
                    text: DeviceInfo.userName.length > 0
                          ? DeviceInfo.userName[0].toUpperCase() : "A"
                    font.pixelSize: 42
                    font.weight: Font.DemiBold
                    color: "#FFFFFF"
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Aegis ID")
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: "#FFFFFF"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { k: qsTr("Device"), v: DeviceInfo.hostName },
                        { k: qsTr("User"), v: DeviceInfo.userName },
                        { k: qsTr("System"), v: DeviceInfo.osName }
                    ]
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: modelData.k
                            font.pixelSize: 13
                            color: Qt.rgba(1, 1, 1, 0.45)
                            Layout.preferredWidth: 84
                        }
                        Text {
                            text: modelData.v
                            font.pixelSize: 14
                            color: "#FFFFFF"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("No telemetry. Your identity stays on this device.")
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.55)
                wrapMode: Text.WordWrap
            }
        }
    }
}
