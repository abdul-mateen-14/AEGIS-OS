import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aegis.Util
import Aegis.Store

// Aegis Store — T14, the apt-backed app store (the user ruling: "an
// appstore with all the famous ubuntu and debian etc apps"). One curated
// catalog of the famous archive packages, dpkg-query for the installed
// state, sudo -n apt-get for install/remove (NOPASSWD via 0610). The
// cards carry letter tiles in the category tint — the store icon
// (aegis-store) ships in the Aegis theme.
Window {
    id: storeRoot

    width: 1120
    height: 720
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

    Rectangle {
        id: band
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 44
        color: Util.darkMode ? "#17181D" : "#F4F6FA"
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Tokens.glassBorder
        }
        Text {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: "Store"
            font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
            color: Tokens.fg
        }
    }

    RowLayout {
        anchors { top: band.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 0

        // ── sidebar: search + categories ──────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 216
            color: Util.darkMode ? "#141519" : "#EDEFF4"
            Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: Tokens.glassBorder }

            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 8

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    height: 36
                    placeholderText: "Search apps"
                    font { family: "Montserrat"; pixelSize: 12 }
                    color: Tokens.fg
                    placeholderTextColor: Tokens.fgMuted
                    selectByMouse: true
                    background: Rectangle {
                        radius: 18
                        color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                        border.color: searchField.activeFocus ? Tokens.accent : Tokens.glassBorder
                    }
                    onTextChanged: storeRoot.query = text
                }

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

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    text: Store.installingId.length > 0
                          ? "Installing " + Store.installingId + "…"
                          : "apt-backed · Ubuntu + Debian archive"
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

                        Rectangle {
                            width: 50; height: 50; radius: 14
                            color: {
                                var t = "#3E8BFF"
                                for (var i = 0; i < storeRoot.categories.length; ++i)
                                    if (storeRoot.categories[i].label === modelData.category)
                                        t = storeRoot.categories[i].tint
                                return t
                            }
                            Text {
                                anchors.centerIn: parent
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

    Connections {
        target: Store
        function onInstallFinished(id, ok, message) {
            Store.refresh()
        }
    }

    Component.onCompleted: Store.refresh()
}
