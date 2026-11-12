import QtQuick
import QtQuick.Controls
import Aegis.Util
import Aegis.Files

// Layer::Background — the desktop canvas. M1 renders the wallpaper only;
// canvas icons, the single widget and hot corners arrive in M2 (§2.3).
Window {
    // KWin's alt+F4 must never destroy a shell surface: with no app window
    // focused, the focused layer surface receives the close and would die
    // (dock -> island -> panel cascade, observed on the v0.6.5 boot test).
    onClosing: (close) => { close.accepted = false }
    objectName: "desktopWindow"
    visible: false
    color: "transparent"
    width: 1920
    height: 1080
    flags: Qt.FramelessWindowHint

    // W36.1 — the desktop right-click: New Folder in ~/Desktop, the two
    // Settings jumps, and a terminal. The review's Clean Up entry waits
    // for desktop icons (M2) and stays out until then.
    function newDesktopFolder() {
        // ensure ~/Desktop exists first (mkdir is single-level)
        Files.makeDir(Files.homeUrl(), "Desktop")
        const desk = Files.homeUrl().toString().replace(/\/$/, "")
                     + "/Desktop"
        if (Files.makeDir(desk, "New Folder"))
            return
        for (let i = 2; i < 100; ++i)
            if (Files.makeDir(desk, "New Folder " + i))
                return
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        // W4 — live apply: Util.wallpaper is a property with a NOTIFY, so a
        // Settings-side change (pane or Aegis ID sync over DBus) repaints here.
        source: Util.wallpaper || Util.config["wallpaper"]
                || "/usr/share/wallpapers/aegis/aurora-ink.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: false
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.ArrowCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                desktopMenu.popup()
        }
    }

    Menu {
        id: desktopMenu
        dim: false
        MenuItem {
            text: "New Folder"
            onTriggered: newDesktopFolder()
        }
        MenuSeparator {}
        MenuItem {
            text: "Change Wallpaper…"
            onTriggered: Util.launch("aegis-settings 0")
        }
        MenuItem {
            text: "Display Settings"
            onTriggered: Util.launch("aegis-settings 4")
        }
        MenuItem {
            text: "Open Terminal"
            onTriggered: Util.launch("konsole")
        }
    }
}
