import QtQuick
import Aegis.Util

// Panel Glass — proposal §3 Table 7 + review round 7 §5. Dark rung
// default; light rung when the user flips Dark Mode off in Control
// Center (M2; full light audit M4).
//
// Layer 1 (backdrop blur) is provided by KWin through the real client
// channel: every glass surface calls KWindowEffects::enableBlurBehind
// (org_kde_kwin_blur) — shell surfaces in main.cpp, app chrome bands in
// apps-main.cpp — gated by Governor blurLive / blurAny (W50/W57). Stock
// KWin 6 has NO window-rule force-blur; the old kwinrulesrc story was
// fiction. Blur follows window alpha, so the tint below stays as-is.
//
// §5.2 — the specular edge system, three layers, every rung inherits:
//   (1) top highlight BAND — 8 px gradient white 12% → 2%; the "lit from
//       above" streak (macOS materials read as curved because of this
//       gradient, not the old 1 px line)
//   (2) the 1 px hairline border — luminance-matched per rung
//   (3) bottom inner stroke — white 6% bounce light that separates a
//       floating panel from a sticker
Rectangle {
    // §5.1 material ladder — "panel" (dock tray, Island, top panel),
    // "sheet" (CC, calendar, launcher, menus) or "chrome" (the AppWindow
    // 44 px titleband — more transparent than sheets, the single biggest
    // macOS tell). Per-screen ad-hoc values stay forbidden.
    property string rung: "panel"
    property int cornerRadius: 0
    radius: cornerRadius
    color: {
        if (!Util.darkMode) {
            if (rung === "sheet") return Tokens.sheetTintLight
            if (rung === "chrome") return Tokens.chromeTintLight
            return Tokens.glassTintLight
        }
        if (rung === "sheet") return Tokens.sheetTint
        if (rung === "chrome") return Tokens.chromeTint
        return Tokens.glassTint
    }
    border.color: {
        if (!Util.darkMode)
            return Tokens.glassBorderLight
        if (rung === "sheet") return Tokens.sheetBorder
        if (rung === "chrome") return Tokens.chromeBorder
        return Tokens.glassBorder
    }
    border.width: 1

    // (1) top highlight band — replaces the old 1 px inset line
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 1
            leftMargin: Math.max(1, parent.cornerRadius)
            rightMargin: Math.max(1, parent.cornerRadius)
        }
        height: 8
        visible: parent.height > 10
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.12) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.02) }
        }
    }

    // (3) bottom inner stroke — the faint bounce light
    Rectangle {
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            bottomMargin: 1
            leftMargin: Math.max(1, parent.cornerRadius)
            rightMargin: Math.max(1, parent.cornerRadius)
        }
        height: 1
        visible: parent.height > 10
        color: Qt.rgba(1, 1, 1, 0.06)
    }
}
