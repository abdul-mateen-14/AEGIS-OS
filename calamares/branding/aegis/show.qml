// Aegis OS install slideshow — calm, monochrome, Montserrat.
// A quiet ambient glow behind the mark, feature statements that cross-fade
// while files copy. Nothing flashy: installing is the calm part.
import QtQuick

Rectangle {
    id: root
    color: "#08090C"

    // Ambient brand glow — slow breathing radial gradient
    Rectangle {
        anchors.centerIn: parent
        width: 640; height: 640
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.24, 0.55, 1.0, 0.16) }
            GradientStop { position: 0.55; color: Qt.rgba(0.24, 0.55, 1.0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(0.0, 0.0, 0.0, 0.0) }
        }
        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.08; duration: 5200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.08; to: 1.0; duration: 5200; easing.type: Easing.InOutSine }
        }
    }

    Image {
        id: mark
        source: "logo.png"
        width: 132
        height: width
        fillMode: Image.PreserveAspectFit
        anchors {
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: -118
            horizontalCenter: parent.horizontalCenter
        }
        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.03; duration: 3200; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.03; to: 1.0; duration: 3200; easing.type: Easing.InOutQuad }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: mark.bottom
        anchors.topMargin: 26
        text: "Aegis OS"
        color: "#F2F4F8"
        font { family: "Montserrat"; pixelSize: 26; weight: Font.DemiBold; letterSpacing: 2 }
    }

    // Rotating feature statements
    readonly property var lines: [
        "Hardened by default. Quiet chrome, colorful content.",
        "The island lives on your desktop — apps fold into it, one tap away.",
        "Files, Terminal, Browser, Cloud — first-party, cohesive, fast.",
        "Your machine, your rules: zram tuned, ports closed, updates calm.",
        "Almost there. Your new desktop is taking shape."
    ]
    property int idx: 0

    Text {
        id: statement
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: mark.bottom
        anchors.topMargin: 74
        width: Math.min(root.width - 120, 560)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.lines[root.idx]
        color: Qt.rgba(1, 1, 1, 0.6)
        font { family: "Montserrat"; pixelSize: 14; letterSpacing: 0.4 }

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.0; duration: 900; easing.type: Easing.InQuad }
            PauseAnimation { duration: 4600 }
            NumberAnimation { from: 0.0; to: 1.0; duration: 900; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 4600 }
            onStarted: root.idx = (root.idx + 1) % root.lines.length
        }
    }

    // Hairline progress — mirrors the Plymouth progress bar language
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        width: 220; height: 2
        color: Qt.rgba(1, 1, 1, 0.14)
        radius: 1

        Rectangle {
            width: 44; height: parent.height
            radius: 1
            color: "#3E8BFF"
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { from: -44; to: 220; duration: 6000; easing.type: Easing.InOutSine }
            }
        }
    }
}
