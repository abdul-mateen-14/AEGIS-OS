import QtQuick
import Aegis.Util
import Aegis.Activity

// Notification banners — Table 17: 356 × 84, stack ≤ 3, top-right below
// the panel, radius 16. Standard in (180 ms), auto-out 5 s with a hairline
// progress track; hover pauses the clock and reveals the close button.
// Every app that calls the standard org.freedesktop.Notifications API
// lands here — the shell owns the daemon name inside the session. With
// Do Not Disturb on, banners queue silently (the stack is capped at 3,
// the oldest drops) and nothing shows on screen.
Window {
    objectName: "notificationsWindow"
    id: notifRoot
    visible: Activity.bannersVisible
    color: "transparent"
    width: 356
    height: stack.implicitHeight + 16
    flags: Qt.FramelessWindowHint

    Column {
        id: stack
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        spacing: 8

        Repeater {
            model: Activity.banners

            delegate: Rectangle {
                id: banner

                required property var modelData
                width: 356
                height: 84
                radius: 16
                color: Util.darkMode ? Tokens.glassTint : Tokens.glassTintLight
                border.width: 1
                border.color: Util.darkMode ? Tokens.glassBorder
                                            : Tokens.glassBorderLight
                opacity: 0
                Component.onCompleted: enterAnim.restart()

                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: banner; property: "opacity"; from: 0; to: 1; duration: Tokens.durStandard; easing.type: Easing.OutCubic }
                    NumberAnimation { target: banner; property: "x"; from: 24; to: 0; duration: Tokens.durStandard; easing.type: Easing.OutCubic }
                }

                SequentialAnimation {
                    id: exitAnim

                    NumberAnimation { target: banner; property: "opacity"; from: 1; to: 0; duration: Tokens.durInstant; easing.type: Easing.InCubic }
                    ScriptAction { script: Activity.dismissBanner(banner.modelData.id) }
                }

                // auto-out: 5 s minus the visible exit, paused on hover
                Timer {
                    id: outTimer
                    interval: Math.max(1, banner.modelData.ttl
                                        ? banner.modelData.ttl - Tokens.durInstant
                                        : 5000 - Tokens.durInstant)
                    running: !hover.hovered
                    onTriggered: exitAnim.restart()
                }

                // body-click invokes the default action; declared first so
                // the close button (later sibling) keeps priority
                MouseArea {
                    id: clickBody
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Activity.activateBanner(banner.modelData.id)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // app icon in a glass chip
                    Rectangle {
                        width: 44
                        height: 44
                        radius: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.08)
                                             : Qt.rgba(0, 0, 0, 0.05)
                        border.width: 1
                        border.color: Util.darkMode ? Tokens.glassBorder
                                                    : Tokens.glassBorderLight

                        Image {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            source: banner.modelData.icon
                                    ? "image://icons/" + banner.modelData.icon
                                    : "qrc:/qml/aegis-mark.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }

                    Column {
                        width: parent.width - 44 - 12 - (closeGlyph.visible ? 14 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: banner.modelData.summary
                                  + (banner.modelData.app
                                     ? "  ·  " + banner.modelData.app : "")
                            color: Tokens.fg
                            font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
                        }

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: banner.modelData.body
                            color: Tokens.fgMuted
                            font { family: "Montserrat"; pixelSize: 11 }
                        }
                    }

                    Text {
                        id: closeGlyph
                        anchors.verticalCenter: parent.verticalCenter
                        visible: hover.hovered
                        text: "✕"
                        color: Tokens.fgMuted
                        font { family: "Montserrat"; pixelSize: 12 }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Activity.dismissBanner(banner.modelData.id)
                        }
                    }
                }

                // hairline progress — the 5 s track (§3 hairline language)
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.bottomMargin: 8
                    width: 0
                    height: 2
                    radius: 1
                    color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                   Tokens.accent.b, 0.55)

                    NumberAnimation on width {
                        from: 0
                        to: 324
                        duration: outTimer.interval
                        running: outTimer.running
                    }
                }

                HoverHandler {
                    id: hover
                }
            }
        }
    }
}
