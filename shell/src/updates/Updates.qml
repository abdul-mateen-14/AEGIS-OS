// Software Update — the macOS-grade face of system updates on Aegis OS.
// One window: a status line that always answers "is my system current?",
// the list of pending updates with sizes, one button that applies
// everything, live progress, and a restart prompt when one is needed.
// Frameless glass card over true black, Tokens-aligned (accent #3E8BFF,
// Montserrat). Pure QtQuick primitives — no Controls, no Effects.

import QtQuick

Window {
    id: root

    readonly property color accent: "#3E8BFF"
    readonly property color fg: "#F2F4F8"
    readonly property color fgMuted: Qt.rgba(1, 1, 1, 0.55)
    readonly property color glass: Qt.rgba(1, 1, 1, 0.06)
    readonly property color line: Qt.rgba(1, 1, 1, 0.13)

    width: 660
    height: 480
    minimumWidth: 560
    minimumHeight: 420
    visible: true
    title: "Software Update"
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.Window

    Component.onCompleted: Updates.checkNow()

    // ── chrome ───────────────────────────────────────────────────────
    Rectangle {
        id: chrome
        anchors.fill: parent
        radius: 16
        color: "#0B0D12F5"
        border.width: 1
        border.color: root.line
    }

    MouseArea {
        id: drag
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48
        onPressed: root.startSystemMove()
    }

    // close button
    Rectangle {
        width: 26; height: 26; radius: 13
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 14
        color: closeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
        Text {
            anchors.centerIn: parent
            text: "\u2715"
            color: root.fgMuted
            font.pixelSize: 11
        }
        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
        }
    }

    // ── content ──────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.topMargin: 48
        anchors.bottomMargin: 18
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        spacing: 16

        // header
        Item {
            width: parent.width
            height: 34

            Image {
                id: mark
                source: "aegis-mark.png"
                width: 30
                height: 30
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
            }
            Text {
                anchors.left: mark.right
                anchors.leftMargin: 12
                anchors.verticalCenter: mark.verticalCenter
                text: "Software Update"
                color: root.fg
                font { family: "Montserrat"; weight: Font.DemiBold; pixelSize: 17; letterSpacing: 0.4 }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Updates.osLabel
                color: root.fgMuted
                font { family: "Montserrat"; pixelSize: 11.5 }
                elide: Text.ElideRight
                width: parent.width - 240
                horizontalAlignment: Text.AlignRight
            }
        }

        // hero status
        Item {
            width: parent.width
            height: 54

            Canvas {
                id: heroGlyph
                width: 44; height: 44
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                property string mode: Updates.phase === "up-to-date" ? "check"
                                      : Updates.phase === "error" ? "alert"
                                      : Updates.phase === "available" ? "packs"
                                      : "spin"
                onModeChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    var c = mode === "alert" ? "#FF9C9C" : root.accent
                    ctx.strokeStyle = c
                    ctx.fillStyle = c
                    ctx.lineWidth = 2.4

                    if (mode === "check") {
                        ctx.beginPath()
                        ctx.arc(22, 22, 17, 0, Math.PI * 2)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(13.5, 22.5)
                        ctx.lineTo(20, 29)
                        ctx.lineTo(31, 16.5)
                        ctx.stroke()
                    } else if (mode === "alert") {
                        ctx.beginPath()
                        ctx.arc(22, 22, 17, 0, Math.PI * 2)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(22, 12); ctx.lineTo(22, 24); ctx.stroke()
                        ctx.beginPath()
                        ctx.arc(22, 29.5, 1.6, 0, Math.PI * 2)
                        ctx.fill()
                    } else if (mode === "packs") {
                        ctx.beginPath()
                        ctx.moveTo(12, 15); ctx.lineTo(22, 9); ctx.lineTo(32, 15)
                        ctx.lineTo(22, 21); ctx.closePath(); ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(12, 22); ctx.lineTo(22, 28); ctx.lineTo(32, 22)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(12, 29); ctx.lineTo(22, 35); ctx.lineTo(32, 29)
                        ctx.stroke()
                    } else {
                        ctx.beginPath()
                        ctx.arc(22, 22, 15, Math.PI * 0.2, Math.PI * 1.7)
                        ctx.stroke()
                    }
                }

                RotationAnimation on rotation {
                    running: heroGlyph.mode === "spin" && root.visible
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 1400
                }
            }

            Text {
                id: heroText
                anchors.left: heroGlyph.right
                anchors.leftMargin: 16
                anchors.verticalCenter: heroGlyph.verticalCenter
                width: parent.width - 64
                text: Updates.phase === "checking"
                          ? "Checking for updates…"
                      : Updates.phase === "available"
                          ? (Updates.updates.length === 1
                             ? "1 update is available for your Aegis."
                             : Updates.updates.length + " updates are available for your Aegis.")
                      : Updates.phase === "installing"
                          ? "Installing updates — this can take a few minutes."
                      : Updates.phase === "error"
                          ? "Couldn't check for updates."
                      : "Aegis OS is up to date."
                color: root.fg
                font { family: "Montserrat"; weight: Font.Medium; pixelSize: 16 }
                wrapMode: Text.WordWrap
            }
        }

        // update list
        Flickable {
            width: parent.width
            height: updatesAvailable ? Math.min(200, Updates.updates.length * 44 + 10) : 0
            clip: true
            contentHeight: col.height
            property bool updatesAvailable: Updates.phase === "available"

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: root.glass
                border.width: 1
                border.color: root.line
                visible: updatesAvailable
            }

            Column {
                id: col
                x: 6; y: 6
                width: parent.width - 12
                spacing: 0
                visible: updatesAvailable

                Repeater {
                    model: Updates.updates

                    Item {
                        width: col.width
                        height: 42

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: root.fg
                            font { family: "Montserrat"; pixelSize: 12.5 }
                            elide: Text.ElideRight
                            width: parent.width - 190
                        }
                        Text {
                            anchors.right: size.right
                            anchors.rightMargin: 90
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.version
                            color: root.fgMuted
                            font { family: "Montserrat"; pixelSize: 11 }
                            elide: Text.ElideRight
                            width: 120
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            id: size
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.size !== "" ? modelData.size : ""
                            color: root.fgMuted
                            font { family: "Montserrat"; pixelSize: 11 }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            height: 1
                            color: root.line
                            visible: index < Updates.updates.length - 1
                        }
                    }
                }
            }
        }

        // progress
        Item {
            width: parent.width
            height: Updates.busy ? 30 : 0
            visible: Updates.busy
            Behavior on height { NumberAnimation { duration: 160 } }

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.10)
                visible: Updates.percent >= 0
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                width: Updates.percent >= 0 ? track.width * Updates.percent / 100 : 0
                height: 6
                radius: 3
                color: root.accent
                visible: Updates.percent >= 0
            }
            // indeterminate sweep
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                visible: Updates.percent < 0

                Rectangle {
                    id: sweep
                    width: 120
                    height: 6
                    radius: 3
                    color: root.accent
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        NumberAnimation { from: -120; to: root.width; duration: 1200;
                                          easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

        // filler
        Item { width: 1; height: parent.height < 460 ? 2 : 10 }

        // status line
        Text {
            width: parent.width
            text: Updates.statusLine
            color: root.fgMuted
            font { family: "Montserrat"; pixelSize: 11.5 }
            wrapMode: Text.WordWrap
        }
    }

    // ── footer buttons ───────────────────────────────────────────────
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        anchors.right: parent.right
        anchors.rightMargin: 26
        spacing: 10

        component PillButton: Rectangle {
            id: pill
            property string label: ""
            property bool isPrimary: false
            property bool enabledNow: true
            signal clicked()

            width: Math.max(96, lbl.implicitWidth + 36)
            height: 38
            radius: 19
            color: !enabledNow ? Qt.rgba(1, 1, 1, 0.05)
                   : isPrimary ? Qt.rgba(accent.r, accent.g, accent.b, 0.9)
                   : Qt.rgba(1, 1, 1, 0.10)
            opacity: enabledNow ? 1 : 0.55

            Text {
                id: lbl
                anchors.centerIn: parent
                text: pill.label
                color: pill.isPrimary ? "#FFFFFF" : root.fg
                font { family: "Montserrat"; weight: Font.DemiBold; pixelSize: 12.5 }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: pill.enabledNow
                onClicked: pill.clicked()
            }
        }

        PillButton {
            label: "Check Again"
            enabledNow: !Updates.busy
            onClicked: Updates.checkNow()
            visible: Updates.phase === "up-to-date" || Updates.phase === "error"
        }
        PillButton {
            label: "Restart Now"
            isPrimary: true
            onClicked: Updates.restartNow()
            visible: Updates.phase === "up-to-date" && Updates.rebootRequired
        }
        PillButton {
            label: "Update Now"
            isPrimary: true
            enabledNow: Updates.phase === "available"
            onClicked: Updates.installNow()
            visible: Updates.phase !== "installing" && Updates.phase !== "checking"
        }
    }
}
