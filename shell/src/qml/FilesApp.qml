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
//   · 52 px toolbar — back · breadcrumbs · sort · view · search · New Folder
//   · content — grid (folders first) or list, cards tinted by kind
//     (Folders blue · PDFs red · archives amber · images purple · audio pink
//      — tints picked by QMimeDatabase sniffing in filemanager.h, §8.1)
//   · 28 px status footer — "N items · 2 hidden · filtered"
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
    property bool showHidden: false
    property string sortKey: "name"    // name · date · kind · size
    property bool sortReversed: false
    property int hiddenCount: 0
    // cut/copy clipboard selection (paths), held by the Files singleton
    property var clipSelection: []

    function applyPrefs(json) {
        const p = JSON.parse(json || "{}")
        if (typeof p.gridMode === "boolean") win.gridMode = p.gridMode
        if (typeof p.sortKey === "string") win.sortKey = p.sortKey
        if (typeof p.sortReversed === "boolean") win.sortReversed = p.sortReversed
        if (typeof p.showHidden === "boolean") win.showHidden = p.showHidden
    }
    function savePrefs() {
        Files.saveViewPrefs(JSON.stringify({
            gridMode: win.gridMode,
            sortKey: win.sortKey,
            sortReversed: win.sortReversed,
            showHidden: win.showHidden
        }))
    }

    Component.onCompleted: {
        applyPrefs(Files.loadViewPrefs())
        history = [Files.homeUrl()]
    }
    // files.prefs synced by Aegis ID on another device — re-apply live
    Connections {
        target: Files
        function onViewPrefsChanged() { applyPrefs(Files.loadViewPrefs()) }
    }

    AppWindow {
        anchors.fill: parent
        title: "Files"
        accent: Tokens.accent

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
            // sort — name / date / kind / size + descending + show hidden
            AbstractButton {
                id: sortButton
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                contentItem: Column {
                    spacing: 2; anchors.centerIn: parent
                    Text { text: "\u2195"; font.pixelSize: 13; color: Tokens.fgMuted; horizontalAlignment: Text.AlignHCenter; width: 28 }
                    Text { text: "A\u2193"; font.pixelSize: 9; color: Tokens.fgMuted; horizontalAlignment: Text.AlignHCenter; width: 28 }
                }
                onClicked: sortMenu.popup(sortButton, 0, sortButton.height + 2)
                Menu {
                    id: sortMenu
                    dim: false
                    MenuItem {
                        text: "Name"
                        checkable: true
                        checked: win.sortKey === "name"
                        onTriggered: { win.sortKey = "name"; win.savePrefs() }
                    }
                    MenuItem {
                        text: "Date"
                        checkable: true
                        checked: win.sortKey === "date"
                        onTriggered: { win.sortKey = "date"; win.savePrefs() }
                    }
                    MenuItem {
                        text: "Kind"
                        checkable: true
                        checked: win.sortKey === "kind"
                        onTriggered: { win.sortKey = "kind"; win.savePrefs() }
                    }
                    MenuItem {
                        text: "Size"
                        checkable: true
                        checked: win.sortKey === "size"
                        onTriggered: { win.sortKey = "size"; win.savePrefs() }
                    }
                    MenuSeparator {}
                    MenuItem {
                        text: "Descending"
                        checkable: true
                        checked: win.sortReversed
                        onTriggered: { win.sortReversed = !win.sortReversed; win.savePrefs() }
                    }
                    MenuItem {
                        text: "Show hidden files"
                        checkable: true
                        checked: win.showHidden
                        onTriggered: { win.showHidden = !win.showHidden; win.savePrefs() }
                    }
                }
            },
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
                onClicked: { win.gridMode = !win.gridMode; win.savePrefs() }
            },
            // search — filters the current folder
            TextField {
                id: search
                Layout.preferredWidth: 160; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                placeholderText: "Search"
                font.pixelSize: 12
                color: Tokens.fg; placeholderTextColor: Tokens.fgMuted
                background: Rectangle { radius: 14; color: Util.darkMode ? "#23252B" : "#FFFFFF"; border.color: Tokens.glassBorder }
            },
            // New Folder
            AbstractButton {
                Layout.preferredWidth: 92; Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                contentItem: Text { text: "New Folder"; font.pixelSize: 12; color: Tokens.accent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
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
                    nameFilters: search.text.length ? ["*" + search.text + "*"] : ["*"]
                    showDirsFirst: true
                    showDotAndHidden: win.showHidden
                    sortField: win.sortKey === "date" ? FolderListModel.Date
                             : win.sortKey === "size" ? FolderListModel.Size
                             : win.sortKey === "kind" ? FolderListModel.Type
                             : FolderListModel.Name
                    sortReversed: win.sortReversed
                    onFolderChanged: win.hiddenCount = Files.hiddenCount(win.current)
                }

                // background paste — right-click on the file area
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: pasteMenu.popup()
                }
                Menu {
                    id: pasteMenu
                    MenuItem {
                        text: "Paste"
                        enabled: Files.hasClipboard()
                        onTriggered: win.doPaste()
                    }
                    MenuItem {
                        text: "New Folder"
                        onTriggered: Files.makeDir(flm.folder, "New Folder")
                    }
                }

                // W2 — empty-Home quick tiles (plate 7): four cards instead
                // of blank space, straight back into the places rail
                Row {
                    anchors.centerIn: parent
                    spacing: 14
                    visible: flm.count === 0 && search.text.length === 0

                    Repeater {
                        model: [
                            { label: "Home",      icon: "user-home",        to: "home" },
                            { label: "Documents", icon: "folder-documents", to: "place:Documents" },
                            { label: "Downloads", icon: "folder-download",  to: "place:Downloads" },
                            { label: "Apps",      icon: "folder",           to: "file:///usr/share/applications" }
                        ]
                        delegate: Item {
                            id: emptyTile
                            width: 84; height: 104
                            Rectangle {
                                width: 84; height: 84; radius: 18
                                color: Util.darkMode ? "#20222A" : "#FFFFFF"
                                border.color: emptyMa.containsMouse ? Tokens.accent : Tokens.glassBorder
                                border.width: emptyMa.containsMouse ? 2 : 1
                                Image {
                                    anchors.centerIn: parent
                                    source: "image://icons/" + modelData.icon
                                    sourceSize: "44x44"; width: 44; height: 44
                                    opacity: 0.8
                                }
                                TapHandler {
                                    id: emptyMa
                                    onTapped: {
                                        if (modelData.to === "home")
                                            win.navigateTo(Files.homeUrl())
                                        else if (modelData.to.toString().startsWith("place:"))
                                            win.navigateTo(placeUrl(modelData.to.toString().slice(6)))
                                        else
                                            win.navigateTo(modelData.to)
                                    }
                                }
                            }
                            Text {
                                anchors { top: parent.top; topMargin: 88; left: parent.left; right: parent.right }
                                text: modelData.label
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 11
                                color: Tokens.fgMuted
                            }
                        }
                    }
                }

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.bottomMargin: 42
                    visible: win.gridMode
                    model: flm
                    cellWidth: 104; cellHeight: 104
                    clip: true

                    delegate: Item {
                        id: gridCard
                        width: grid.cellWidth; height: grid.cellHeight
                        // §8.1 — one sniffed call per card; the tint drives
                        // the hover hairline (folders blue, PDFs red, …)
                        property var meta: Files.fileMeta(filePath)

                        Rectangle {
                            width: 84; height: 84; radius: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            color: Util.darkMode ? "#20222A" : "#FFFFFF"
                            border.color: gridMa.containsMouse ? gridCard.meta.tint : Tokens.glassBorder
                            border.width: gridMa.containsMouse ? 2 : 1

                            Image {
                                anchors.centerIn: parent
                                source: "image://icons/" + gridCard.meta.icon
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
                            MenuItem { text: "Cut"; onTriggered: { win.clipSelection = [filePath]; Files.cutPaths([filePath]) } }
                            MenuItem { text: "Copy"; onTriggered: { win.clipSelection = [filePath]; Files.copyPaths([filePath]) } }
                            MenuItem { text: "Open With\u2026"; onTriggered: openWithSheet.openFor(filePath) }
                            MenuItem { text: "Rename\u2026"; onTriggered: renameDialog.openFor(filePath) }
                            MenuItem { text: "Move to Trash"; onTriggered: Files.moveToTrash(fileURL) }
                            MenuItem { text: "Properties"; onTriggered: propsSheet.openFor(filePath) }
                        }
                    }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.bottomMargin: 42
                    visible: !win.gridMode
                    model: flm
                    clip: true
                    spacing: 2

                    delegate: Rectangle {
                        id: listRow
                        width: list.width; height: 32; radius: 8
                        property var meta: Files.fileMeta(filePath)
                        color: listMa.containsMouse ? (Util.darkMode ? "#262930" : "#E8ECF4") : "transparent"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 10; spacing: 10
                            Image { source: "image://icons/" + listRow.meta.icon; sourceSize: "18x18"; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: fileName; font.pixelSize: 13; color: Tokens.fg; width: 300; elide: Text.ElideMiddle; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: listRow.meta.label; font.pixelSize: 12; color: listRow.meta.tint; anchors.verticalCenter: parent.verticalCenter }
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
                            MenuItem { text: "Cut"; onTriggered: { win.clipSelection = [filePath]; Files.cutPaths([filePath]) } }
                            MenuItem { text: "Copy"; onTriggered: { win.clipSelection = [filePath]; Files.copyPaths([filePath]) } }
                            MenuItem { text: "Open With\u2026"; onTriggered: openWithSheet.openFor(filePath) }
                            MenuItem { text: "Rename\u2026"; onTriggered: renameDialog.openFor(filePath) }
                            MenuItem { text: "Move to Trash"; onTriggered: Files.moveToTrash(fileURL) }
                            MenuItem { text: "Properties"; onTriggered: propsSheet.openFor(filePath) }
                        }
                    }
                }

                // ── W1 — 28 px status footer ─────────────────────────────
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 28
                    color: Util.darkMode ? "#1B1D23" : "#E6EAF2"
                    Rectangle { width: parent.width; height: 1; color: Tokens.glassBorder }
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                        font.pixelSize: 11
                        color: Tokens.fgMuted
                        text: {
                            let t = flm.count + (flm.count === 1 ? " item" : " items")
                            if (!win.showHidden && win.hiddenCount > 0)
                                t += " \u00b7 " + win.hiddenCount + " hidden"
                            if (search.text.length > 0)
                                t += " \u00b7 filtered"
                            return t
                        }
                    }
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 12 }
                        font.pixelSize: 11
                        color: Tokens.fgMuted
                        text: win.clipSelection.length > 0
                              ? (win.clipSelection.length + " on clipboard") : ""
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

                // ── W1 — paste overwrite prompt (existing dialog pattern) ─
                Rectangle {
                    id: overwriteDialog
                    anchors.centerIn: parent
                    width: 300; height: 128; radius: 18
                    color: Util.darkMode ? "#23252B" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    visible: false
                    z: 21
                    property var conflicts: []

                    Column {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10
                        Text { text: "Replace items?"; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                        Text {
                            width: parent.width
                            font.pixelSize: 12; color: Tokens.fgMuted
                            wrapMode: Text.WordWrap
                            text: overwriteDialog.conflicts.length
                                  + " item(s) already exist here."
                        }
                        RowLayout {
                            width: parent.width
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            AbstractButton {
                                Layout.preferredHeight: 28; Layout.preferredWidth: 64
                                contentItem: Text { text: "Cancel"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4" }
                                onClicked: overwriteDialog.visible = false
                            }
                            AbstractButton {
                                Layout.preferredHeight: 28; Layout.preferredWidth: 88
                                contentItem: Text { text: "Replace all"; font.pixelSize: 12; color: "#FFFFFF"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 8; color: Tokens.accent }
                                onClicked: {
                                    Files.paste(flm.folder, true)
                                    overwriteDialog.visible = false
                                }
                            }
                        }
                    }
                }

                // ── W1 — properties sheet ────────────────────────────────
                Rectangle {
                    id: propsSheet
                    anchors.centerIn: parent
                    width: 320; height: 200; radius: 18
                    color: Util.darkMode ? "#23252B" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    visible: false
                    z: 20
                    property var info: ({})

                    function openFor(p) {
                        info = Files.propertiesOf(p)
                        visible = true
                    }

                    Column {
                        anchors { fill: parent; margins: 14 }
                        spacing: 8
                        Text { text: propsSheet.info.name || ""; font.pixelSize: 13; font.bold: true; color: Tokens.fg; elide: Text.ElideMiddle; width: parent.width }
                        Grid {
                            columns: 2
                            width: parent.width
                            columnSpacing: 14; rowSpacing: 6
                            Text { text: "Kind"; font.pixelSize: 12; color: Tokens.fgMuted }
                            Text { text: propsSheet.info.label || ""; font.pixelSize: 12; color: propsSheet.info.tint || Tokens.fg }
                            Text { text: "Size"; font.pixelSize: 12; color: Tokens.fgMuted }
                            Text { text: propsSheet.info.size || ""; font.pixelSize: 12; color: Tokens.fg }
                            Text { text: "Modified"; font.pixelSize: 12; color: Tokens.fgMuted }
                            Text { text: propsSheet.info.modified || ""; font.pixelSize: 12; color: Tokens.fg }
                            Text { text: "Path"; font.pixelSize: 12; color: Tokens.fgMuted }
                            Text { text: propsSheet.info.path || ""; font.pixelSize: 12; color: Tokens.fg; elide: Text.ElideMiddle; width: 180 }
                        }
                        Item { height: 6 }
                        AbstractButton {
                            height: 28; width: 70
                            contentItem: Text { text: "Close"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4" }
                            onClicked: propsSheet.visible = false
                        }
                    }
                }

                // ── W1 — Open With (MIME-matched .desktop entries) ───────
                Rectangle {
                    id: openWithSheet
                    anchors.centerIn: parent
                    width: 320; height: 240; radius: 18
                    color: Util.darkMode ? "#23252B" : "#FFFFFF"
                    border.color: Tokens.glassBorder
                    visible: false
                    z: 20
                    property url target
                    property var choices: []

                    function openFor(p) {
                        target = p
                        choices = Files.openWithChoices(Files.pathOf(p))
                        visible = true
                    }

                    Column {
                        anchors { fill: parent; margins: 14 }
                        spacing: 8
                        Text { text: "Open With"; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                        Text {
                            text: nameOf(openWithSheet.target) || ""
                            font.pixelSize: 11; color: Tokens.fgMuted
                            elide: Text.ElideMiddle; width: parent.width
                        }
                        ListView {
                            width: parent.width; height: 130
                            clip: true
                            spacing: 4
                            model: openWithSheet.choices
                            delegate: AbstractButton {
                                width: openWithSheet.width - 28; height: 34
                                background: Rectangle {
                                    radius: 8
                                    color: owMa.containsMouse ? (Util.darkMode ? "#262930" : "#E8ECF4") : "transparent"
                                    border.color: Tokens.glassBorder
                                }
                                contentItem: Row {
                                    spacing: 10
                                    leftPadding: 8
                                    Image { source: "image://icons/" + (modelData.icon || "application-x-executable"); sourceSize: "18x18"; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: modelData.name; font.pixelSize: 12; color: Tokens.fg; anchors.verticalCenter: parent.verticalCenter }
                                }
                                TapHandler {
                                    id: owMa
                                    onTapped: {
                                        Files.launchWith(modelData.exec, Files.pathOf(openWithSheet.target))
                                        openWithSheet.visible = false
                                    }
                                }
                            }
                        }
                        Text {
                            visible: openWithSheet.choices.length === 0
                            text: "No matching applications"
                            font.pixelSize: 12; color: Tokens.fgMuted
                        }
                        AbstractButton {
                            height: 28; width: 70
                            contentItem: Text { text: "Close"; font.pixelSize: 12; color: Tokens.fg; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 8; color: Util.darkMode ? "#262930" : "#E8ECF4" }
                            onClicked: openWithSheet.visible = false
                        }
                    }
                }
            }
        }
    }

    property var history: []

    // navigation — on the Window itself: every toolbar/delegate handler calls
    // win.navigateTo(...), so the function must live in win's scope.
    function navigateTo(p) {
        history.push(p)
        win.current = p
        flm.folder = p
        crumb.model = segments(p)
    }

    // W1 — paste with the overwrite prompt; conflicts first, replace second
    function doPaste() {
        const conflicts = Files.paste(flm.folder, false)
        if (conflicts.length > 0) {
            overwriteDialog.conflicts = conflicts
            overwriteDialog.visible = true
        }
        win.clipSelection = []
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
}
