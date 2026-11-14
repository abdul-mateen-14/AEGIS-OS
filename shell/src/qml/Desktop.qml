import QtQuick
import QtQuick.Controls
import Aegis.Util
import Aegis.Governor
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

    // T15-D4 (W39.1) — the Focus-dim wallpaper veil. A REAL effect now:
    // Governor.effects["wallpaperDim"] is a settable override (the
    // Settings switch calls Governor.setEffect) and the veil applies
    // while any normal window is on the workspace (the same predicate
    // the island auto-hide rides) — none when the desktop is frontmost.
    // 18% black, 200 ms ease, per the review contract.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        visible: opacity > 0.005
        opacity: (Governor.effects["wallpaperDim"] === true
                  && Util.workspaceWindows > 0) ? 0.18 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
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
        // §5.5 — menus ride the Sheet Glass rung. Radius 12 (not the
        // sheet's 18): at menu sizes r18 reads as a bubble; 12 keeps the
        // menu anatomy. Recorded as a deliberate rung deviation in TASKS.
        background: GlassPanel {
            rung: "sheet"
            cornerRadius: 12
        }
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
