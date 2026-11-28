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
    // §5.1 material ladder — "panel" (the TOP BAR only since W80: ink
    // glass for readable status glyphs), "sheet" (CC, calendar,
    // launcher, menus, dock tray, Island) or "chrome" (the AppWindow
    // 44 px titleband — more transparent than sheets, the single
    // biggest macOS tell). Per-screen ad-hoc values stay forbidden.
    property string rung: "panel"
    property int cornerRadius: 0
    radius: cornerRadius
    color: {
        if (!Util.darkMode) {
            if (rung === "sheet") return Tokens.sheetTintLight
            if (rung === "chrome") return Tokens.chromeTintLight
            return Tokens.barTintLight
        }
        if (rung === "sheet") return Tokens.sheetTint
        if (rung === "chrome") return Tokens.chromeTint
        return Tokens.barTint
    }
    border.color: {
        if (!Util.darkMode)
            return Tokens.glassBorderLight
        if (rung === "sheet") return Tokens.sheetBorder
        if (rung === "chrome") return Tokens.chromeBorder
        return Tokens.glassBorder
    }
    border.width: 1

    // (1) top highlight band — the "lit from above" streak; Liquid
    // Glass v1.6 doubled its reach (8 → 14 px) and brightness so the
    // rim, not the fill, defines the shape
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 1
            leftMargin: Math.max(1, parent.cornerRadius)
            rightMargin: Math.max(1, parent.cornerRadius)
        }
        height: 14
        visible: parent.height > 16
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.20) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.03) }
        }
    }

    // (2b) LIQUID GLASS v1.6 — the sheen wash: a broad soft light
    // across the upper half (the lens reads as curved because of this,
    // not because of the border). Vertical gradient approximates the
    // diagonal sweep without a rotated, clipped child.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: parent.height > 60
        gradient: Gradient {
            GradientStop { position: 0;    color: Qt.rgba(1, 1, 1, 0.05) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1;    color: Qt.rgba(0, 0, 0, 0.04) }
        }
    }

    // (3) bottom inner stroke — the bounce light, doubled for the thin
    // plate (a floating panel, not a sticker)
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
        color: Qt.rgba(1, 1, 1, 0.10)
    }

    // (4) LIQUID GLASS v1.6 — inner bottom shadow: the depth cue that
    // makes the plate read as a lens standing over the wallpaper
    Rectangle {
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            bottomMargin: 2
            leftMargin: Math.max(1, parent.cornerRadius)
            rightMargin: Math.max(1, parent.cornerRadius)
        }
        height: 2
        visible: parent.height > 16
        color: Qt.rgba(0, 0, 0, 0.10)
    }
}
