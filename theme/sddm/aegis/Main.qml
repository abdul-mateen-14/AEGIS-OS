// Aegis glass login screen (SDDM greeter) — replaces the bare default
// greeter users saw on v0.2.0 (white background, floating form).
// macOS-lock-screen inspired: full-bleed Aegis wallpaper under a scrim,
// a big clock, a centered glass card (avatar · name · password pill ·
// Log In), a user strip when several accounts exist, power glyphs bottom
// right. Pure QtQuick primitives — no Controls, no Effects plugin, no
// shell imports — so it renders inside the SDDM greeter process with the
// exact module set SDDM ships. Circular avatars are Canvas-drawn because
// Rectangle.clip does not honor radius.
//
// SDDM context properties used: sddm, userModel, sessionModel,
// keyboardModel (guarded), config (theme.conf background).

import QtQuick

Rectangle {
    id: root

    readonly property color accent: "#3E8BFF"
    readonly property color fg: "#F2F4F8"
    readonly property color fgMuted: Qt.rgba(1, 1, 1, 0.55)
    readonly property color glass: Qt.rgba(1, 1, 1, 0.08)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.22)

    property string selName: ""
    property string selReal: ""
    property string selFace: ""
    property int selected: 0
    property bool busy: false
    property string hint: ""
    property var clockDate: new Date()

    color: "#08090C"

    function fileUrl(p) {
        if (p === undefined || p === null || p === "") return ""
        var s = "" + p
        if (s.indexOf("://") >= 0) return s
        return "file://" + s
    }

    function select(i, name, real, face) {
        selected = i
        selName = name
        selReal = real
        selFace = face
        hint = ""
    }

    function tryLogin() {
        if (busy || selName === "" || pw.text.length === 0)
            return
        busy = true
        hint = ""
        var session = typeof sessionModel !== "undefined"
                      ? sessionModel.lastIndex : 0
        sddm.login(selName, pw.text, session)
    }

    Component.onCompleted: {
        if (typeof userModel !== "undefined" && userModel.count > 0) {
            var i = 0
            if (typeof userModel.lastIndex !== "undefined")
                i = Math.max(0, Math.min(userModel.lastIndex, userModel.count - 1))
            selected = i
        }
        pw.forceActiveFocus()
    }

    // ── circular avatar renderer (no Effects plugin available) ───────
    component FaceAvatar: Canvas {
        id: av
        property string facePath: ""
        property string faceUrl: root.fileUrl(facePath)
        property real ringWidth: 2
        property color ringColor: root.glassBorder

        width: 88
        height: 88

        onFacePathChanged: {
            if (faceUrl !== "") loadImage(faceUrl)
            requestPaint()
        }
        Component.onCompleted: if (faceUrl !== "") loadImage(faceUrl)
        onImageLoaded: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            // base disc
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, width / 2 - ringWidth, 0, Math.PI * 2)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.10)
            ctx.fill()

            if (faceUrl !== "" && isImageLoaded(faceUrl)) {
                ctx.save()
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, width / 2 - ringWidth, 0, Math.PI * 2)
                ctx.clip()
                ctx.drawImage(faceUrl, 0, 0, width, height)
                ctx.restore()
            }

            // ring
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, width / 2 - ringWidth / 2, 0, Math.PI * 2)
            ctx.strokeStyle = Qt.rgba(ringColor.r, ringColor.g, ringColor.b, ringColor.a)
            ctx.lineWidth = ringWidth
            ctx.stroke()
        }
    }

    // ── wallpaper + scrim ────────────────────────────────────────────
    Image {
        anchors.fill: parent
        source: (typeof config !== "undefined" && config.background !== "")
                ? config.background : ""
        fillMode: Image.PreserveAspectCrop
        cache: true
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.25) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
        }
    }

    // ── mark + clock ──────────────────────────────────────────────
    // B3 — the greeter carries the Aegis mark with the same accent
    // progress device the plymouth splash paints (boot → login → desktop
    // reads as one continuous surface). The mark ships as mark.png in the
    // theme dir (synced from the transparent plymouth watermark); pure
    // QtQuick — no Effects plugin.
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.045
        spacing: 16

        Item {
            width: 56
            height: 54
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                anchors.fill: parent
                source: "mark.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                cache: true
            }

            // progress device — splash track + accent fill, at rest
            Item {
                width: 120
                height: 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: 10

                Rectangle {
                    anchors.fill: parent
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.14)
                }
                Rectangle {
                    width: 56
                    height: 2
                    radius: 1
                    color: root.accent
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.clockDate, "HH:mm")
            color: root.fg
            font { family: "Montserrat"; weight: Font.Light; pixelSize: 72; letterSpacing: 2 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.clockDate, "EEEE, d MMMM")
            color: root.fgMuted
            font { family: "Montserrat"; weight: Font.Medium; pixelSize: 15; letterSpacing: 3 }
        }
    }
    Timer {
        interval: 5000
        running: true
        triggeredOnStart: true
        repeat: true
        onTriggered: root.clockDate = new Date()
    }

    // ── login card ───────────────────────────────────────────────────
    Rectangle {
        id: card
        width: 340
        height: users.count > 1 ? 360 : 304
        radius: 28
        color: root.glass
        border.width: 1
        border.color: root.glassBorder
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 26

        SequentialAnimation {
            id: shake
            loops: 2
            NumberAnimation { target: card; property: "anchors.verticalCenterOffset";
                              from: 26; to: 32; duration: 55; easing.type: Easing.InOutQuad }
            NumberAnimation { target: card; property: "anchors.verticalCenterOffset";
                              from: 32; to: 26; duration: 55; easing.type: Easing.InOutQuad }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 14

            // avatar
            Item {
                width: 88; height: 88
                anchors.horizontalCenter: parent.horizontalCenter

                FaceAvatar {
                    anchors.fill: parent
                    facePath: root.selFace
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.selFace === "" && root.selName !== ""
                    text: root.selName.length > 0 ? root.selName.substring(0, 1).toUpperCase() : ""
                    color: root.fg
                    font { family: "Montserrat"; weight: Font.DemiBold; pixelSize: 34 }
                }
            }

            // name
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.selReal !== "" ? root.selReal : root.selName
                color: root.fg
                font { family: "Montserrat"; weight: Font.DemiBold; pixelSize: 17 }
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            // password pill
            Rectangle {
                id: pwPill
                width: parent.width
                height: 44
                radius: 22
                color: Qt.rgba(0, 0, 0, 0.30)
                border.width: pw.activeFocus ? 1.6 : 1
                border.color: pw.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                                             : root.glassBorder

                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "\u2022"
                    font { family: "Montserrat"; pixelSize: 14; letterSpacing: 1 }
                    color: root.fg
                    clip: true
                    enabled: !root.busy
                    onAccepted: root.tryLogin()
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pw.text.length === 0 && !pw.activeFocus
                    text: "Enter password"
                    color: root.fgMuted
                    font { family: "Montserrat"; pixelSize: 13 }
                }
            }

            // caps lock hint
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: typeof keyboardModel !== "undefined" && keyboardModel.capsLockOn
                text: "Caps Lock is on"
                color: Qt.rgba(1, 0.85, 0.55, 0.9)
                font { family: "Montserrat"; pixelSize: 11; letterSpacing: 0.5 }
            }

            // login button
            Rectangle {
                width: parent.width
                height: 44
                radius: 22
                color: root.busy ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                                 : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)

                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "Logging in…" : "Log In"
                    color: "#FFFFFF"
                    font { family: "Montserrat"; weight: Font.DemiBold; pixelSize: 14; letterSpacing: 1 }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.busy
                    onClicked: { pw.forceActiveFocus(); root.tryLogin() }
                }
            }

            // failure hint
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.hint !== ""
                text: root.hint
                color: "#FF9C9C"
                font { family: "Montserrat"; pixelSize: 11.5 }
            }
        }
    }

    // ── user strip (only with multiple accounts) ─────────────────────
    Row {
        id: users
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: card.bottom
        anchors.topMargin: 18
        spacing: 12
        visible: typeof userModel !== "undefined" && userModel.count > 1

        Repeater {
            model: typeof userModel !== "undefined" ? userModel : 0

            Item {
                width: 46
                height: 46

                FaceAvatar {
                    anchors.fill: parent
                    width: 46
                    height: 46
                    ringWidth: index === root.selected ? 2 : 1
                    facePath: model.face
                }
                Text {
                    anchors.centerIn: parent
                    visible: model.face === "" || model.face === undefined
                    text: (model.name !== undefined && model.name.length > 0)
                          ? model.name.substring(0, 1).toUpperCase() : ""
                    color: root.fg
                    font { family: "Montserrat"; weight: Font.DemiBold; pixelSize: 16 }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 23
                    color: "transparent"
                    border.width: index === root.selected ? 2 : 1
                    border.color: index === root.selected ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.10)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(index, model.name, model.realName, model.face)
                }
                Component.onCompleted: {
                    if (index === root.selected && root.selName === "")
                        root.select(index, model.name, model.realName, model.face)
                }
            }
        }
    }

    // ── bottom rail: wordmark + power ────────────────────────────────
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 22
        text: "Aegis OS"
        color: root.fgMuted
        font { family: "Montserrat"; weight: Font.Medium; pixelSize: 13; letterSpacing: 4 }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22
        spacing: 14

        Repeater {
            model: ListModel {
                ListElement { glyph: "restart" }
                ListElement { glyph: "power" }
            }

            delegate: Rectangle {
                width: 40; height: 40; radius: 20
                color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                border.width: 1
                border.color: root.glassBorder

                Canvas {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.85)
                        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.85)
                        ctx.lineWidth = 1.6
                        if (model.glyph === "power") {
                            ctx.beginPath()
                            ctx.arc(8, 8.5, 5.6, Math.PI * 0.75, Math.PI * 2.25)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(8, 1)
                            ctx.lineTo(8, 7)
                            ctx.stroke()
                        } else {
                            ctx.beginPath()
                            ctx.arc(8, 8, 6, Math.PI * 0.35, Math.PI * 1.75)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(13.6, 1.4)
                            ctx.lineTo(13.2, 6.4)
                            ctx.lineTo(8.6, 4.2)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: model.glyph === "restart" ? sddm.reboot() : sddm.powerOff()
                }
            }
        }
    }

    // ── SDDM signals ─────────────────────────────────────────────────
    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            pw.text = ""
            pw.forceActiveFocus()
            root.hint = "Wrong password — try again"
            shake.restart()
        }
        function onLoginSucceeded() {
            root.busy = true
        }
    }
}
