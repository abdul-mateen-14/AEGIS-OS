import QtQuick
import Aegis.Util

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

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Util.config["wallpaper"] || "/usr/share/wallpapers/aegis/aurora-ink.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: false
    }
}
