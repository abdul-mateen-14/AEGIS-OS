import QtQuick
import Aegis.Util

// Layer::Background — the desktop canvas. M1 renders the wallpaper only;
// canvas icons, the single widget and hot corners arrive in M2 (§2.3).
Window {
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
