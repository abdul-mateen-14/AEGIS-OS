import QtQuick
import Aegis.Util

// Lock screen — the honesty surface (proposal chapter 07, Plate 6 +
// Table 17). Full-bleed wallpaper under a 42% scrim; panel, dock, island
// and every other piece of chrome fade out with the same 240 ms token —
// they are layer-shell surfaces under this Overlay-layer window, and the
// compositor stacks Overlay above Top, so nothing else of the shell shows
// through. 118 px thin clock in Montserrat ExtraLight, the user's
// monochrome avatar ring, and one glass password pill (300 × 46).
//
// Unlock verifies through the setuid PAM helper (aegis-auth → pam_unix):
// success hands off to the session with a single 240 ms fade — no zoom,
// no spin. Failure shakes the pill once, quietly.
//
// Entry/exit: smooth 240 ms both ways (Table 17).
Window {
    objectName: "lockWindow"
    id: lockRoot
    visible: Util.locked
    color: "transparent"
    width: 1920
    height: 1080
    flags: Qt.FramelessWindowHint

    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Tokens.durSmooth; easing.type: Easing.OutCubic }
    }

    onVisibleChanged: if (visible) {
        passwordField.text = ""
        passwordField.forceActiveFocus()
    }

    // wallpaper full-bleed (same canvas as the desktop — continuity)
    Image {
        anchors.fill: parent
        source: Util.config["wallpaper"] || "/usr/share/wallpapers/aegis/aurora-ink.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: false
    }

    // 42% ink scrim (§7 lock screen)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -36
        spacing: 0

        // ── 118 px thin clock ────────────────────────────────────────
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            font {
                family: "Montserrat"
                pixelSize: 118
                weight: Font.ExtraLight
                letterSpacing: 1.5
            }

            Timer {
                interval: 1000
                running: lockRoot.visible
                repeat: true
                triggeredOnStart: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm")
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: -6
            color: Qt.rgba(1, 1, 1, 0.55)
            font { family: "Montserrat"; pixelSize: 13; letterSpacing: 2.5 }
            text: Qt.formatDate(new Date(), "EEEE, d MMMM")
        }

        // ── avatar ring + password pill, 44 px below the date ────────
        Item {
            width: 300
            height: 180
            anchors.horizontalCenter: parent.horizontalCenter

            // monochrome avatar ring
            Rectangle {
                id: avatar
                width: 56
                height: 56
                radius: 28
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 44
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 2
                border.color: Qt.rgba(1, 1, 1, 0.40)

                Text {
                    anchors.centerIn: parent
                    text: Util.userInitials
                    color: "white"
                    font { family: "Montserrat"; pixelSize: 18; weight: Font.Light }
                }
            }

            // glass password pill 300 × 46 (Table 17)
            Rectangle {
                id: pill
                width: 300
                height: 46
                radius: 23
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 122
                color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 1
                border.color: unlockOk > 0
                              ? (unlockOk === 1 ? Qt.rgba(0.13, 0.77, 0.47, 0.7)
                                                : Qt.rgba(0.94, 0.27, 0.27, 0.7))
                              : Qt.rgba(1, 1, 1, 0.18)
                // unlockOk: 0 idle · 1 success · 2 failure

                transform: Translate { id: shake; x: 0 }

                TextInput {
                    id: passwordField
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 48
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "\u2022"
                    color: "white"
                    font { family: "Montserrat"; pixelSize: 14 }
                    clip: true
                    enabled: !checking
                    onAccepted: lockRoot.submit()

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: passwordField.text === ""
                        text: "Enter password"
                        color: Qt.rgba(1, 1, 1, 0.40)
                        font { family: "Montserrat"; pixelSize: 13 }
                    }
                }

                // submit glyph
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: submitMa.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)

                    Canvas {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        rotation: 0
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = "white"
                            ctx.lineWidth = 1.6
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(3, 7)
                            ctx.lineTo(11, 7)
                            ctx.moveTo(7.5, 3.5)
                            ctx.lineTo(11, 7)
                            ctx.lineTo(7.5, 10.5)
                            ctx.stroke()
                        }
                    }

                    MouseArea {
                        id: submitMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: lockRoot.submit()
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 0
                visible: lockRoot.checking
                text: "Verifying…"
                color: Qt.rgba(1, 1, 1, 0.55)
                font { family: "Montserrat"; pixelSize: 11; letterSpacing: 1 }
            }
        }
    }

    // footer hint — quiet, lower-left, hairline language
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 20
        text: Util.userName + " · Aegis OS"
        color: Qt.rgba(1, 1, 1, 0.35)
        font { family: "Montserrat"; pixelSize: 11; letterSpacing: 1 }
    }

    property int unlockOk: 0
    property bool checking: false

    function submit() {
        if (checking || passwordField.text === "")
            return
        checking = true
        unlockOk = 0
        Util.unlock(Util.userName, passwordField.text)
    }

    Connections {
        target: Util

        function onUnlockResult(ok) {
            checking = false
            if (ok) {
                unlockOk = 1
                passwordField.text = ""
            } else {
                unlockOk = 2
                shakeAnim.restart()
                passwordField.selectAll()
                passwordField.forceActiveFocus()
            }
            resetTimer.restart()
        }
    }

    Timer {
        id: resetTimer
        interval: 1400
        onTriggered: lockRoot.unlockOk = 0
    }

    SequentialAnimation {
        id: shakeAnim

        NumberAnimation { target: shake; property: "x"; from: 0; to: -7; duration: 55; easing.type: Easing.OutCubic }
        NumberAnimation { target: shake; property: "x"; from: -7; to: 7; duration: 90; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; from: 7; to: 0; duration: 55; easing.type: Easing.OutCubic }
    }
}
