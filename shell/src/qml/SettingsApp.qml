import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aegis.Util
import Aegis.Governor
import Aegis.Files

// Aegis Settings — first-party settings app (proposal §6, plates 10/11/13).
//
// Sidebar: Aegis ID row FIRST (38 px avatar + name + chevron, where Apple ID
// sits), then the §6 pane order — Wallpaper · Appearance · Desktop Effects ·
// Drivers & Firmware · Displays · Sound · Network · Users.
// Wired TODAY: Dark/Light (Util), tier control (Governor), Aegis ID identity.
// Stub panes carry their spec pointer; backends land with the M3 milestone.
Window {
    id: win

    width: 900; height: 640
    minimumWidth: 520; minimumHeight: 360
    visible: true
    title: "Settings"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    property int pane: 0  // index into panes below

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
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        background: Rectangle {
                            radius: 12
                            color: Util.darkMode ? "#262930" : "#DDE3EE"
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
                                    text: Util.userInitials
                                    font { pixelSize: 14; bold: true }
                                    color: "#FFFFFF"
                                }
                            }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0
                                Text { text: Util.userName; font.pixelSize: 13; font.bold: true; color: Tokens.fg }
                                Text { text: "Aegis ID"; font.pixelSize: 11; color: Tokens.fgMuted }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "\u203a"; font.pixelSize: 18; color: Tokens.fgMuted; Layout.alignment: Qt.AlignVCenter; Layout.rightMargin: 8 }
                        }
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
                                leftPadding: 10
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    Layout.alignment: Qt.AlignVCenter
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
                    // panes 0–3 have real content; Displays/Sound/Network/Users
                    // (4–7) all render the stub until their backends land (M3).
                    sourceComponent: win.pane < 4
                                     ? [wallpaperPane, appearancePane,
                                        effectsPane, driversPane][win.pane]
                                     : stubPane
                }
            }
        }

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
    }

    // ── Wallpaper (Table 15: four defaults · choose image · rotation · Focus-dim)
    Component {
        id: wallpaperPane
        ColumnLayout {
            spacing: 14
            Text { text: "Wallpaper"; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            RowLayout {
                spacing: 12
                Repeater {
                    model: [
                        { name: "Aurora Ink",    top: "#2A3F55", bottom: "#0C1520", note: "Dark default" },
                        { name: "Graphite Dune", top: "#B8AFA4", bottom: "#6E6862", note: "Light default" },
                        { name: "Neon Coast",    top: "#FF7E5F", bottom: "#17A2A6", note: "The colorful pick" },
                        { name: "Emerald Ridge", top: "#2F5D50", bottom: "#0E1F1A", note: "The calm pick" }
                    ]
                    delegate: ColumnLayout {
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 132; Layout.preferredHeight: 82
                            radius: 12
                            border.color: Tokens.accent; border.width: 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: modelData.top }
                                GradientStop { position: 1; color: modelData.bottom }
                            }
                        }
                        Text { text: modelData.name; font.pixelSize: 12; color: Tokens.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: modelData.note; font.pixelSize: 10; color: Tokens.fgMuted; Layout.alignment: Qt.AlignHCenter }
                    }
                }
                // dashed Choose image… tile
                Rectangle {
                    Layout.preferredWidth: 132; Layout.preferredHeight: 82
                    radius: 12
                    color: "transparent"
                    border.color: Tokens.fgMuted
                    border.width: 1.5
                    Text { anchors.centerIn: parent; text: "Choose image\u2026"; font.pixelSize: 12; color: Tokens.fgMuted }
                    TapHandler { onTapped: imageDialog.open() }
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
                text: "Apply at first boot from /usr/share/wallpapers/aegis — live apply lands with the Desktop property setter (M4)."
                font.pixelSize: 11; color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    // ── Appearance (§6: Auto/Dark/Light cards + six accent presets)
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
            Text { text: "Accent"; font.pixelSize: 13; color: Tokens.fg }
            RowLayout {
                spacing: 10
                Repeater {
                    model: ["#3E8BFF", "#28C840", "#FF9F0A", "#FF6B84", "#8B5CF6", "#5B6068"]
                    delegate: Rectangle {
                        width: 28; height: 28; radius: 14
                        color: modelData
                        border.color: Tokens.fg; border.width: modelData === Tokens.accent ? 2 : 0
                        TapHandler { onTapped: console.log("accent", modelData, "— one-token recolor lands with Tokens.accent setter (M4)") }
                    }
                }
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

    // ── Displays / Sound / Network / Users placeholders (spec §6)
    Component {
        id: stubPane
        ColumnLayout {
            spacing: 8
            Text { text: win.panes[win.pane].label; font.family: "Montserrat"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Tokens.fg }
            Text {
                text: "Backend wiring lands with the M3 milestone:\n· Displays — kscreen D-Bus (resolution · scale · night light)\n· Sound — PipeWire (output · input · devices)\n· Network — NetworkManager D-Bus (Wi-Fi list · known networks)\n· Users — AccountsService (person glyph, §6)"
                font.pixelSize: 12
                color: Tokens.fgMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
}
