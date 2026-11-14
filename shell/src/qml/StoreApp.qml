import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aegis.Util
import Aegis.Store

// Aegis Store — T14, the apt-backed app store (the user ruling: "an
// appstore with all the famous ubuntu and debian etc apps"). One curated
// catalog of the famous archive packages, dpkg-query for the installed
// state, sudo -n apt-get for install/remove (NOPASSWD via 0610).
//
// T15-D3 (W38) — the window rides the AppWindow anatomy now (the bare
// Window + hand-rolled 44 px band had NO traffic lights — the user's
// "app store do not have traffic lights so it is not closing" — no drag,
// no resize, and the body painted outside the rounded frame). Same
// anatomy as Settings/Files: 44 px titlebar + lights + DragHandler + 8
// resize zones + clipped rounded body. The search field moved into the
// 52 px toolbar; the cards carry REAL theme icons through the
// image://icons provider (Store.hasIcon ladder, letter tile as the last
// resort) instead of letter tiles alone.
Window {
    id: storeRoot

    width: 1120
    height: 720
    minimumWidth: 680
    minimumHeight: 440
    visible: true
    title: "Store"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    // ── categories ────────────────────────────────────────────────
    readonly property var categories: [
        { label: "All", tint: "#3E8BFF" },
        { label: "Graphics", tint: "#8B5CF6" },
        { label: "Multimedia", tint: "#FF6B84" },
        { label: "Office", tint: "#3E8BFF" },
        { label: "Internet", tint: "#4AC8C8" },
        { label: "Utilities", tint: "#FFB84D" },
        { label: "Development", tint: "#28C840" }
    ]
    property string activeCategory: "All"
    property string query: ""

    function tintFor(category) {
        var t = "#3E8BFF"
        for (var i = 0; i < categories.length; ++i)
            if (categories[i].label === category)
                t = categories[i].tint
        return t
    }

    function visibleEntries() {
        var out = []
        var cat = Store.catalog
        for (var i = 0; i < cat.length; ++i) {
            var e = cat[i]
            if (activeCategory !== "All" && e.category !== activeCategory)
                continue
            if (query.length > 0
                && e.name.toLowerCase().indexOf(query.toLowerCase()) < 0)
                continue
            out.push(e)
        }
        return out
    }

    AppWindow {
        anchors.fill: parent
        title: "Store"

        toolbar: [
            // W38 — search lives in the 52 px toolbar now (it used to be
            // the first sidebar row; the sidebar holds categories + the
            // live-session notice)
            TextField {
                id: searchField
                Layout.preferredWidth: 300
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                placeholderText: "Search apps"
                font { family: "Montserrat"; pixelSize: 12 }
                color: Tokens.fg
                placeholderTextColor: Tokens.fgMuted
                selectByMouse: true
                background: Rectangle {
                    radius: 16
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                    border.color: searchField.activeFocus ? Tokens.accent : Tokens.glassBorder
                }
                onTextChanged: storeRoot.query = text
            },
            Item { Layout.fillWidth: true },
            // installing pill — mirrors the sidebar status line
            Rectangle {
                visible: Store.installingId.length > 0
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                width: installingText.width + 20
                radius: 13
                color: Tokens.glassBorder
                Text {
                    id: installingText
                    anchors.centerIn: parent
                    text: Store.installingId.length > 0
                          ? "Installing " + Store.installingId + "…"
                          : ""
                    font.pixelSize: 11
                    color: Tokens.fg
                }
            }
        ]

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── sidebar: categories + live-session notice ─────────
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 216
                color: Util.darkMode ? "#141519" : "#EDEFF4"
                Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: Tokens.glassBorder }

                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 8

                    Repeater {
                        model: storeRoot.categories
                        delegate: AbstractButton {
                            id: catBtn
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            property bool active: storeRoot.activeCategory === modelData.label
                            background: Rectangle {
                                radius: 10
                                color: catBtn.active ? (Util.darkMode ? "#262930" : "#DDE3EE")
                                                     : "transparent"
                            }
                            contentItem: Row {
                                spacing: 10
                                leftPadding: 10
                                Rectangle {
                                    width: 12; height: 12; radius: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.tint
                                }
                                Text {
                                    text: modelData.label
                                    font.pixelSize: 13
                                    color: catBtn.active ? Tokens.fg : Tokens.fgMuted
                                    font.weight: catBtn.active ? Font.DemiBold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            onClicked: storeRoot.activeCategory = modelData.label
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // T15-D9 (W46) — live-session honesty card. Every
                    // install in a live session lands in the overlay and
                    // is lost on reboot; the Store owns that sentence (the
                    // predicate is the same one the installer uses) and
                    // hands the user to aegis-live-installer.
                    Rectangle {
                        visible: Store.liveSession
                        Layout.fillWidth: true
                        // Layout.preferredHeight, NOT a `height:` binding —
                        // the parent ColumnLayout overwrites children's
                        // height (destroying the binding), so the card
                        // froze at its pre-wrap height and the caption
                        // below painted over the Run-installer button
                        // (user-reported on v0.6.60). implicitHeight
                        // tracks the wrapped text as the width settles.
                        Layout.preferredHeight: noticeColumn.implicitHeight + 20
                        radius: 12
                        color: Util.darkMode ? Qt.rgba(1, 0.72, 0.30, 0.10)
                                             : Qt.rgba(1, 0.72, 0.30, 0.16)
                        border.color: Util.darkMode ? "#B7791F" : "#D69E2E"
                        ColumnLayout {
                            id: noticeColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: "Live session"
                                font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
                                color: Tokens.fg
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Apps install to the overlay and are lost on reboot. Run the Aegis installer to keep them."
                                font.pixelSize: 11
                                color: Tokens.fgMuted
                                wrapMode: Text.WordWrap
                            }
                            AbstractButton {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: 132
                                background: Rectangle {
                                    radius: 14
                                    color: Tokens.accent
                                }
                                contentItem: Text {
                                    text: "Run installer"
                                    font { family: "Montserrat"; pixelSize: 11; weight: Font.DemiBold }
                                    color: "#FFFFFF"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: Store.openInstaller()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        text: "apt-backed · Ubuntu + Debian archive"
                        font.pixelSize: 10
                        color: Tokens.fgMuted
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ── main pane: the catalog cards ──────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.topMargin: 12
                    text: storeRoot.activeCategory
                    font { family: "Montserrat"; pixelSize: 15; weight: Font.DemiBold }
                    color: Tokens.fg
                }

                ListView {
                    id: cardList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 12
                    spacing: 10
                    clip: true
                    model: storeRoot.visibleEntries()

                    delegate: Rectangle {
                        width: cardList.width
                        height: 74
                        radius: 14
                        color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#FFFFFF"
                        border.color: Tokens.glassBorder

                        RowLayout {
                            anchors { fill: parent; margins: 12 }
                            spacing: 14

                            // W38 — the icon ladder: theme icon through
                            // the image://icons provider when the theme
                            // really carries it (installed apps, and any
                            // entry whose icon ships in the Aegis theme),
                            // letter tile in the category tint otherwise.
                            Rectangle {
                                width: 50; height: 50; radius: 14
                                color: storeRoot.tintFor(modelData.category)
                                Image {
                                    anchors.centerIn: parent
                                    width: 34; height: 34
                                    visible: Store.hasIcon(modelData.pkgs[0])
                                    source: visible
                                            ? "image://icons/" + modelData.pkgs[0]
                                            : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !Store.hasIcon(modelData.pkgs[0])
                                    text: modelData.name.substring(0, 1)
                                    font { family: "Montserrat"; pixelSize: 22; weight: Font.DemiBold }
                                    color: "#FFFFFF"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    text: modelData.name
                                    font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                                    color: Tokens.fg
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.description
                                    font.pixelSize: 11
                                    color: Tokens.fgMuted
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.category + " · " + modelData.pkgs.join(" ")
                                    font.pixelSize: 10
                                    color: Tokens.fgMuted
                                    opacity: 0.7
                                }
                            }

                            Rectangle {
                                id: actionBtn
                                width: 104; height: 34; radius: 17
                                Layout.alignment: Qt.AlignVCenter
                                readonly property bool busy:
                                    Store.installingId === modelData.id
                                readonly property bool installed:
                                    modelData.installed === true
                                color: busy ? Tokens.glassBorder
                                     : installed ? (Util.darkMode ? "#262930" : "#DDE3EE")
                                     : Tokens.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: actionBtn.busy ? "Working…"
                                         : actionBtn.installed ? "Installed"
                                         : "Install"
                                    font { family: "Montserrat"; pixelSize: 11; weight: Font.DemiBold }
                                    color: actionBtn.installed && !actionBtn.busy
                                           ? Tokens.fgMuted : "#FFFFFF"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !actionBtn.busy
                                    onClicked: {
                                        if (actionBtn.installed)
                                            Store.remove(modelData.id)
                                        else
                                            Store.install(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        visible: Store.installingId.length > 0
                                 && cardList.count === 0
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cardList.count === 0
                                 && Store.installingId.length === 0
                        text: "Nothing in this category"
                        color: Tokens.fgMuted
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    color: Util.darkMode ? "#141519" : "#EDEFF4"
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: Store.lastMessage.length > 0
                              ? Store.lastMessage
                              : cardList.count + " apps · " + storeRoot.activeCategory
                        font.pixelSize: 10
                        color: Tokens.fgMuted
                        elide: Text.ElideRight
                        width: parent.width - 28
                    }
                }
            }
        }
    }

    Connections {
        target: Store
        function onInstallFinished(id, ok, message) {
            Store.refresh()
        }
    }

    Component.onCompleted: Store.refresh()
}
