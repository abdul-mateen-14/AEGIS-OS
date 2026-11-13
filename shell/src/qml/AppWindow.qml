import QtQuick
import QtQuick.Layouts
import Aegis.Util

// Table 18 — the shared window anatomy for the first-party suite.
// 44 px Panel Glass titlebar (traffic lights) · 52 px opaque toolbar with a
// hairline bottom · opaque radius-18 body · 6 px resize zones on all eight
// edges/corners. Frameless CSD: drag + resize go through the Wayland system
// interfaces so KWin keeps tiling, snapping and corner rounding.
//
// Usage: Window { AppWindow { title: "Files"; toolbar: [...]; <content> } }
Item {
    id: root

    readonly property Window window: Window.window
    property string title: ""
    property color accent: Tokens.accent
    default property alias page: body.data
    property alias toolbar: toolbarContent.data

    // opaque body — radius 18 all around (Table 18)
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Util.darkMode ? "#17181D" : "#F4F6FA"
        border.color: Tokens.glassBorder
        border.width: 1
    }

    // 44 px Panel Glass titlebar, top corners 18 (bottom corners square)
    GlassPanel {
        id: titlebar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 44
        cornerRadius: 18

        // bottom corners square — mask the panel's bottom radius (keep the
        // 1 px hairline visible above the toolbar boundary)
        Rectangle {
            anchors { bottom: parent.bottom; bottomMargin: 1; left: parent.left; right: parent.right }
            height: 18
            color: Util.darkMode ? Tokens.glassTint : Tokens.glassTintLight
        }

        DragHandler {
            target: null
            onActiveChanged: if (active && root.window) root.window.startSystemMove()
        }

        // T15-D7 (W44) — the macOS contract: double-click the titleband
        // toggles maximize/restore. The DragHandler above only engages on
        // a real drag (system move), so a double-tap never converts into
        // one; the TrafficLights keep their own grabs (a click on a light
        // never becomes a move or a maximize).
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: {
                if (!root.window) return
                if (root.window.visibility === Window.Maximized)
                    root.window.showNormal()
                else
                    root.window.showMaximized()
            }
        }

        TrafficLights {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            focused: root.window ? root.window.activeFocusItem !== null : true
            onCloseClicked: if (root.window) root.window.close()
            onMinClicked: if (root.window) root.window.showMinimized()
            onMaxClicked: {
                if (!root.window) return
                if (root.window.visibility === Window.Maximized) root.window.showNormal()
                else root.window.showMaximized()
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.title
            font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
            color: Tokens.fg
        }
    }

    // 52 px opaque toolbar, hairline bottom — app content, never glass.
    // T15-D7 (W44) — the toolbar's EMPTY stretches drag the window (the
    // macOS second-drag-region contract): the DragHandler sits on the
    // toolbar itself, and every control that wants the pointer (buttons,
    // text fields) takes its own grab first — a press that lands between
    // controls falls through to this handler and moves the window.
    Rectangle {
        id: toolbarRow
        anchors { top: titlebar.bottom; left: parent.left; right: parent.right }
        height: 52
        color: Util.darkMode ? "#17181D" : "#F4F6FA"
        DragHandler {
            target: null
            onActiveChanged: if (active && root.window) root.window.startSystemMove()
        }
        RowLayout {
            id: toolbarContent
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 8
        }
        Rectangle {
            height: 1
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            color: Tokens.glassBorder
        }
    }

    // opaque content area
    Item {
        id: body
        anchors { top: toolbarRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    // 8 invisible resize zones — T15-D7 (W44): edges 8 px (was 6 — too
    // thin a target, half of the user's "resizing needs improvement"),
    // corners 16 px (was 12). Drag to edges = half, corners = quarter
    // (KWin resolves the actual geometry; we just hand over the edge mask).
    MouseArea { anchors { top: parent.top; left: parent.left; right: parent.right } height: 8
                cursorShape: Qt.SizeVerCursor; z: 10
                onPressed: root.window.startSystemResize(Qt.TopEdge) }
    MouseArea { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 8
                cursorShape: Qt.SizeVerCursor; z: 10
                onPressed: root.window.startSystemResize(Qt.BottomEdge) }
    MouseArea { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 8
                cursorShape: Qt.SizeHorCursor; z: 10
                onPressed: root.window.startSystemResize(Qt.LeftEdge) }
    MouseArea { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 8
                cursorShape: Qt.SizeHorCursor; z: 10
                onPressed: root.window.startSystemResize(Qt.RightEdge) }
    MouseArea { anchors { top: parent.top; left: parent.left } width: 16; height: 16
                cursorShape: Qt.SizeFDiagCursor; z: 11
                onPressed: root.window.startSystemResize(Qt.TopEdge | Qt.LeftEdge) }
    MouseArea { anchors { top: parent.top; right: parent.right } width: 16; height: 16
                cursorShape: Qt.SizeBDiagCursor; z: 11
                onPressed: root.window.startSystemResize(Qt.TopEdge | Qt.RightEdge) }
    MouseArea { anchors { bottom: parent.bottom; left: parent.left } width: 16; height: 16
                cursorShape: Qt.SizeBDiagCursor; z: 11
                onPressed: root.window.startSystemResize(Qt.BottomEdge | Qt.LeftEdge) }
    MouseArea { anchors { bottom: parent.bottom; right: parent.right } width: 16; height: 16
                cursorShape: Qt.SizeFDiagCursor; z: 11
                onPressed: root.window.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }
}
