import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Aegis.Util
import Aegis.Files

// Aegis Files — first-party file manager (proposal §8 + §8.1, plate 7).
//
// Structure = Ubuntu/Nautilus information architecture, glassed:
//   · 206 px sidebar — exactly seven places, glyphs tinted by location
//   · 52 px toolbar — back · breadcrumbs · view toggle · search · New Folder
//   · content — grid (folders first) or list, cards tinted by kind:
//     folders blue · PDFs red · archives amber · images purple
// Backend: FolderListModel + the Files singleton (filemanager.h). No KIO.
Window {
    id: win

    width: 960; height: 620
    minimumWidth: 520; minimumHeight: 360
    visible: true
    title: "Files"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    property bool gridMode: true
    property url current: Files.homeUrl()

    AppWindow {
        anchors.fill: parent
        title: "Files"
        accent: "#5B8BFF"

        toolbar: [
            // back — pop the history stack
            AbstractButton {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                contentItem: Text { text: "\u2039"; font.pixelSize: 20; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: { if (history.length > 1) { history.pop(); win.navigateTo(history[history.length - 1]) } }
            },
            // breadcrumbs — click any segment to jump there
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Repeater {
                    id: crumb
                    model: segments(win.current)
                    delegate: AbstractButton {
                        Layout.preferredHeight: 24
                        contentItem: Text { text: modelData; font.pixelSize: 12; color: index === crumb.model.length - 1 ? Tokens.fg : Tokens.fgMuted; verticalAlignment: Text.AlignVCenter }
                        onClicked: win.navigateTo(joinSegments(index))
                    }
                }
            },
            Item { Layout.fillWidth: true },
            // view toggle — grid / list
            AbstractButton {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                contentItem: Column {
                    spacing: 3; anchors.centerIn: parent
                    Repeater {
                        model: 3
                        Rectangle { width: win.gridMode ? 16 : 3; height: 3; radius: 1.5; color: Tokens.fgMuted; anchors.right: win.gridMode ? undefined : parent.right }
                    }
                }
                onClicked: win.gridMode = !win.gridMode
            },
            // search — filters the current folder
            TextField {
                Layout.preferredWidth: 160; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                placeholderText: "Search"
                font.pixelSize: 12
                color: Tokens.fg; placeholderTextColor: Tokens.fgMuted
                background: Rectangle { radius: 14; color: Util.darkMode ? "#23252B" : "#FFFFFF"; border.color: Tokens.glassBorder }
                onTextChanged: flm.nameFilters = text.length ? ["*" + text + "*"] : ["*"]
            },
            // New Folder
            AbstractButton {
                Layout.preferredWidth: 92; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                contentItem: Text { text: "New Folder"; font.pixelSize: 12; color: "#5B8BFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: Files.makeDir(flm.folder, "New Folder")
            }
        ]

        Row {
            anchors.fill: parent

            // 206 px sidebar — the seven Nautilus-structure places (§8.1 tints)
            Rectangle {
                width: 206; height: parent.height
                color: Util.darkMode ? "#141519" : "#EDEFF4"
                Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: Tokens.glassBorder }

                Column {
                    anchors { fill: parent; margins: 10 }
                    spacing: 2

                    Repeater {
                        model: [
                            { label: "Home",      icon: "user-home",       tint: "#3E8BFF" },
                            { label: "Documents", icon: "folder-documents", tint: "#4A9BFF" },
                            { label: "Downloads", icon: "folder-download", tint: "#28C840" },
                            { label: "Music",     icon: "folder-music",    tint: "#FA2D48" },
                            { label: "Pictures",  icon: "folder-pictures", tint: "#8B5CF6" },
                            { label: "Videos",    icon: "folder-videos",   tint: "#FF9F0A" },
                            { label: "Trash",     icon: "trash-can-empty", tint: "#8A909C" }
                        ]
                        delegate: AbstractButton {
                            width: parent.width; height: 34
                            property bool active: win.current === (modelData.label === "Trash" ? Files.trashUrl() : placeUrl(modelData.label))
                            background: Rectangle {
                                radius: 8
                                color: parent.active ? (Util.darkMode ? "#262930" : "#DDE3EE") : "transparent"
                            }
                            contentItem: Row {
                                spacing: 10
                                leftPadding: 10
                                Image {
                                    source: "image://icons/" + modelData.icon
                                    sourceSize: "18x18"; width: 18; height: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text { text: modelData.label; font.pixelSize: 13; color: Tokens.fg; anchors.verticalCenter: parent.verticalCenter }
                            }
                            onClicked: {
                                win.navigateTo(modelData.label === "Trash" ? Files.trashUrl() : placeUrl(modelData.label))
                            }
                        }
                    }
                    Item { height: 8 }
                    Text {
                        text: "Devices"
                        font { pixelSize: 11; bold: true }
                        color: Tokens.fgMuted
                        leftPadding: 10
                    }
                    Repeater {
                        model: [{ label: "Removable", icon: "drive-removable" }]
                        delegate: AbstractButton {
                            width: parent.width; height: 34
                            contentItem: Row {
                                spacing: 10; leftPadding: 10
                                Image { source: "image://icons/" + modelData.icon; sourceSize: "18x18"; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData.label; font.pixelSize: 13; color: Tokens.fg; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }

            // content — grid (folders first) / list, cards tinted by kind
            Item {
                height: parent.height
                width: parent.width - 206

                FolderListModel {
                    id: flm
                    folder: win.current
                    nameFilters: ["*"]
                    showDirsFirst: true
                }

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: win.gridMode
                    model: flm
                    cellWidth: 104; cellHeight: 104
                    clip: true

                    delegate: Item {
                        width: grid.cellWidth; height: grid.cellHeight
                        property color kindTint: fileIsDir ? "#5B8BFF" : kindColor(fileName)

                        Rectangle {
                            width: 84; height: 84; radius: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            color: Util.darkMode ? "#20222A" : "#FFFFFF"
                            border.color: gridMa.containsMouse ? "#5B8BFF" : Tokens.glassBorder
                            border.width: gridMa.containsMouse ? 2 : 1

                            Image {
                                anchors.centerIn: parent
                                source: fileIsDir ? "image://icons/folder" : "image://icons/" + iconFor(fileName)
                                sourceSize: "44x44"; width: 44; height: 44
                            }
                        }
                        Text {
                            anchors { top: parent.top; topMargin: 88; left: parent.left; right: parent.right }
                            text: fileName
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 11
                            color: Tokens.fg
                        }
                        TapHandler {
                            id: gridMa
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (eventPoint, button) => {
                                if (button === Qt.RightButton) { fileMenu.popup(); return }
                                if (fileIsDir) win.navigateTo(filePath)
                                else Util.launch("xdg-open \"" + filePath + "\"")
                            }
                        }
                        Menu {
                            id: fileMenu
                            MenuItem { text: "Rename…"; onTriggered: renameDialog.openFor(filePath) }
                            MenuItem { text: "Move to Trash"; onTriggered: Files.moveToTrash(fileURL) }
                        }
                    }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: !win.gridMode
                    model: flm
                    clip: true
                    spacing: 2

                    delegate: Rectangle {
                        width: list.width; height: 32; radius: 8
                        color: listMa.containsMouse ? (Util.darkMode ? "#262930" : "#E8ECF4") : "transparent"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 10; spacing: 10
                            Image { source: fileIsDir ? "image://icons/folder" : "image://icons/" + iconFor(fileName); sourceSize: "18x18"; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: fileName; font.pixelSize: 13; color: Tokens.fg; width: 300; elide: Text.ElideMiddle; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: fileIsDir ? "Folder" : kindLabel(fileName); font.pixelSize: 12; color: kindTintList(fileName, fileIsDir); anchors.verticalCenter: parent.verticalCenter }
                            Text { text: fileIsDir ? "" : (fileSize > 1048576 ? (fileSize / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(fileSize / 1024)) + " KB"); font.pixelSize: 12; color: Tokens.fgMuted; anchors.verticalCenter: parent.verticalCenter }
                        }
                        TapHandler {
                            id: listMa
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (eventPoint, button) => {
                                if (button === Qt.RightButton) { fileMenu2.popup(); return }
                                if (fileIsDir) win.navigateTo(filePath)
                                else Util.launch("xdg-open \"" + filePath + "\"")
                            }
                        }
                        Menu {
                            id: fileMenu2
                            MenuItem { text: "Rename…"; onTriggered: renameDialog.openFor(filePath) }
                            MenuItem { text: "Move to Trash"; onTriggered: Files.moveToTrash(fileURL) }
                        }
                    }
                }

                // rename dialog (F2-style)
                Rectangle {
                    id: renameDialog
                    anchors.centerIn: parent
                    width: 280; height: 120; radius: 18
                    color: Util.darkMode ? "#23252B" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    visible: false
                    z: 20
                    property url target

                    function openFor(p) { target = p; input.text = nameOf(p); visible = true; input.forceActiveFocus() }

                    Column {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10
                        Text { text: "Rename"; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                        TextField {
                            id: input
                            width: parent.width; font.pixelSize: 13
                            color: Tokens.fg
                            background: Rectangle { radius: 8; color: Util.darkMode ? "#17181D" : "#F4F6FA"; border.color: Tokens.glassBorder }
                            onAccepted: { Files.rename(renameDialog.target, input.text); renameDialog.visible = false }
                        }
                    }
                }
            }
        }
    }

    property var history: []
    Component.onCompleted: history = [Files.homeUrl()]

    // navigation — on the Window itself: every toolbar/delegate handler calls
    // win.navigateTo(...), so the function must live in win's scope.
    function navigateTo(p) {
        history.push(p)
        win.current = p
        flm.folder = p
        crumb.model = segments(p)
    }

    // helpers
    function placeUrl(label) {
        if (label === "Home") return Files.homeUrl()
        return Files.pathOf(Files.homeUrl()) + "/" + label
    }
    function segments(p) {
        const s = Files.pathOf(p).split("/").filter(Boolean)
        return ["Home"].concat(s.slice(2))
    }
    function joinSegments(n) {
        const home = Files.pathOf(Files.homeUrl())
        const s = segments(win.current).slice(1, n + 1)
        return "file://" + home + (s.length ? "/" + s.join("/") : "")
    }
    function nameOf(p) { return Files.pathOf(p).split("/").filter(Boolean).pop() }
    function kindColor(n) {
        const s = n.toLowerCase()
        if (s.endsWith(".pdf")) return "#FA2D48"                       // PDFs — red
        if (/(zip|tar|gz|7z|xz|bz2|rar)$/.test(s)) return "#FF9F0A"    // archives — amber
        if (/(png|jpg|jpeg|webp|gif|svg|bmp)$/.test(s)) return "#8B5CF6" // images — purple
        if (/(mp3|flac|ogg|wav)$/.test(s)) return "#FF6B84"            // audio
        if (/(mp4|mkv|mov|webm)$/.test(s)) return "#FFB84D"            // video
        return "#8A909C"
    }
    function kindTintList(n, isDir) { return isDir ? "#5B8BFF" : kindColor(n) }
    function kindLabel(n) {
        const s = n.toLowerCase()
        if (s.endsWith(".pdf")) return "PDF"
        if (/(zip|tar|gz|7z|xz|bz2|rar)$/.test(s)) return "Archive"
        if (/(png|jpg|jpeg|webp|gif|svg|bmp)$/.test(s)) return "Image"
        if (/(mp3|flac|ogg|wav)$/.test(s)) return "Audio"
        if (/(mp4|mkv|mov|webm)$/.test(s)) return "Video"
        return "File"
    }
    function iconFor(n) {
        const s = n.toLowerCase()
        if (s.endsWith(".pdf")) return "folder-documents"
        if (/(png|jpg|jpeg|webp|gif|svg|bmp)$/.test(s)) return "folder-pictures"
        if (/(mp3|flac|ogg|wav)$/.test(s)) return "folder-music"
        if (/(mp4|mkv|mov|webm)$/.test(s)) return "folder-videos"
        return "folder"
    }
}
