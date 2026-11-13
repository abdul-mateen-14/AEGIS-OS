import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Aegis.Util
import Aegis.Governor
import Aegis.Files
import Aegis.Display
import Aegis.Sound
import Aegis.Network
import Aegis.Users
import Aegis.Id

// Aegis Settings — first-party settings app (proposal §6, plates 10/11/13).
//
// Sidebar: Aegis ID row FIRST (38 px avatar + name + chevron, where Apple ID
// sits), then the §6 pane order — Wallpaper · Appearance · Desktop Effects ·
// Drivers & Firmware · Displays · Sound · Network · Users.
// Wired TODAY: Dark/Light (Util), tier control (Governor), the six accents
// (W5, one-token recolor), live wallpaper (W4, DBus into the shell), the
// four M3 backends (W3: kscreen-doctor · wpctl · NetworkManager D-Bus ·
// AccountsService D-Bus) and the Aegis ID account client (W6).
Window {
    id: win

    width: 900; height: 640
    minimumWidth: 520; minimumHeight: 360
    visible: true
    title: "Settings"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    // pane 0..7 = the panes below; 8 = Aegis ID. "aegis-settings 8" opens
    // straight into Aegis ID (boot-capture's pane screenshots).
    property int pane: (typeof aegisInitialPane !== "undefined")
                       ? aegisInitialPane : 0

    // the §6 pane order lives on the WINDOW: the sidebar Repeater and the
    // pane loader both resolve it as win.panes (one lookup, no inner-item
    // scoping surprises)
    property var panes: [
        { label: "Wallpaper",          tint: "#8B5CF6", glyph: "mountain" },
        { label: "Appearance",         tint: "#3E8BFF", glyph: "palette" },
        { label: "Desktop Effects",    tint: "#28C840", glyph: "sparkles" },
        { label: "Drivers & Firmware", tint: "#FF9F0A", glyph: "chip" },
        { label: "Displays",           tint: "#5B8BFF", glyph: "monitor" },
        { label: "Sound",              tint: "#FA2D48", glyph: "speaker" },
        { label: "Network",            tint: "#4AC8C8", glyph: "wifi" },
        { label: "Users",              tint: "#6E7BFF", glyph: "person" }
    ]

    // W31 — the §6 sidebar glyphs, same 18 px Canvas + stroke family as the
    // CC tiles (the panes model carried {label, tint} only, so the sidebar
    // rendered plain circles). Outline glyphs, one painter per pane, painted
    // white inside the tint circle — the v1.3 settings-sheet look.
    function paintPaneGlyph(name, ctx, w, h, color) {
        ctx.reset()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.5
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        const cx = w / 2, cy = h / 2
        // manual rounded rect — Context2D has no roundRect in the QML API
        const rrect = (x, y, rw, rh, r) => {
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + rw, y, x + rw, y + rh, r)
            ctx.arcTo(x + rw, y + rh, x, y + rh, r)
            ctx.arcTo(x, y + rh, x, y, r)
            ctx.arcTo(x, y, x + rw, y, r)
            ctx.closePath()
        }
        if (name === "mountain") {
            // image/mountain — frame + two peaks + sun dot
            ctx.beginPath()
            rrect(1.5, 3, w - 3, h - 6, 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(4, 13)
            ctx.lineTo(8, 7)
            ctx.lineTo(10.5, 10)
            ctx.lineTo(12, 8)
            ctx.lineTo(14.5, 13)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(11.6, 6, 1.1, 0, Math.PI * 2)
            ctx.fill()
        } else if (name === "palette") {
            // palette — blob with thumb hole + three paint wells
            ctx.beginPath()
            ctx.arc(cx, cy, 7, Math.PI * 0.85, Math.PI * 2.55)
            ctx.arc(cx + 1.2, cy + 1.2, 3.4, Math.PI * 2.2, Math.PI * 0.7,
                    true)
            ctx.closePath()
            ctx.stroke()
            const dots = [[cx - 3.4, cy - 1.6], [cx - 1.2, cy - 3.8],
                          [cx + 2.0, cy - 3.4]]
            for (const d of dots) {
                ctx.beginPath()
                ctx.arc(d[0], d[1], 1.05, 0, Math.PI * 2)
                ctx.fill()
            }
        } else if (name === "sparkles") {
            // desktop effects — one big + two small four-point stars
            const star = (x, y, r) => {
                ctx.beginPath()
                ctx.moveTo(x, y - r)
                ctx.quadraticCurveTo(x, y, x + r, y)
                ctx.quadraticCurveTo(x, y, x, y + r)
                ctx.quadraticCurveTo(x, y, x - r, y)
                ctx.quadraticCurveTo(x, y, x, y - r)
                ctx.closePath()
                ctx.fill()
            }
            star(cx - 1.5, cy - 0.5, 5)
            star(cx + 5, cy - 4.5, 2.4)
            star(cx + 4.5, cy + 4.5, 2)
        } else if (name === "chip") {
            // drivers & firmware — chip body, legs, inner die
            ctx.beginPath()
            rrect(4, 4, w - 8, h - 8, 2)
            ctx.stroke()
            ctx.beginPath()
            rrect(6.8, 6.8, w - 13.6, h - 13.6, 1)
            ctx.stroke()
            for (let i = 0; i < 3; ++i) {
                const p = 6.5 + i * 3.5
                ctx.beginPath(); ctx.moveTo(p, 1.5); ctx.lineTo(p, 4); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(p, h - 4); ctx.lineTo(p, h - 1.5); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(1.5, p); ctx.lineTo(4, p); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(w - 4, p); ctx.lineTo(w - 1.5, p); ctx.stroke()
            }
        } else if (name === "monitor") {
            // displays — screen + stand + base
            ctx.beginPath()
            rrect(2, 3, w - 4, h - 9, 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(cx, h - 6)
            ctx.lineTo(cx, h - 3)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(cx - 4, h - 3)
            ctx.lineTo(cx + 4, h - 3)
            ctx.stroke()
        } else if (name === "speaker") {
            // sound — driver body + one wave
            ctx.beginPath()
            ctx.moveTo(cx - 6, cy - 2.5)
            ctx.lineTo(cx - 3, cy - 2.5)
            ctx.lineTo(cx + 1, cy - 6.5)
            ctx.lineTo(cx + 1, cy + 6.5)
            ctx.lineTo(cx - 3, cy + 2.5)
            ctx.lineTo(cx - 6, cy + 2.5)
            ctx.closePath()
            ctx.fill()
            ctx.beginPath()
            ctx.arc(cx + 2.5, cy, 3.4, -Math.PI / 3, Math.PI / 3)
            ctx.stroke()
        } else if (name === "wifi") {
            // network — the CC paintWifi arcs
            const b = cy + 3.5
            for (let i = 1; i <= 3; ++i) {
                ctx.beginPath()
                ctx.arc(cx, b, i * 3.2, Math.PI * 1.25, Math.PI * 1.75, false)
                ctx.stroke()
            }
            ctx.beginPath()
            ctx.arc(cx, b, 1.5, 0, Math.PI * 2)
            ctx.fill()
        } else if (name === "person") {
            // users — head + shoulders
            ctx.beginPath()
            ctx.arc(cx, cy - 2.8, 3.2, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cx, cy + 6.2, 5.2, Math.PI * 1.15, Math.PI * 1.85)
            ctx.stroke()
        }
    }

    // W12 — the glass switch: the Control Center tile toggle's anatomy
    // (accent track when on, white knob on the standard easing) as a real
    // control. The stock Qt switch (dark pill, near-invisible knob) read
    // broken next to the rest of the system — "the toggles look bad".
    component GlassSwitch: Switch {
        id: gs
        // T15-D5 (W40) — the label must sit ON the pill's midline. A
        // replaced indicator is NOT positioned by the Control: without an
        // explicit x/y it landed at (0,0) — the top-left — while the
        // contentItem text was centered inside the padded content box
        // (measured on the user's Wallpaper capture: text ~5 px low, and
        // drifting further whenever a layout stretched the control).
        // padding: 0 kills the box asymmetry; y pins the knob to the
        // control's vertical center no matter how tall a layout makes it.
        padding: 0
        spacing: 10
        indicator: Rectangle {
            implicitWidth: 40
            implicitHeight: 24
            radius: 12
            x: 0
            y: (gs.height - 24) / 2
            color: gs.checked ? Tokens.accent
                              : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.14)
                                               : Qt.rgba(0, 0, 0, 0.12))
            border.width: 1
            border.color: gs.checked ? Tokens.accent
                                     : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.10)
                                                      : Qt.rgba(0, 0, 0, 0.08))
            Behavior on color { ColorAnimation { duration: 160 } }
            Rectangle {
                x: gs.checked ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 10
                color: "#FFFFFF"
                Behavior on x {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }
        }
        contentItem: Text {
            text: gs.text
            font: gs.font
            color: Tokens.fg
            verticalAlignment: Text.AlignVCenter
            leftPadding: gs.indicator.width + gs.spacing
        }
    }

    // Aegis ID field background — glass well, accent border on focus.
    component IdField: Rectangle {
        radius: 12
        color: Util.darkMode ? "#15161B" : "#F4F6FA"
        border.width: 1
        border.color: parent.activeFocus ? Tokens.accent : Tokens.glassBorder
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }

    function saveWallpaper(path) {
        Util.setWallpaper(path)   // persists + DBus-forwards to the shell
    }

    AppWindow {
        anchors.fill: parent
        title: "Settings"
        accent: Tokens.accent

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // 206 px sidebar — Aegis ID rail atop the §6 pane order
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 206
                color: Util.darkMode ? "#141519" : "#EDEFF4"
                Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: Tokens.glassBorder }

                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 2

                    // D6 — brand row: the 18 px mark + wordmark above the
                    // Aegis ID rail (reviewer carry-over on v0.6.34; the
                    // v1.3 ruling stands)
                    Row {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.topMargin: 2
                        Layout.bottomMargin: 6
                        spacing: 8

                        Image {
                            source: "aegis-mark.png"
                            sourceSize: Qt.size(18, 18)
                            width: 18; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Aegis"
                            font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                            color: Tokens.fg
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Aegis ID row — 38 px avatar + name + chevron (§6)
                    AbstractButton {
                        id: aegisRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        property bool active: win.pane === 8
                        background: Rectangle {
                            radius: 12
                            color: aegisRow.active ? Tokens.accent
                                                   : (Util.darkMode ? "#262930" : "#DDE3EE")
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            Item {
                                Layout.preferredWidth: 38; Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignVCenter
                                Rectangle {
                                    anchors.fill: parent; radius: 19
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "#56B0FF" }
                                        GradientStop { position: 1; color: "#1D6FEA" }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: AegisId.signedIn
                                          ? Util.userInitials
                                          : "\u25CB"
                                    font { pixelSize: 14; bold: true }
                                    color: "#FFFFFF"
                                }
                            }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0
                                Text {
                                    text: AegisId.signedIn ? AegisId.email : Util.userName
                                    font.pixelSize: 12; font.bold: true; color: Tokens.fg
                                    elide: Text.ElideMiddle
                                    Layout.maximumWidth: 130
                                }
                                Text {
                                    text: AegisId.signedIn ? "Aegis ID · signed in"
                                                           : "Aegis ID · Local account"
                                    font.pixelSize: 10; color: aegisRow.active ? "#FFFFFF" : Tokens.fgMuted
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "\u203a"; font.pixelSize: 18; color: aegisRow.active ? "#FFFFFF" : Tokens.fgMuted; Layout.alignment: Qt.AlignVCenter; Layout.rightMargin: 8 }
                        }
                        onClicked: win.pane = 8
                    }
                    Item { Layout.preferredHeight: 6 }

                    Repeater {
                        model: win.panes
                        delegate: AbstractButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            property bool active: win.pane === index
                            background: Rectangle {
                                radius: 8
                                color: parent.active ? (Util.darkMode ? "#262930" : "#DDE3EE") : "transparent"
                            }
                            contentItem: RowLayout {
                                spacing: 10
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.leftMargin: 10
                                    color: modelData.tint
                                    opacity: 0.9
                                    // W31 — the pane glyph inside the tint
                                    // circle (outline, white on the tint)
                                    Canvas {
                                        anchors.fill: parent
                                        onPaint: win.paintPaneGlyph(
                                            modelData.glyph,
                                            getContext("2d"), width, height,
                                            "#FFFFFF")
                                    }
                                }
                                Text { text: modelData.label; font.pixelSize: 13; color: Tokens.fg; Layout.alignment: Qt.AlignVCenter }
                                Item { Layout.fillWidth: true }
                            }
                            onClicked: win.pane = index
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // opaque body — panes
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 18
                spacing: 12

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: win.pane === 8 ? aegisIdPane
                                   : win.pane === 0 ? wallpaperPane
                                   : win.pane === 1 ? appearancePane
                                   : win.pane === 2 ? effectsPane
                                   : win.pane === 3 ? driversPane
                                   : win.pane === 4 ? displaysPane
                                   : win.pane === 5 ? soundPane
                                   : win.pane === 6 ? networkPane
                                   : usersPane
                }
            }
        }
    }

    // overlay host — sheets live OUTSIDE the RowLayout so anchors work
    Item {
        anchors.fill: parent
        z: 30
        visible: imagePickerHost.active || userRename.visible || wifiJoin.visible
        MouseArea { anchors.fill: parent; onClicked: (mouse) => { mouse.accepted = true; imagePickerHost.active = false; userRename.visible = false } }

        Loader {
            id: imagePickerHost
            anchors.fill: parent
            active: false
            sourceComponent: imagePickerComp
        }

        Rectangle {
            id: userRename
            property string targetPath: ""
            anchors.centerIn: parent
            width: 300; height: 130; radius: 18
            color: Util.darkMode ? "#23252B" : "#FFFFFF"
            border.color: Tokens.glassBorder
            visible: false
            Column {
                anchors { fill: parent; margins: 12 }
                spacing: 10
                Text { text: "Full name"; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                TextField {
                    id: userRenameInput
                    width: parent.width; font.pixelSize: 13
                    color: Tokens.fg
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#17181D" : "#F4F6FA"; border.color: Tokens.glassBorder }
                    onAccepted: {
                        Users.setRealName(userRename.targetPath, text)
                        userRename.visible = false
                    }
                }
            }
        }

        // W32.1 — the WPA join sheet: ssid + password field, working spin,
        // honest error state on a wrong secret (the activation is
        // agent-less, so the failure is read from the refreshed list: the
        // network is not inUse after the settle window).
        Rectangle {
            id: wifiJoin
            property string ssid: ""
            property string errorText: ""
            property bool working: false
            anchors.centerIn: parent
            width: 320; height: 190; radius: 18
            color: Util.darkMode ? "#23252B" : "#FFFFFF"
            border.color: Tokens.glassBorder
            visible: false
            function join() {
                if (wifiJoinInput.text.length < 8) {
                    wifiJoin.errorText = "A WPA password is at least 8 characters"
                    return
                }
                wifiJoin.working = true
                wifiJoin.errorText = ""
                Network.connectWithSecret(wifiJoin.ssid, wifiJoinInput.text)
                joinSettle.restart()
            }
            Timer {
                id: joinSettle
                interval: 7500
                onTriggered: {
                    wifiJoin.working = false
                    const nets = Network.networks
                    let inUse = false
                    for (const n of nets) {
                        if (n.ssid === wifiJoin.ssid && n.inUse) {
                            inUse = true
                            break
                        }
                    }
                    if (inUse) {
                        wifiJoin.visible = false
                    } else {
                        wifiJoin.errorText =
                            "Wrong password or network unreachable — try again"
                    }
                }
            }
            Column {
                anchors { fill: parent; margins: 14 }
                spacing: 10
                Text { text: wifiJoin.ssid; font.pixelSize: 13; font.bold: true; color: Tokens.fg; elide: Text.ElideMiddle; width: parent.width }
                Text { text: "Password"; font.pixelSize: 11; color: Tokens.fgMuted }
                TextField {
                    id: wifiJoinInput
                    width: parent.width; font.pixelSize: 13
                    echoMode: TextInput.Password
                    enabled: !wifiJoin.working
                    color: Tokens.fg
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#17181D" : "#F4F6FA"; border.color: Tokens.glassBorder }
                    onAccepted: wifiJoin.join()
                }
                Text {
                    visible: wifiJoin.errorText !== ""
                    text: wifiJoin.errorText
                    font.pixelSize: 11; color: "#FA2D48"
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Row {
                    spacing: 8
                    anchors.right: parent.right
                    AbstractButton {
                        width: 72; height: 26
                        enabled: !wifiJoin.working
                        contentItem: Text { text: "Cancel"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                        onClicked: { wifiJoin.visible = false; wifiJoin.working = false }
                    }
                    AbstractButton {
                        width: 96; height: 26
                        enabled: !wifiJoin.working
                        contentItem: Text { text: wifiJoin.working ? "Connecting…" : "Connect"; font.pixelSize: 11; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 8; color: wifiJoin.working ? Tokens.fgMuted : Tokens.accent }
                        onClicked: wifiJoin.join()
                    }
                }
            }
        }
    }

    // W4 — the glass image picker (FolderListModel — same stack as Files)
    Component {
        id: imagePickerComp
        Rectangle {
            id: picker
            anchors.fill: parent
            color: Util.darkMode ? "#17181D" : "#F4F6FA"
            opacity: 0.97

            property url folder: "file://" + Files.pathOf(Files.homeUrl()) + "/Pictures"

            RowLayout {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
                spacing: 8
                AbstractButton {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                    contentItem: Text { text: "\u2039"; font.pixelSize: 16; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter }
                    onClicked: {
                        const s = picker.folder.toString()
                        const up = s.slice(0, s.lastIndexOf("/"))
                        picker.folder = up && up !== "file:" ? up : "file:///"
                    }
                }
                Text {
                    text: Files.pathOf(picker.folder)
                    font.pixelSize: 11; color: Tokens.fgMuted
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                AbstractButton {
                    Layout.preferredHeight: 26; Layout.preferredWidth: 70
                    contentItem: Text { text: "Cancel"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4" }
                    onClicked: imagePickerHost.active = false
                }
            }

            FolderListModel {
                id: pickerModel
                folder: picker.folder
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                showDirs: true
            }
            GridView {
                anchors { fill: parent; margins: 12; topMargin: 48 }
                model: pickerModel
                cellWidth: 92; cellHeight: 92
                clip: true
                delegate: Item {
                    id: pickCell
                    width: 92; height: 92
                    Rectangle {
                        width: 84; height: 84; radius: 12
                        anchors.centerIn: parent
                        color: Util.darkMode ? "#17181D" : "#F4F6FA"
                        border.color: pickerMa.containsMouse ? Tokens.accent : Tokens.glassBorder
                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            source: filePath
                            fillMode: Image.PreserveAspectCrop
                            visible: !fileIsDir && status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: fileIsDir
                            text: "\uD83D\uDCC1"
                            font.pixelSize: 22
                        }
                        TapHandler {
                            id: pickerMa
                            onTapped: {
                                if (fileIsDir) picker.folder = filePath
                                else {
                                    win.saveWallpaper(filePath)
                                    imagePickerHost.active = false
                                }
                            }
                        }
                    }
                    Text {
                        anchors { top: parent.top; topMargin: 86; left: parent.left; right: parent.right }
                        text: fileName
                        font.pixelSize: 9; color: Tokens.fgMuted
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // ── W14 — Aegis ID (§6: identity, devices, sync; zero-knowledge client) ─
    // v0.6.27 redesign. The old pane was two bare 30 px fields and two small
    // buttons — "needs a lot of improvement". Now: a hero card (mark + pitch),
    // glass form wells (the IdField component, accent border on focus),
    // 34 px actions, feature tiles, and — signed in — account, sync and
    // device cards with separators.
    Component {
        id: aegisIdPane
        ColumnLayout {
            id: idPane
            spacing: 14

            property bool recoverySeen: false

            Text { text: "Aegis ID"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            Text {
                text: AegisId.signedIn
                      ? "One account across your Aegis devices"
                      : "Local account · sign in to turn on device sync"
                font.pixelSize: 12; color: Tokens.fgMuted
            }

            // recovery key — shown once, right after account creation
            Rectangle {
                visible: AegisId.recoveryKey.length > 0 && !idPane.recoverySeen
                Layout.fillWidth: true
                Layout.preferredHeight: 116
                radius: 14
                color: Util.darkMode ? "#221A10" : "#FFF6E0"
                border.color: "#FF9F0A"
                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 6
                    Text { text: "Recovery key — shown once"; font.pixelSize: 12; font.bold: true; color: "#FF9F0A" }
                    Text {
                        text: "Write it down and keep it safe. There is no server-side password recovery — this is the only offline backup for the sync vault."
                        font.pixelSize: 11; color: Tokens.fg
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        text: AegisId.recoveryKey
                        font { pixelSize: 16; family: "Monospace"; bold: true }
                        color: Tokens.fg
                    }
                    AbstractButton {
                        Layout.preferredHeight: 26; Layout.preferredWidth: 110
                        contentItem: Text { text: "I saved it"; font.pixelSize: 11; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 8; color: "#FF9F0A" }
                        onClicked: idPane.recoverySeen = true
                    }
                }
            }

            // ── signed-out: hero, form, what syncs, privacy ──────────────
            ColumnLayout {
                visible: !AegisId.signedIn
                spacing: 14

                // hero — the mark and the pitch
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 106
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    RowLayout {
                        anchors { fill: parent; margins: 16 }
                        spacing: 14
                        Rectangle {
                            width: 56; height: 56; radius: 16
                            color: Tokens.glassHighlight
                            Image {
                                anchors.centerIn: parent
                                source: "aegis-mark.png"
                                sourceSize: Qt.size(34, 34)
                            }
                        }
                        ColumnLayout {
                            spacing: 4
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Text { text: "Sign in to Aegis ID"; font.family: "Montserrat"; font.pixelSize: 16; font.weight: Font.DemiBold; color: Tokens.fg }
                            Text {
                                text: "Your accent, wallpaper and Files view travel with you — vault-encrypted end to end. The password never leaves this device."
                                font.pixelSize: 11; color: Tokens.fgMuted
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // form — glass wells, 34 px fields, Enter signs in
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: idFormCol.implicitHeight + 28
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    ColumnLayout {
                        id: idFormCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 10
                        TextField {
                            id: idEmail
                            Layout.fillWidth: true; Layout.preferredHeight: 34
                            placeholderText: "Email"
                            font.pixelSize: 12
                            color: Tokens.fg; placeholderTextColor: Tokens.fgMuted
                            leftPadding: 12
                            selectByMouse: true
                            background: IdField { }
                        }
                        TextField {
                            id: idPassword
                            Layout.fillWidth: true; Layout.preferredHeight: 34
                            placeholderText: "Password"
                            echoMode: TextInput.Password
                            font.pixelSize: 12
                            color: Tokens.fg; placeholderTextColor: Tokens.fgMuted
                            leftPadding: 12
                            selectByMouse: true
                            background: IdField { }
                            onAccepted: {
                                if (AegisId.state !== "working"
                                        && idEmail.text.length > 0
                                        && idPassword.text.length > 0)
                                    AegisId.signIn(idEmail.text, idPassword.text)
                            }
                        }
                        RowLayout {
                            spacing: 10
                            AbstractButton {
                                Layout.preferredHeight: 34; Layout.preferredWidth: 132
                                enabled: AegisId.state !== "working"
                                         && idEmail.text.length > 0
                                         && idPassword.text.length > 0
                                opacity: enabled ? 1 : 0.55
                                contentItem: Text {
                                    text: "Sign in"
                                    font { pixelSize: 12; family: "Montserrat"; weight: Font.DemiBold }
                                    color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 10; color: Tokens.accent }
                                onClicked: AegisId.signIn(idEmail.text, idPassword.text)
                            }
                            AbstractButton {
                                Layout.preferredHeight: 34; Layout.preferredWidth: 150
                                enabled: AegisId.state !== "working"
                                opacity: enabled ? 1 : 0.55
                                contentItem: Text {
                                    text: "Create account"
                                    font { pixelSize: 12; family: "Montserrat"; weight: Font.DemiBold }
                                    color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 10; border.color: Tokens.glassBorder
                                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                                }
                                onClicked: AegisId.registerAccount(idEmail.text, idPassword.text)
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.maximumWidth: 170
                                text: AegisId.state === "working" ? AegisId.statusText : ""
                                font.pixelSize: 11; color: Tokens.accent
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: AegisId.state === "error"
                            text: AegisId.statusText
                            font.pixelSize: 11; color: Tokens.danger
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        // W34 — the state line the review asked for: is the
                        // backend even connected? Last attempt time makes a
                        // silent-failure session diagnosable.
                        Text {
                            text: AegisId.backendState === "reachable"
                                  ? "Backend: reachable · last attempt " + AegisId.lastAttempt
                                  : AegisId.backendState === "unreachable"
                                    ? "Backend: unreachable · last attempt " + AegisId.lastAttempt
                                    : "Backend: not tried yet this session"
                            font.pixelSize: 10
                            color: AegisId.backendState === "reachable"
                                       ? Tokens.fgMuted
                                       : (AegisId.backendState === "unreachable"
                                              ? Tokens.danger : Tokens.fgMuted)
                        }
                    }
                }

                // what syncs — three tiles in the sidebar dot language
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: [
                            { t: "A", label: "Accent & theme", note: "follows you",  tint: "#3E8BFF" },
                            { t: "W", label: "Wallpaper",      note: "every desk",   tint: "#8B5CF6" },
                            { t: "F", label: "Files view",     note: "sorts, pins",  tint: "#34C77B" }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 58
                            radius: 14
                            color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                            border.color: Tokens.glassBorder
                            RowLayout {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; margins: 12 }
                                spacing: 10
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    color: modelData.tint
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.t
                                        font { pixelSize: 11; bold: true }
                                        color: "#FFFFFF"
                                    }
                                }
                                ColumnLayout {
                                    spacing: 1
                                    Text { text: modelData.label; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
                                    Text { text: modelData.note; font.pixelSize: 10; color: Tokens.fgMuted }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Zero-knowledge by construction: the vault key is derived on this device (PBKDF2-SHA256, 100k iterations), the server stores only a verifier, and sync payloads are AES-256-GCM encrypted with a key it never sees. Tokens live in the secret service, never in plaintext on disk."
                    font.pixelSize: 10; color: Tokens.fgMuted
                    wrapMode: Text.WordWrap
                }
            }

            // ── signed-in: account, sync, devices ─────────────────────────
            ColumnLayout {
                visible: AegisId.signedIn
                spacing: 14

                // account card — avatar, email, live dot
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    RowLayout {
                        anchors { fill: parent; margins: 16 }
                        spacing: 14
                        Rectangle {
                            width: 48; height: 48; radius: 24
                            color: Tokens.accent
                            Text {
                                anchors.centerIn: parent
                                text: AegisId.email.length > 0
                                      ? AegisId.email.charAt(0).toUpperCase() : "A"
                                font { pixelSize: 18; family: "Montserrat"; weight: Font.DemiBold }
                                color: "#FFFFFF"
                            }
                        }
                        ColumnLayout {
                            spacing: 3
                            Text {
                                text: AegisId.email
                                font { family: "Montserrat"; pixelSize: 14; weight: Font.DemiBold }
                                color: Tokens.fg
                            }
                            RowLayout {
                                spacing: 6
                                Rectangle { width: 7; height: 7; radius: 3.5; color: "#28C840" }
                                Text { text: "Aegis ID · signed in"; font.pixelSize: 11; color: Tokens.fgMuted }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 118; height: 22; radius: 11
                            color: Tokens.glassHighlight
                            Text {
                                anchors.centerIn: parent
                                text: "Zero-knowledge vault"
                                font.pixelSize: 9; color: Tokens.fgMuted
                            }
                        }
                    }
                }

                // sync card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: idSyncCol.implicitHeight + 28
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    ColumnLayout {
                        id: idSyncCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 10
                        Text { text: "Sync"; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                        RowLayout {
                            spacing: 10
                            AbstractButton {
                                Layout.preferredHeight: 32; Layout.preferredWidth: 120
                                enabled: AegisId.state !== "working"
                                opacity: enabled ? 1 : 0.55
                                contentItem: Text {
                                    text: "Sync now"
                                    font { pixelSize: 12; family: "Montserrat"; weight: Font.DemiBold }
                                    color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 10; color: Tokens.accent }
                                onClicked: AegisId.syncNow()
                            }
                            AbstractButton {
                                Layout.preferredHeight: 32; Layout.preferredWidth: 110
                                contentItem: Text { text: "Sign out"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle {
                                    radius: 10; border.color: Tokens.glassBorder
                                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                                }
                                onClicked: {
                                    idPane.recoverySeen = false
                                    AegisId.signOut()
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.maximumWidth: 260
                                text: AegisId.state === "working" ? AegisId.statusText : ""
                                font.pixelSize: 11; color: Tokens.accent
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            text: "accent · wallpaper · Files view — encrypted with your vault key, never readable on the server"
                            font.pixelSize: 10; color: Tokens.fgMuted
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            id: idSyncStatus
                            text: ""
                            font.pixelSize: 11; color: Tokens.fgMuted
                        }
                        Connections {
                            target: AegisId
                            function onSyncFinished(ok, message) {
                                idSyncStatus.text = ok ? "Sync OK — " + message
                                                       : "Sync failed — " + message
                            }
                        }
                    }
                }

                // devices card — rows with separators, the THIS DEVICE chip
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: idDevCol.implicitHeight + 28
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    ColumnLayout {
                        id: idDevCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 0
                        Text { text: "Devices"; font.pixelSize: 13; font.bold: true; color: Tokens.fg; bottomPadding: 8 }
                        Text {
                            visible: AegisId.devices.length === 0
                            text: "No devices yet — this one appears the moment you sign in."
                            font.pixelSize: 11; color: Tokens.fgMuted
                            topPadding: 4; bottomPadding: 4
                        }
                        Repeater {
                            model: AegisId.devices
                            delegate: ColumnLayout {
                                spacing: 0
                                Rectangle {
                                    visible: index > 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Tokens.glassBorder
                                    opacity: 0.5
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 11
                                    Layout.bottomMargin: 11
                                    spacing: 10
                                    Rectangle {
                                        width: 30; height: 30; radius: 15
                                        color: modelData.isThis ? Tokens.accent : Tokens.glassHighlight
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.platform === "linux" ? "L"
                                                  : modelData.platform === "android" ? "A"
                                                  : modelData.platform === "macos" ? "M" : "\u25CB"
                                            font { pixelSize: 12; bold: true }
                                            color: modelData.isThis ? "#FFFFFF" : Tokens.fg
                                        }
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        RowLayout {
                                            spacing: 6
                                            Text { text: modelData.name; font.pixelSize: 12; font.bold: modelData.isThis; color: Tokens.fg }
                                            Rectangle {
                                                visible: modelData.isThis
                                                width: 64; height: 16; radius: 4
                                                color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                                                Text { anchors.centerIn: parent; text: "THIS DEVICE"; font.pixelSize: 8; font.bold: true; color: "#28C840" }
                                            }
                                        }
                                        Text { text: "seen " + (modelData.lastSeen || "—"); font.pixelSize: 10; color: Tokens.fgMuted }
                                    }
                                    Item { Layout.fillWidth: true }
                                    AbstractButton {
                                        visible: !modelData.isThis
                                        Layout.preferredHeight: 26; Layout.preferredWidth: 84
                                        contentItem: Text { text: "Remove"; font.pixelSize: 11; color: Tokens.danger; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle {
                                            radius: 8; border.color: Tokens.glassBorder
                                            color: Util.darkMode ? "#262930" : "#E8ECF4"
                                        }
                                        onClicked: AegisId.revokeDevice(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ── W4 — Wallpaper (Table 15) — LIVE apply through the shell ──────────
    Component {
        id: wallpaperPane
        ColumnLayout {
            spacing: 14
            Text { text: "Wallpaper"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            RowLayout {
                spacing: 12
                Repeater {
                    model: [
                        { name: "Aurora Ink",    file: "aurora-ink.jpg",    top: "#2A3F55", bottom: "#0C1520", note: "Dark default" },
                        { name: "Graphite Dune", file: "graphite-dune.jpg", top: "#B8AFA4", bottom: "#6E6862", note: "Light default" },
                        { name: "Neon Coast",    file: "neon-coast.jpg",    top: "#FF7E5F", bottom: "#17A2A6", note: "The colorful pick" },
                        { name: "Emerald Ridge", file: "emerald-ridge.jpg", top: "#2F5D50", bottom: "#0E1F1A", note: "The calm pick" }
                    ]
                    delegate: ColumnLayout {
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 118; Layout.preferredHeight: 74
                            radius: 12
                            border.color: Util.wallpaper.indexOf(modelData.file) >= 0
                                          ? Tokens.accent : Tokens.glassBorder
                            border.width: Util.wallpaper.indexOf(modelData.file) >= 0 ? 2 : 1
                            gradient: Gradient {
                                GradientStop { position: 0; color: modelData.top }
                                GradientStop { position: 1; color: modelData.bottom }
                            }
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "/usr/share/wallpapers/aegis/" + modelData.file
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }
                            TapHandler {
                                onTapped: win.saveWallpaper(
                                    "/usr/share/wallpapers/aegis/"
                                    + modelData.file)
                            }
                        }
                        Text { text: modelData.name; font.pixelSize: 12; color: Tokens.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: modelData.note; font.pixelSize: 10; color: Tokens.fgMuted; Layout.alignment: Qt.AlignHCenter }
                    }
                }
                // dashed Choose image… tile — the SAME column anatomy as the
                // four wallpaper tiles (thumbnail band + name + note rows) so
                // it sits on the thumbnail line instead of floating mid-row;
                // 118 px keeps five tiles inside the 658 px pane width (the
                // old 132 px row overflowed and the button clipped at the
                // window edge).
                ColumnLayout {
                    spacing: 6
                    Rectangle {
                        Layout.preferredWidth: 118; Layout.preferredHeight: 74
                        radius: 12
                        color: "transparent"
                        border.color: Tokens.fgMuted
                        border.width: 1.5
                        Text { anchors.centerIn: parent; text: "Choose image\u2026"; font.pixelSize: 12; color: Tokens.fgMuted }
                        TapHandler { onTapped: imagePickerHost.active = true }
                    }
                    Text { text: "Custom"; font.pixelSize: 12; color: Tokens.fg; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "Your pictures"; font.pixelSize: 10; color: Tokens.fgMuted; Layout.alignment: Qt.AlignHCenter }
                }
            }
            GlassSwitch {
                // T15-D4 (W39.1) — REAL: the shell cycles the four bundled
                // wallpapers at session start + at the date rollover; the
                // toggle persists in tokens.conf and forwards over the bus
                text: "Rotate wallpapers daily"
                font.pixelSize: 13
                checked: Util.wallpaperRotateDaily
                onToggled: Util.setWallpaperRotateDaily(checked)
            }
            GlassSwitch {
                // T15-D4 (W39.1) — REAL: the wallpaperDim governor override
                // + the Desktop.qml veil (18% black while a normal window
                // is on the workspace, 200 ms ease)
                text: "Focus-dim wallpaper"
                font.pixelSize: 13
                checked: Governor.effects["wallpaperDim"] === true
                onToggled: Governor.setEffect("wallpaperDim", checked)
            }
            Text {
                text: Util.wallpaper
                font.pixelSize: 10; color: Tokens.fgMuted
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── Appearance (§6: Auto/Dark/Light cards + six accent presets, W5 live)
    Component {
        id: appearancePane
        ColumnLayout {
            spacing: 14
            Text { text: "Appearance"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            RowLayout {
                spacing: 12
                Repeater {
                    model: [
                        { label: "Auto",  dark: Util.darkMode },
                        { label: "Dark",  dark: true },
                        { label: "Light", dark: false }
                    ]
                    delegate: AbstractButton {
                        Layout.preferredWidth: 110; Layout.preferredHeight: 64
                        background: Rectangle {
                            radius: 12
                            color: modelData.dark ? "#17181D" : "#F4F6FA"
                            border.color: Tokens.accent; border.width: 2
                        }
                        contentItem: Text {
                            text: modelData.label
                            font.pixelSize: 13; font.bold: true
                            color: modelData.dark ? "#F2F4F8" : "#101216"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: Util.setDarkMode(modelData.dark)
                    }
                }
            }
            Text { text: "Accent — one token recolors the whole system"; font.pixelSize: 13; color: Tokens.fg }
            RowLayout {
                spacing: 10
                Repeater {
                    model: ["#3E8BFF", "#28C840", "#FF9F0A", "#FF6B84", "#8B5CF6", "#5B6068"]
                    delegate: Rectangle {
                        width: 28; height: 28; radius: 14
                        color: modelData
                        border.color: Tokens.fg; border.width: modelData === Tokens.accent ? 2 : 0
                        TapHandler { onTapped: Util.setAccent(modelData) }
                    }
                }
            }
            Text {
                text: "The accent persists at ~/.config/aegis/tokens.conf and syncs through Aegis ID."
                font.pixelSize: 11; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── Desktop Effects (Table 16: segmented tier control + six switches)
    Component {
        id: effectsPane
        ColumnLayout {
            spacing: 14
            Text { text: "Desktop Effects"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            RowLayout {
                spacing: 0
                Repeater {
                    model: [
                        { label: "Full",     tier: "A" },
                        { label: "Balanced", tier: "B" },
                        { label: "Calm",     tier: "C" }
                    ]
                    delegate: AbstractButton {
                        Layout.preferredWidth: 110; Layout.preferredHeight: 34
                        property bool active: Governor.tier === modelData.tier && !Governor.autoMode
                        background: Rectangle {
                            radius: index === 0 ? 10 : (index === 2 ? 10 : 0)
                            color: parent.active ? Tokens.accent : (Util.darkMode ? "#23252B" : "#FFFFFF")
                            border.color: Tokens.glassBorder
                        }
                        contentItem: Text {
                            text: modelData.label
                            font.pixelSize: 13
                            color: parent.active ? "#FFFFFF" : Tokens.fg
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: { Governor.setAutoMode(false); Governor.setTier(modelData.tier) }
                    }
                }
                Text {
                    text: Governor.autoMode ? "auto · tier " + Governor.tier : "manual"
                    font.pixelSize: 11; color: Tokens.fgMuted
                    Layout.leftMargin: 12
                }
            }

            Repeater {
                // T15-D4 (W39.2) — only REAL rows stay. The old model mixed
                // four real effect keys with tier shortcuts (tierA/tierAB/
                // tierC) and a parallax row that never existed — six rows
                // with NOT ONE onToggled handler, the exact "buttons are
                // placeholders" class the W37 sweep missed. Every row now
                // binds checked to the live governor state and toggles
                // through Governor.setEffect (persisted overrides ride over
                // the tier map); the cost chip rides only the row with a
                // measured cost.
                model: [
                    { label: "Live blur & transparency",   key: "blurLive",     chip: "\u22120.5 W" },
                    { label: "Blur behind decorations",    key: "blurAny",      chip: "" },
                    { label: "Window springs",             key: "motionSpring", chip: "" },
                    { label: "Half shadows in Calm",       key: "shadowsHalf",  chip: "" }
                ]
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Text { text: modelData.label; font.pixelSize: 13; color: Tokens.fg; Layout.fillWidth: true }
                    Rectangle {
                        visible: modelData.chip.length > 0
                        Layout.preferredWidth: 52; Layout.preferredHeight: 20; radius: 10
                        color: Util.darkMode ? "#23252B" : "#E8ECF4"
                        Text { anchors.centerIn: parent; text: modelData.chip; font.pixelSize: 10; font.family: "Monospace"; color: Tokens.fgMuted }
                    }
                    GlassSwitch {
                        checked: Governor.effects[modelData.key] === true
                        onToggled: Governor.setEffect(modelData.key, checked)
                    }
                }
            }
            Text {
                text: "Tier control stays in the Control Center — these switches set per-effect overrides that ride over the tier and persist."
                font.pixelSize: 11; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── D23 (W33) — Drivers & Firmware: the real inventory ────────────────
    // The pane used to be the static BUILT-IN placeholder list (the W37
    // poster child). Every section now renders REAL data with an explicit
    // empty state — never blank: device inventory (lspci/lsusb/lsblk with
    // the kernel driver per PCI device), printing (CUPS queues + test
    // page + CUPS web UI; cups-pdf waits for an archive reintroduction —
    // TASKS.md D16), scanning (simple-scan), power & charging (Util's
    // sysfs read; VMs say "AC power"), firmware (fwupdmgr best-effort)
    // and the presentation toggle lives in Displays.
    Component {
        id: driversPane
        ColumnLayout {
            spacing: 12
            Component.onCompleted: Drivers.refresh()

            Text { text: "Drivers & Firmware"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            // Power & charging — Util reads /sys/class/power_supply; a VM
            // without a battery reads "AC power" honestly.
            Text { text: "Power"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            Text {
                text: Util.onBattery
                      ? "Battery — " + Util.batteryPercent + "%"
                        + (Util.charging ? ", charging" : "")
                      : "AC power"
                font.pixelSize: 11; color: Tokens.fgMuted
            }

            // Device inventory — categories with the kernel driver where
            // resolvable; zero devices renders the explicit empty line.
            Text { text: "Device inventory"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            Repeater {
                model: ["Graphics", "Network", "Audio", "Storage"]
                delegate: ColumnLayout {
                    id: pciCat
                    property string cat: modelData
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: pciCat.cat
                        font { pixelSize: 11; bold: true }
                        color: Tokens.fgMuted
                    }
                    Repeater {
                        model: Drivers.pciDevices.filter(
                                   function (d) { return d.category === pciCat.cat })
                        delegate: Text {
                            text: modelData.name
                                  + (modelData.driver
                                     ? "  —  driver: " + modelData.driver
                                     : "  —  no kernel driver bound")
                            font.pixelSize: 11
                            color: Tokens.fg
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                    Text {
                        visible: Drivers.pciDevices.filter(
                                     function (d) { return d.category === pciCat.cat }).length === 0
                        text: "No devices in this class"
                        font.pixelSize: 11; color: Tokens.fgMuted
                    }
                }
            }
            Text {
                text: "USB"
                font { pixelSize: 11; bold: true }
                color: Tokens.fgMuted
            }
            Repeater {
                model: Drivers.usbDevices
                delegate: Text {
                    text: modelData.name
                    font.pixelSize: 11; color: Tokens.fg
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
            Text {
                visible: Drivers.usbDevices.length === 0
                text: "No USB devices visible"
                font.pixelSize: 11; color: Tokens.fgMuted
            }
            Text {
                text: "Storage"
                font { pixelSize: 11; bold: true }
                color: Tokens.fgMuted
            }
            Repeater {
                model: Drivers.storageDevices
                delegate: Text {
                    text: "/dev/" + modelData.name + " — " + modelData.size
                    font.pixelSize: 11; color: Tokens.fg
                }
            }
            Text {
                visible: Drivers.storageDevices.length === 0
                text: "No disks visible"
                font.pixelSize: 11; color: Tokens.fgMuted
            }

            // Printing — real CUPS queues; the buttons act (test page
            // through lp, the CUPS web UI at localhost:631).
            Text { text: "Printing"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            Repeater {
                model: Drivers.printers
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: modelData.name + " — " + modelData.state
                        font.pixelSize: 11; color: Tokens.fg
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    AbstractButton {
                        Layout.preferredHeight: 24; Layout.preferredWidth: 84
                        contentItem: Text { text: "Test page"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                        onClicked: Drivers.printTestPage(modelData.name)
                    }
                }
            }
            Text {
                visible: Drivers.printers.length === 0
                text: "No print queues — printers added through CUPS appear here"
                font.pixelSize: 11; color: Tokens.fgMuted
            }
            Text {
                text: "Print to PDF: not available — cups-pdf is missing from the archive (TASKS D16)"
                font.pixelSize: 10; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            RowLayout {
                spacing: 8
                AbstractButton {
                    Layout.preferredHeight: 26; Layout.preferredWidth: 108
                    contentItem: Text { text: "Open CUPS\u2026"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                    onClicked: Drivers.openCups()
                }
                AbstractButton {
                    Layout.preferredHeight: 26; Layout.preferredWidth: 84
                    contentItem: Text { text: "Refresh"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                    onClicked: Drivers.refresh()
                }
            }

            // Scanning
            Text { text: "Scanning"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            RowLayout {
                spacing: 8
                Text {
                    text: Drivers.scanState === "ready"
                          ? "Document scanner ready (simple-scan)"
                          : "No scanner tool in this build"
                    font.pixelSize: 11; color: Tokens.fgMuted
                    Layout.fillWidth: true
                }
                AbstractButton {
                    visible: Drivers.scanState === "ready"
                    Layout.preferredHeight: 26; Layout.preferredWidth: 84
                    contentItem: Text { text: "Open scan\u2026"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                    onClicked: Drivers.launchScanner()
                }
            }

            // Firmware
            Text { text: "Firmware"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            RowLayout {
                spacing: 8
                Text {
                    text: Drivers.firmwareState === "uptodate"
                          ? "No firmware updates available"
                          : Drivers.firmwareState === "checking"
                            ? "Checking fwupd\u2026"
                            : Drivers.firmwareState === "unavailable"
                              ? "fwupd not reachable in this build"
                              : Drivers.firmwareState + " available"
                    font.pixelSize: 11; color: Tokens.fgMuted
                    Layout.fillWidth: true
                }
                AbstractButton {
                    Layout.preferredHeight: 26; Layout.preferredWidth: 84
                    contentItem: Text { text: "Check"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                    onClicked: Drivers.refreshFirmware()
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── W3 — Displays (kscreen-doctor: modes · scale · night light) ───────
    Component {
        id: displaysPane
        ColumnLayout {
            spacing: 12
            Text { text: "Displays"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            // D21 (W30.1/W33.4) — presentation mode, the "presentations
            // using laptops" ask: sleep + screen-off inhibited for as long
            // as it is on (org.freedesktop.ScreenSaver), brightness pinned
            // to max while presenting and restored after. The state file
            // (~/.local/state/aegis-shell/aegis/presentation) is the boot
            // harness's file-based verdict.
            property real savedBrightness: -1
            GlassSwitch {
                id: presentationSwitch
                text: "Presentation mode — keep the screen awake"
                font.pixelSize: 13
                checked: Displays.presentation
                onToggled: {
                    Displays.setPresentation(checked)
                    if (checked) {
                        savedBrightness = Util.brightness >= 0
                                         ? Util.brightness : 0.6
                        Util.setBrightness(1.0)
                    } else if (savedBrightness >= 0) {
                        Util.setBrightness(savedBrightness)
                    }
                }
            }
            Text {
                text: Displays.presentation
                      ? "Presentation on — sleep and screen-off inhibited; brightness pinned to max"
                      : "Off — the screen sleeps on the normal idle timer"
                font.pixelSize: 11; color: Tokens.fgMuted
            }

            RowLayout {
                spacing: 10
                Text {
                    text: Displays.outputs.length
                          ? Displays.outputs.length + " output(s)"
                          : "kscreen-doctor not available — no output list"
                    font.pixelSize: 11; color: Tokens.fgMuted
                    Layout.fillWidth: true
                }
                AbstractButton {
                    Layout.preferredHeight: 26; Layout.preferredWidth: 80
                    contentItem: Text { text: "Refresh"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                    onClicked: Displays.refresh()
                }
            }

            GlassSwitch {
                text: "Night light (evening 20:00 – 06:00, warm)"
                font.pixelSize: 13
                checked: Displays.nightLight
                onToggled: Displays.setNightLight(checked)
            }

            Repeater {
                model: Displays.outputs
                delegate: ColumnLayout {
                    id: outCard
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 1; color: Tokens.glassBorder
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: outCard.modelData.name; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                        Text {
                            text: outCard.modelData.current
                            font.pixelSize: 11; color: Tokens.fgMuted
                        }
                        Text {
                            text: "scale " + outCard.modelData.scale + "\u00d7"
                            font.pixelSize: 11; color: Tokens.fgMuted
                        }
                        Item { Layout.fillWidth: true }
                        AbstractButton {
                            id: resButton
                            Layout.preferredHeight: 26; Layout.preferredWidth: 120
                            contentItem: Text { text: "Resolution\u2026"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                            onClicked: modeMenu.popup(resButton, 0, resButton.height + 2)
                            Menu {
                                id: modeMenu
                                dim: false
                                Repeater {
                                    model: outCard.modelData.modes
                                    delegate: MenuItem {
                                        text: modelData.mode
                                        checkable: true
                                        checked: modelData.mode === outCard.modelData.current
                                        onTriggered: Displays.setResolution(outCard.modelData.name, modelData.mode)
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        spacing: 6
                        Text { text: "Scale:"; font.pixelSize: 11; color: Tokens.fgMuted }
                        Repeater {
                            model: [1.0, 1.25, 1.5, 2.0]
                            delegate: AbstractButton {
                                Layout.preferredWidth: 46; Layout.preferredHeight: 22
                                property bool active: Math.abs(outCard.modelData.scale - modelData) < 0.001
                                background: Rectangle {
                                    radius: 6
                                    color: parent.active ? Tokens.accent : (Util.darkMode ? "#23252B" : "#FFFFFF")
                                    border.color: Tokens.glassBorder
                                }
                                contentItem: Text {
                                    text: modelData + "\u00d7"
                                    font.pixelSize: 11
                                    color: parent.active ? "#FFFFFF" : Tokens.fg
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: Displays.setScale(outCard.modelData.name, modelData)
                            }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── W3 — Sound (wpctl / PipeWire: sinks · sources · default) ─────────
    Component {
        id: soundPane
        ColumnLayout {
            spacing: 12
            Text { text: "Sound"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            Text { text: "Output"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            Repeater {
                model: Sound.sinks
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: modelData.name; font.pixelSize: 12; color: Tokens.fg; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        Rectangle {
                            visible: modelData.isDefault
                            width: 58; height: 16; radius: 4
                            color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                            Text { anchors.centerIn: parent; text: "DEFAULT"; font.pixelSize: 8; font.bold: true; color: "#28C840" }
                        }
                        AbstractButton {
                            visible: !modelData.isDefault
                            Layout.preferredHeight: 22; Layout.preferredWidth: 74
                            contentItem: Text { text: "Set default"; font.pixelSize: 10; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 6; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                            onClicked: Sound.setDefault(modelData.id)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        GlassSwitch {
                            text: "Mute"
                            font.pixelSize: 11
                            checked: modelData.muted
                            onToggled: Sound.setMuted(modelData.id, checked)
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0; to: 1.0
                            value: modelData.volume
                            palette.highlight: Tokens.accent
                            onMoved: Sound.setVolume(modelData.id, value)
                        }
                        Text {
                            text: Math.round(modelData.volume * 100) + "%"
                            font.pixelSize: 11; color: Tokens.fgMuted
                        }
                    }
                }
            }

            Text { text: "Input"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
            Repeater {
                model: Sound.sources
                delegate: Text {
                    text: "\u2022 " + modelData.name
                    font.pixelSize: 12; color: Tokens.fgMuted
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
            Text {
                visible: Sound.sinks.length === 0
                // W30 — the three empty states are different facts; one
                // placeholder line for all of them read as a broken pane.
                text: Sound.state === "nowpctl"
                      ? "wpctl not available — PipeWire session not found"
                      : "No output device — PipeWire is running but no audio hardware is exposed"
                font.pixelSize: 11; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            AbstractButton {
                Layout.preferredHeight: 26; Layout.preferredWidth: 80
                contentItem: Text { text: "Refresh"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                onClicked: Sound.refresh()
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── W3 — Network (NetworkManager D-Bus) ──────────────────────────────
    Component {
        id: networkPane
        ColumnLayout {
            spacing: 10
            Component.onCompleted: { Network.loadKnown(); Network.refresh(); Bluetooth.refresh() }

            Text { text: "Network"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            // W30/W32 — the wired section first: VMs are ethernet-only and
            // the pane must never read as dead. One row per ethernet device
            // with its honest carrier state.
            Repeater {
                model: Network.wired
                delegate: Rectangle {
                    id: wiredRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: modelData.active ? 62 : 38
                    radius: 8
                    color: Util.darkMode ? "#1E2026" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            Layout.alignment: Qt.AlignVCenter
                            color: modelData.active ? "#28C840"
                                                    : (modelData.plugged ? Tokens.accent
                                                                         : (Util.darkMode ? "#3A3D45" : "#C6CCD8"))
                        }
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            // T15-D6 (W43) — the row carries real substance:
                            // iface + Connected + the live IPv4 (a row that
                            // says only "Wired — ens160: Connected" reads
                            // inert; the user concluded "no ethernet option"
                            // from exactly such a row)
                            Text {
                                text: "Wired — " + modelData.iface
                                      + (modelData.active
                                         ? " · Connected · " + Util.wiredIp
                                         : (modelData.plugged ? " · Cable connected"
                                                              : " · Cable unplugged"))
                                font.pixelSize: 12; color: Tokens.fg
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }
                            // the honest VM line: NAT IS wired; a radio
                            // cannot exist there — stops the "where is the
                            // Wi-Fi toggle" hunt before it starts
                            Text {
                                visible: modelData.active
                                text: "Virtual machines expose NAT as wired ethernet; Wi-Fi needs a physical radio"
                                font.pixelSize: 10; color: Tokens.fgMuted
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                        // T15-D6 — Disconnect / Reconnect: real NM actions
                        // (nmcli device disconnect/connect), not chrome
                        AbstractButton {
                            visible: modelData.active
                            Layout.preferredHeight: 26; Layout.preferredWidth: 88
                            contentItem: Text { text: "Disconnect"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                            onClicked: Util.disconnectWired(modelData.iface)
                        }
                        AbstractButton {
                            visible: !modelData.active
                            Layout.preferredHeight: 26; Layout.preferredWidth: 88
                            contentItem: Text { text: "Reconnect"; font.pixelSize: 11; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Tokens.accent }
                            onClicked: Util.reconnectWired(modelData.iface)
                        }
                    }
                }
            }

            RowLayout {
                GlassSwitch {
                    text: "Wi-Fi"
                    font.pixelSize: 13
                    checked: Network.wifiEnabled
                    onToggled: Network.setWifiEnabled(checked)
                }
                Item { Layout.fillWidth: true }
            }

            Repeater {
                model: Network.networks
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 8
                    color: Util.darkMode ? "#1E2026" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        // signal bars
                        Item {
                            Layout.preferredWidth: 18; Layout.preferredHeight: 18
                            Repeater {
                                model: 4
                                delegate: Rectangle {
                                    x: index * 4
                                    width: 3
                                    height: 4 + index * 4
                                    anchors.bottom: parent.bottom
                                    radius: 1
                                    color: modelData.strength >= index * 25 + 10
                                           ? Tokens.fg : (Util.darkMode ? "#3A3D45" : "#C6CCD8")
                                }
                            }
                        }
                        Text { text: modelData.ssid; font.pixelSize: 12; color: Tokens.fg; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        Rectangle {
                            visible: modelData.inUse
                            width: 40; height: 16; radius: 4
                            color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                            Text { anchors.centerIn: parent; text: "NOW"; font.pixelSize: 8; font.bold: true; color: "#28C840" }
                        }
                        Rectangle {
                            visible: modelData.known && !modelData.inUse
                            width: 52; height: 16; radius: 4
                            color: Util.darkMode ? "#23252B" : "#E8ECF4"
                            Text { anchors.centerIn: parent; text: "KNOWN"; font.pixelSize: 8; font.bold: true; color: Tokens.fgMuted }
                        }
                        Rectangle {
                            visible: modelData.secure
                            width: 44; height: 16; radius: 4
                            color: "transparent"
                            border.color: Tokens.glassBorder
                            Text { anchors.centerIn: parent; text: "WPA"; font.pixelSize: 8; color: Tokens.fgMuted }
                        }
                        Text { text: modelData.strength + "%"; font.pixelSize: 10; color: Tokens.fgMuted }
                        AbstractButton {
                            visible: !modelData.inUse
                            Layout.preferredHeight: 24; Layout.preferredWidth: 72
                            contentItem: Text { text: modelData.known ? "Connect" : "Join"; font.pixelSize: 11; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Tokens.accent }
                            // W32.1 — secure unknown networks open the
                            // password sheet; open and known networks join
                            // directly (NM picks the stored secret).
                            onClicked: {
                                if (modelData.secure && !modelData.known) {
                                    wifiJoin.ssid = modelData.ssid
                                    wifiJoin.errorText = ""
                                    wifiJoinInput.text = ""
                                    wifiJoin.visible = true
                                    wifiJoinInput.forceActiveFocus()
                                } else {
                                    Network.connectTo(modelData.ssid)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: Network.networks.length === 0
                // W32 — a VM with no Wi-Fi radio must say so, not "scanning".
                text: !Network.hasWifi
                      ? "No Wi-Fi device — wired networking is above"
                      : Network.wifiEnabled
                        ? "No networks visible — scanning…"
                        : "Wi-Fi is off"
                font.pixelSize: 11; color: Tokens.fgMuted
            }
            AbstractButton {
                Layout.preferredHeight: 26; Layout.preferredWidth: 80
                contentItem: Text { text: "Refresh"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                onClicked: { Network.loadKnown(); Network.refresh() }
            }
            Text {
                text: "WPA networks need a stored secret (connect once from the live session); open networks join directly."
                font.pixelSize: 10; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // D22 (W32.3) — the Bluetooth section: the CC tile toggles the
            // adapter power (Util.setBluetoothEnabled), this section is the
            // device surface. A VM with no adapter says so instead of
            // rendering a dead empty list.
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Tokens.glassBorder }
            Text { text: "Bluetooth"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }

            Text {
                text: Bluetooth.state === "noctl"
                      ? "bluetoothctl not available in this build"
                      : Bluetooth.state === "noadapter"
                        ? "No Bluetooth adapter — devices will appear here when one is present"
                        : Bluetooth.state === "off"
                          ? "Bluetooth adapter is off — use the control center tile to power it"
                          : (Bluetooth.scanning
                             ? "Scanning\u2026 (8 s discovery)"
                             : Bluetooth.devices.length === 0
                               ? "Adapter on — no devices paired yet"
                               : Bluetooth.devices.length
                                 + " paired device(s)")
                font.pixelSize: 11; color: Tokens.fgMuted
            }

            Repeater {
                model: Bluetooth.devices
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 8
                    color: Util.darkMode ? "#1E2026" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            Layout.alignment: Qt.AlignVCenter
                            color: modelData.connected ? "#28C840"
                                                       : (Util.darkMode ? "#3A3D45" : "#C6CCD8")
                        }
                        Text {
                            text: modelData.name
                            font.pixelSize: 12; color: Tokens.fg
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            visible: modelData.connected
                            width: 64; height: 16; radius: 4
                            color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                            Text { anchors.centerIn: parent; text: "CONNECTED"; font.pixelSize: 8; font.bold: true; color: "#28C840" }
                        }
                        AbstractButton {
                            Layout.preferredHeight: 24; Layout.preferredWidth: modelData.connected ? 84 : 72
                            contentItem: Text { text: modelData.connected ? "Disconnect" : (modelData.trusted ? "Connect" : "Pair"); font.pixelSize: 11; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Tokens.accent }
                            onClicked: {
                                if (modelData.connected)
                                    Bluetooth.disconnectDevice(modelData.mac)
                                else if (modelData.trusted)
                                    Bluetooth.connectDevice(modelData.mac)
                                else
                                    Bluetooth.pairDevice(modelData.mac)
                            }
                        }
                        AbstractButton {
                            Layout.preferredHeight: 24; Layout.preferredWidth: 64
                            contentItem: Text { text: "Forget"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                            onClicked: Bluetooth.forgetDevice(modelData.mac)
                        }
                    }
                }
            }

            AbstractButton {
                visible: Bluetooth.state === "idle"
                Layout.preferredHeight: 26; Layout.preferredWidth: 88
                contentItem: Text { text: Bluetooth.scanning ? "Working\u2026" : "Scan"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                onClicked: Bluetooth.startScan()
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── W3 — Users (AccountsService D-Bus, §6 person glyph) ──────────────
    Component {
        id: usersPane
        ColumnLayout {
            spacing: 10
            Text { text: "Users"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            Repeater {
                model: Users.users
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 10
                    color: Util.darkMode ? "#1E2026" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 34; Layout.preferredHeight: 34
                            radius: 17
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#56B0FF" }
                                GradientStop { position: 1; color: "#1D6FEA" }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: (modelData.realName || modelData.userName).slice(0, 1).toUpperCase()
                                font { pixelSize: 13; bold: true }
                                color: "#FFFFFF"
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: modelData.realName || modelData.userName
                                font { pixelSize: 12; bold: true }
                                color: Tokens.fg
                            }
                            Text { text: modelData.userName; font.pixelSize: 10; color: Tokens.fgMuted }
                        }
                        Rectangle {
                            visible: modelData.admin
                            width: 64; height: 16; radius: 4
                            color: Util.darkMode ? "#23252B" : "#E8ECF4"
                            Text { anchors.centerIn: parent; text: "ADMIN"; font.pixelSize: 8; font.bold: true; color: Tokens.fgMuted }
                        }
                        Rectangle {
                            visible: modelData.isYou
                            width: 40; height: 16; radius: 4
                            color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                            Text { anchors.centerIn: parent; text: "YOU"; font.pixelSize: 8; font.bold: true; color: "#28C840" }
                        }
                        Item { Layout.fillWidth: true }
                        GlassSwitch {
                            visible: modelData.isYou
                            text: "Administrator"
                            font.pixelSize: 11
                            checked: modelData.admin
                            onToggled: Users.setAdmin(modelData.path, checked)
                        }
                        AbstractButton {
                            visible: modelData.isYou
                            Layout.preferredHeight: 24; Layout.preferredWidth: 96
                            contentItem: Text { text: "Rename\u2026"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle {
                                radius: 8; border.color: Tokens.glassBorder
                                color: Util.darkMode ? "#262930" : "#E8ECF4"
                            }
                            onClicked: {
                                userRename.targetPath = modelData.path
                                userRename.visible = true
                                userRename.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            Text {
                visible: Users.users.length === 0
                text: "AccountsService not reachable on this session bus"
                font.pixelSize: 11; color: Tokens.fgMuted
            }
            AbstractButton {
                Layout.preferredHeight: 26; Layout.preferredWidth: 80
                contentItem: Text { text: "Refresh"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                onClicked: Users.refresh()
            }
            Item { Layout.fillHeight: true }
        }
    }
}
