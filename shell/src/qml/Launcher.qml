import QtQuick
import QtQuick.Controls
import Aegis.Util

// Launcher — the full-screen glass sheet (proposal chapter 07, Plate 4 +
// Table 17). Blurs the live desktop 40 px behind a 48% scrim (the KWin
// blur is forced on every aegis-shell surface via kwinrulesrc), so the
// wallpaper remains perceptible — continuity, not a mode change.
//
// An 8 × 3 grid of 62 px glass tiles with 30 px icons; typing filters
// instantly; Enter launches the first match; Esc or click-away dismisses.
// Page dots sit above the dock, which stays interactive. First paint
// target: one frame — the grid is built when the shell loads, not on
// open (the surface is instantiated hidden).
//
// Entry/exit: standard 180 ms in, instant out on Esc (Table 9).
Window {
    // KWin's alt+F4 must never destroy a shell surface: with no app window
    // focused, the focused layer surface receives the close and would die
    // (dock -> island -> panel cascade, observed on the v0.6.5 boot test).
    onClosing: (close) => { close.accepted = false }
    objectName: "launcherWindow"
    id: launcherRoot
    visible: Util.launcherOpen
    color: "transparent"
    width: 1920
    height: 1080
    flags: Qt.FramelessWindowHint

    property var apps: []
    property string query: ""
    readonly property var filtered: {
        const q = query.toLowerCase()
        if (!q)
            return apps
        return apps.filter(function (a) {
            return a.name.toLowerCase().indexOf(q) >= 0
        })
    }
    readonly property int perPage: 24
    readonly property int pageCount: Math.max(1, Math.ceil(filtered.length / perPage))
    property int page: 0
    readonly property var pageSlice: {
        const start = page * perPage
        return filtered.slice(start, start + perPage)
    }

    onVisibleChanged: {
        if (visible) {
            apps = Util.allApps()
            query = ""
            page = 0
            sheet.opacity = 0
            gridContent.scale = 0.98
            openAnim.restart()
            searchField.forceActiveFocus()
        } else {
            searchField.focus = false
        }
    }

    // click-away dismissal (the shared grammar: Esc, click-away, key again)
    MouseArea {
        anchors.fill: parent
        onClicked: Util.launcherOpen = false
    }

    // 48% ink scrim over the blurred desktop (Table 6: Sheet Glass)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(8/255, 9/255, 12/255, 0.48)
    }

    Item {
        id: gridContent
        anchors.fill: parent

        SequentialAnimation {
            id: openAnim

            ParallelAnimation {
                NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: Tokens.durStandard; easing.type: Easing.OutCubic }
                NumberAnimation { target: gridContent; property: "scale"; from: 0.98; to: 1; duration: Tokens.durStandard; easing.type: Easing.OutCubic }
            }
        }

        // ── search pill ──────────────────────────────────────────────
        Rectangle {
            id: sheet
            width: 320
            height: 40
            radius: 20
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 96
            color: Util.darkMode ? Qt.rgba(16/255, 16/255, 18/255, 0.55)
                                 : Qt.rgba(244/255, 246/255, 250/255, 0.55)
            border.width: 1
            border.color: Util.darkMode ? Tokens.glassBorder : Tokens.glassBorderLight

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                verticalAlignment: TextInput.AlignVCenter
                color: Tokens.fg
                font { family: "Montserrat"; pixelSize: 13 }
                clip: true
                onTextChanged: {
                    launcherRoot.query = text
                    launcherRoot.page = 0
                }

                Keys.onEscapePressed: Util.launcherOpen = false
                Keys.onReturnPressed: launcherRoot.launchFirst()
                Keys.onEnterPressed: launcherRoot.launchFirst()
                Keys.onDownPressed: launcherRoot.page = Math.min(launcherRoot.page + 1, launcherRoot.pageCount - 1)
                Keys.onUpPressed: launcherRoot.page = Math.max(0, launcherRoot.page - 1)

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchField.text === ""
                    text: "Search apps"
                    color: Tokens.fgMuted
                    font { family: "Montserrat"; pixelSize: 13 }
                }
            }
        }

        // ── 8 × 3 app grid ───────────────────────────────────────────
        Grid {
            columns: 8
            columnSpacing: 18
            rowSpacing: 26
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -30

            Repeater {
                model: launcherRoot.pageSlice

                delegate: Item {
                    required property var modelData
                    width: 96
                    height: 104

                    Rectangle {
                        id: tile
                        width: 62
                        height: 62
                        radius: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        color: tileMa.containsMouse
                               ? (Util.darkMode ? Qt.rgba(1, 1, 1, 0.16)
                                                : Qt.rgba(1, 1, 1, 0.5))
                               : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.07)
                                                : Qt.rgba(0, 0, 0, 0.04))
                        border.width: 1
                        border.color: Util.darkMode ? Tokens.glassBorder
                                                    : Tokens.glassBorderLight
                        scale: tileMa.containsMouse ? 1.08 : 1.0
                        Behavior on scale {
                            NumberAnimation { duration: Tokens.durQuick; easing.type: Easing.OutCubic }
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            source: modelData.icon
                                    ? "image://icons/" + modelData.icon
                                    : "aegis-mark.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcherRoot.launch(modelData.cmd)
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.name
                        color: launcherRoot.query !== "" ? Tokens.accent : Tokens.fg
                        font { family: "Montserrat"; pixelSize: 11 }
                    }
                }
            }
        }

        // empty state — honest, quiet
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            visible: launcherRoot.filtered.length === 0
            text: "No apps match \u201C" + launcherRoot.query + "\u201D"
            color: Tokens.fgMuted
            font { family: "Montserrat"; pixelSize: 13 }
        }

        // ── page dots, above the dock ────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 150
            spacing: 8
            visible: launcherRoot.pageCount > 1

            Repeater {
                model: launcherRoot.pageCount

                delegate: Rectangle {
                    required property int index
                    width: 6
                    height: 6
                    radius: 3
                    color: index === launcherRoot.page
                           ? Tokens.accent
                           : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.3)
                                            : Qt.rgba(0, 0, 0, 0.25))
                    Behavior on color { ColorAnimation { duration: Tokens.durQuick } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: launcherRoot.page = index
                    }
                }
            }
        }
    }

    // wheel pages
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function (wheel) {
            if (wheel.angleDelta.y < 0)
                launcherRoot.page = Math.min(launcherRoot.page + 1, launcherRoot.pageCount - 1)
            else if (wheel.angleDelta.y > 0)
                launcherRoot.page = Math.max(0, launcherRoot.page - 1)
        }
    }

    function launch(cmd) {
        Util.launch(cmd)
        Util.launcherOpen = false
    }

    function launchFirst() {
        if (filtered.length > 0)
            launch(filtered[0].cmd)
    }
}
