import QtQuick
import QtCore
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Aegis.Util
import Aegis.TextFile

// Aegis Editor — M3 first-party app (proposal §8, plate 12).
//
// The plain-text surface: 52 px toolbar (New · Open · Save · Save As ·
// wrap toggle), a frameless monospace page, 28 px status footer with path
// and counts. Files move through the TextFile backend (monitorbackend.h) —
// QML alone cannot write files, and the 4 MB cap in the backend keeps a
// stray binary from hanging the UI thread. Ctrl+N/O/S work like every
// desktop editor; the titlebar wears the dirty dot.
Window {
    id: win

    width: 760; height: 520
    minimumWidth: 460; minimumHeight: 340
    visible: true
    title: "Editor"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    property url docUrl: ""
    property bool dirty: false
    property bool wrap: true

    function docName() {
        const p = docUrl.toString()
        const base = p.slice(p.lastIndexOf("/") + 1)
        return base.length > 0 ? decodeURIComponent(base) : "Untitled"
    }

    function refreshTitle() {
        win.title = "Editor — " + (docUrl.toString() === "" ? "Untitled" : docName())
                   + (win.dirty ? " •" : "")
    }

    function openFile(fileUrl) {
        const r = TextFile.load(fileUrl)
        if (!r.ok) {
            page.text = ""
            statusFlash("Could not open — " + (r.error || "unknown error"))
            return
        }
        docUrl = fileUrl
        page.text = r.text
        dirty = false
        refreshTitle()
    }

    function saveTo(fileUrl) {
        const r = TextFile.save(fileUrl, page.text)
        if (!r.ok) {
            statusFlash("Could not save — " + (r.error || "unknown error"))
            return
        }
        docUrl = fileUrl
        dirty = false
        refreshTitle()
    }

    function save() {
        if (docUrl.toString() === "") saveDialog.open()
        else saveTo(docUrl)
    }

    function newDoc() {
        docUrl = ""
        page.text = ""
        dirty = false
        refreshTitle()
    }

    function statusFlash(message) {
        statusLine.text = message
        flashTimer.restart()
    }

    Timer {
        id: flashTimer
        interval: 4000
        onTriggered: statusLine.text = ""
    }

    AppWindow {
        id: appBody
        anchors.fill: parent
        title: win.title

        toolbar: [
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 62
                contentItem: Text {
                    text: "New"
                    font.pixelSize: 11
                    color: Tokens.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: win.newDoc()
            },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 70
                contentItem: Text {
                    text: "Open…"
                    font.pixelSize: 11
                    color: Tokens.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: openDialog.open()
            },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 64
                enabled: win.dirty || docUrl.toString() !== ""
                opacity: enabled ? 1 : 0.5
                contentItem: Text {
                    text: "Save"
                    font { pixelSize: 11; weight: Font.DemiBold }
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 8; color: Tokens.accent }
                onClicked: win.save()
            },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 86
                contentItem: Text {
                    text: "Save As…"
                    font.pixelSize: 11
                    color: Tokens.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: saveDialog.open()
            },
            Item { Layout.fillWidth: true },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 92
                contentItem: Text {
                    text: win.wrap ? "Wrap: on" : "Wrap: off"
                    font.pixelSize: 11
                    color: Tokens.fgMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: win.wrap ? Tokens.accent : Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: win.wrap = !win.wrap
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // the page
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollBar.horizontal.policy: win.wrap ? ScrollBar.AlwaysOff : ScrollBar.AlwaysOn

                TextArea {
                    id: page
                    wrapMode: win.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                    font { family: "Monospace"; pixelSize: 13 }
                    color: Tokens.fg
                    placeholderText: "Start typing — or open a file with Ctrl+O"
                    placeholderTextColor: Tokens.fgMuted
                    selectionColor: Tokens.accent
                    persistentSelection: false
                    topPadding: 16
                    leftPadding: 18
                    rightPadding: 18
                    bottomPadding: 12
                    background: Rectangle { color: "transparent" }
                    onTextChanged: {
                        win.dirty = true
                        win.refreshTitle()
                    }
                }
            }

            // 28 px status footer
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                color: Util.darkMode ? "#1B1D23" : "#EDF0F6"
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 8
                    Text {
                        text: docUrl.toString() === "" ? "Untitled" : TextFile.prettyPath(docUrl)
                        font.pixelSize: 10
                        color: Tokens.fgMuted
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 320
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        id: statusLine
                        font.pixelSize: 10
                        color: Tokens.danger
                    }
                    Text {
                        text: {
                            const t = page.text
                            const words = t.trim().length === 0 ? 0 : t.trim().split(/\s+/).length
                            return words + " words · " + t.length + " chars"
                        }
                        font.pixelSize: 10
                        color: Tokens.fgMuted
                    }
                }
                Rectangle {
                    height: 1
                    anchors { bottom: parent.top; left: parent.left; right: parent.right }
                    color: Tokens.glassBorder
                }
            }
        }

        // Ctrl+N / Ctrl+O / Ctrl+S
        Shortcut {
            sequence: StandardKey.New
            onActivated: win.newDoc()
        }
        Shortcut {
            sequence: StandardKey.Open
            onActivated: openDialog.open()
        }
        Shortcut {
            sequence: StandardKey.Save
            onActivated: win.save()
        }
    }

    FileDialog {
        id: openDialog
        title: "Open"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Text & code (*.txt *.md *.log *.conf *.ini *.json *.xml *.qml *.js *.py *.sh *.c *.cpp *.h)", "All files (*)"]
        currentFolder: docUrl.toString() === "" ? StandardPaths.writableLocation(StandardPaths.HomeLocation)
                                                : docUrl
        onAccepted: win.openFile(selectedFile)
    }

    FileDialog {
        id: saveDialog
        title: "Save as"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Plain text (*.txt)", "Markdown (*.md)", "All files (*)"]
        currentFolder: docUrl.toString() === "" ? StandardPaths.writableLocation(StandardPaths.HomeLocation)
                                                : docUrl
        onAccepted: win.saveTo(selectedFile)
    }
}
