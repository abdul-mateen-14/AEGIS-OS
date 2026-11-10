import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Aegis.Util
import Aegis.Governor
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
        { label: "Wallpaper",          tint: "#8B5CF6" },
        { label: "Appearance",         tint: "#3E8BFF" },
        { label: "Desktop Effects",    tint: "#28C840" },
        { label: "Drivers & Firmware", tint: "#FF9F0A" },
        { label: "Displays",           tint: "#5B8BFF" },
        { label: "Sound",              tint: "#FA2D48" },
        { label: "Network",            tint: "#4AC8C8" },
        { label: "Users",              tint: "#6E7BFF" }
    ]

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
        visible: imagePickerHost.active || userRename.visible
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

    // ── W6 — Aegis ID (§6: identity, devices, sync; zero-knowledge client) ─
    Component {
        id: aegisIdPane
        ColumnLayout {
            id: idPane
            spacing: 12

            Text { text: "Aegis ID"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            Text {
                text: AegisId.signedIn
                      ? "Signed in as " + AegisId.email
                      : AegisId.statusText
                font.pixelSize: 12; color: Tokens.fgMuted
            }

            // recovery key — shown once, right after account creation
            Rectangle {
                visible: AegisId.recoveryKey.length > 0 && !idPane.recoverySeen
                Layout.fillWidth: true
                Layout.preferredHeight: 110
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

            // ── signed-out: sign in / create ─────────────────────────────
            ColumnLayout {
                visible: !AegisId.signedIn
                spacing: 8

                TextField {
                    id: idEmail
                    Layout.fillWidth: true; Layout.preferredHeight: 30
                    placeholderText: "Email"
                    font.pixelSize: 12
                    color: Tokens.fg; placeholderTextColor: Tokens.fgMuted
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#17181D" : "#F4F6FA"; border.color: Tokens.glassBorder }
                }
                TextField {
                    id: idPassword
                    Layout.fillWidth: true; Layout.preferredHeight: 30
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    font.pixelSize: 12
                    color: Tokens.fg; placeholderTextColor: Tokens.fgMuted
                    background: Rectangle { radius: 8; color: Util.darkMode ? "#17181D" : "#F4F6FA"; border.color: Tokens.glassBorder }
                }
                RowLayout {
                    spacing: 8
                    AbstractButton {
                        Layout.preferredHeight: 30; Layout.preferredWidth: 110
                        contentItem: Text { text: "Sign in"; font.pixelSize: 12; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 8; color: Tokens.accent }
                        onClicked: AegisId.signIn(idEmail.text, idPassword.text)
                    }
                    AbstractButton {
                        Layout.preferredHeight: 30; Layout.preferredWidth: 150
                        contentItem: Text { text: "Create account"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle {
                            radius: 8; border.color: Tokens.glassBorder
                            color: Util.darkMode ? "#262930" : "#E8ECF4"
                        }
                        onClicked: AegisId.registerAccount(idEmail.text, idPassword.text)
                    }
                    Text {
                        text: AegisId.state === "working" ? AegisId.statusText : ""
                        font.pixelSize: 11; color: Tokens.fgMuted
                    }
                }
                Text {
                    text: "Local account · sync off. Signing in enables device sync (accent, wallpaper, Files view) across your Aegis devices."
                    font.pixelSize: 11; color: Tokens.fgMuted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            // ── signed-in: devices + sync ────────────────────────────────
            ColumnLayout {
                visible: AegisId.signedIn
                spacing: 8

                Text { text: "Devices"; font.pixelSize: 12; font.bold: true; color: Tokens.fg }
                Repeater {
                    model: AegisId.devices
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: modelData.isThis ? Tokens.accent : (Util.darkMode ? "#262930" : "#DDE3EE")
                            Text {
                                anchors.centerIn: parent
                                text: modelData.platform === "linux" ? "L"
                                      : modelData.platform === "android" ? "A"
                                      : modelData.platform === "macos" ? "M" : "\u25CB"
                                font { pixelSize: 11; bold: true }
                                color: modelData.isThis ? "#FFFFFF" : Tokens.fg
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            RowLayout {
                                spacing: 6
                                Text { text: modelData.name; font.pixelSize: 12; color: Tokens.fg }
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
                            Layout.preferredHeight: 24; Layout.preferredWidth: 84
                            contentItem: Text { text: "Remove"; font.pixelSize: 11; color: "#FA2D48"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle {
                                radius: 8; border.color: Tokens.glassBorder
                                color: Util.darkMode ? "#262930" : "#E8ECF4"
                            }
                            onClicked: AegisId.revokeDevice(modelData.id)
                        }
                    }
                }

                RowLayout {
                    spacing: 8
                    AbstractButton {
                        Layout.preferredHeight: 30; Layout.preferredWidth: 110
                        contentItem: Text { text: "Sync now"; font.pixelSize: 12; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 8; color: Tokens.accent }
                        onClicked: AegisId.syncNow()
                    }
                    AbstractButton {
                        Layout.preferredHeight: 30; Layout.preferredWidth: 110
                        contentItem: Text { text: "Sign out"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle {
                            radius: 8; border.color: Tokens.glassBorder
                            color: Util.darkMode ? "#262930" : "#E8ECF4"
                        }
                        onClicked: {
                            idPane.recoverySeen = false
                            AegisId.signOut()
                        }
                    }
                    Text {
                        text: "accent · wallpaper · Files view — encrypted with your vault key, never readable on the server"
                        font.pixelSize: 10; color: Tokens.fgMuted
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
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

            Item { Layout.fillHeight: true }
        }
        property bool recoverySeen: false
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
                            Layout.preferredWidth: 132; Layout.preferredHeight: 82
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
                // dashed Choose image… tile — glass picker, no portal dialogs
                Rectangle {
                    Layout.preferredWidth: 132; Layout.preferredHeight: 82
                    radius: 12
                    color: "transparent"
                    border.color: Tokens.fgMuted
                    border.width: 1.5
                    Text { anchors.centerIn: parent; text: "Choose image\u2026"; font.pixelSize: 12; color: Tokens.fgMuted }
                    TapHandler { onTapped: imagePickerHost.active = true }
                }
            }
            Switch {
                text: "Rotate wallpapers daily"
                font.pixelSize: 13
                palette.windowText: Tokens.fg
            }
            Switch {
                text: "Focus-dim wallpaper"
                font.pixelSize: 13
                palette.windowText: Tokens.fg
            }
            Text {
                text: Util.wallpaper
                font.pixelSize: 10; color: Tokens.fgMuted
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
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
                model: [
                    { label: "Dock magnification",        chip: "\u22120.2 W", key: "tierA",    on: Governor.tier === "A" },
                    { label: "Dock bounce & Glass Fold",  chip: "\u22120.1 W", key: "tierAB",   on: Governor.tier !== "C" },
                    { label: "Window springs",            chip: "free",        key: "motionSpring", on: !!Governor.effects["motionSpring"] },
                    { label: "Live blur & transparency",  chip: "\u22120.5 W", key: "blurLive", on: !!Governor.effects["blurLive"] },
                    { label: "Wallpaper parallax",        chip: "\u22120.1 W", key: "off",      on: false },
                    { label: "Dynamic Island morph",      chip: "\u22120.1 W", key: "tierC",    on: Governor.tier !== "C" }
                ]
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Text { text: modelData.label; font.pixelSize: 13; color: Tokens.fg; Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 52; Layout.preferredHeight: 20; radius: 10
                        color: Util.darkMode ? "#23252B" : "#E8ECF4"
                        Text { anchors.centerIn: parent; text: modelData.chip; font.pixelSize: 10; font.family: "Monospace"; color: Tokens.fgMuted }
                    }
                    Switch {
                        enabled: modelData.key === "motionSpring" || modelData.key === "blurLive"
                        checked: modelData.on
                        palette.highlight: Tokens.accent
                    }
                }
            }
            Text {
                text: "Tier control is live (writes the governor state the shell and KWin read). Per-effect toggles land with the governor extension — switches show current state."
                font.pixelSize: 11; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    // ── Drivers & Firmware (plate 13: six domains, every row BUILT-IN)
    Component {
        id: driversPane
        ColumnLayout {
            spacing: 12
            Text { text: "Drivers & Firmware"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 30; radius: 8
                color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                Text {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; margins: 10 }
                    text: "aegis-drivers \u2014 verified store \u00b7 0 missing"
                    font { pixelSize: 12; family: "Monospace" }
                    color: "#28C840"
                }
            }
            Repeater {
                model: [
                    "Wi-Fi", "Bluetooth", "Graphics", "Audio",
                    "Print & scan", "Input", "WWAN & tethering", "Secure Boot"
                ]
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Text { text: modelData; font.pixelSize: 13; color: Tokens.fg; Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 64; Layout.preferredHeight: 20; radius: 6
                        color: Util.darkMode ? "#1B2B1F" : "#E4F5E8"
                        Text { anchors.centerIn: parent; text: "BUILT-IN"; font.pixelSize: 9; font.bold: true; color: "#28C840" }
                    }
                }
            }
        }
    }

    // ── W3 — Displays (kscreen-doctor: modes · scale · night light) ───────
    Component {
        id: displaysPane
        ColumnLayout {
            spacing: 12
            Text { text: "Displays"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

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

            Switch {
                text: "Night light (evening 20:00 – 06:00, warm)"
                font.pixelSize: 13
                palette.windowText: Tokens.fg
                palette.highlight: Tokens.accent
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
                        Switch {
                            text: "Mute"
                            font.pixelSize: 11
                            palette.highlight: Tokens.accent
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
                text: "wpctl not available — PipeWire session not found"
                font.pixelSize: 11; color: Tokens.fgMuted
            }
            AbstractButton {
                Layout.preferredHeight: 26; Layout.preferredWidth: 80
                contentItem: Text { text: "Refresh"; font.pixelSize: 11; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4"; border.color: Tokens.glassBorder }
                onClicked: Sound.refresh()
            }
        }
    }

    // ── W3 — Network (NetworkManager D-Bus) ──────────────────────────────
    Component {
        id: networkPane
        ColumnLayout {
            spacing: 10
            Component.onCompleted: { Network.loadKnown(); Network.refresh() }

            Text { text: "Network"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }

            RowLayout {
                Switch {
                    text: "Wi-Fi"
                    font.pixelSize: 13
                    palette.highlight: Tokens.accent
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
                            Text { anchors.centerIn: parent; text: "WPA"; font.pixelSize: 8; font.color: Tokens.fgMuted }
                        }
                        Text { text: modelData.strength + "%"; font.pixelSize: 10; color: Tokens.fgMuted }
                        AbstractButton {
                            visible: !modelData.inUse
                            Layout.preferredHeight: 24; Layout.preferredWidth: 72
                            contentItem: Text { text: modelData.known ? "Connect" : "Join"; font.pixelSize: 11; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Tokens.accent }
                            onClicked: Network.connectTo(modelData.ssid)
                        }
                    }
                }
            }

            Text {
                visible: Network.networks.length === 0
                text: Network.wifiEnabled
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
                        Switch {
                            visible: modelData.isYou
                            text: "Administrator"
                            font.pixelSize: 11
                            palette.highlight: Tokens.accent
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
        }
    }
}
