// Aegis OS install slideshow — calm, monochrome, Montserrat.
import QtQuick

Rectangle {
    id: root
    color: "#08090C"

    // Gentle breathing on the mark — nothing flashy during install
    Image {
        id: mark
        source: "logo.png"
        width: 140
        height: width
        fillMode: Image.PreserveAspectFit
        anchors.centerIn: parent
        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.04; duration: 1600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.04; to: 1.0; duration: 1600; easing.type: Easing.InOutQuad }
        }
    }

    Column {
        anchors {
            top: mark.bottom
            topMargin: 28
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Aegis OS"
            color: "#F2F4F8"
            font { family: "Montserrat"; pixelSize: 24; weight: Font.DemiBold; letterSpacing: 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Hardened by default. Quiet chrome, colorful content. Calm. Fast."
            color: Qt.rgba(1, 1, 1, 0.55)
            font { family: "Montserrat"; pixelSize: 13 }
        }
    }
}
