import QtQuick
import Aegis.Util

// Floating dock — a real liquid tray, packed macOS-tight (§2.2, Table 4).
//
// The magnification field is the exact §2.2 developer recipe:
//   (1) Track  — one HoverHandler on the tray; per-tile signed distance d is
//                measured from the LIVE rects (Row re-lays-out as widths
//                animate), so the field follows the moving icons.
//   (2) Map    — target = B·(1 + 0.85·(1 − |d|/2.4B)) inside ±2.4 tiles, B
//                outside; 1.85·B exactly at d = 0. Straight line, no easing.
//   (3) Solve  — per-tile spring mass 0.1 · stiffness 170 · damping 13, two
//                Euler substeps per frame (Spring.step).
//   (4) Write  — tile WIDTH animates, so neighbours slide aside and the tray
//                length breathes; the icon scales from its bottom edge; the
//                label rides 8 px above the magnifying icon's top.
//   (5) Launch — two-hop bounce y [0, −0.32B, 0, −0.12B, 0] @ 0.65 s on a
//                Translate transform so it never fights the icon scale.
//
// States: Expanded tray (always visible — the user's macOS dock) · Sliver
// 120×4 · Hidden. Esc folds; pointer held in the bottom 8 px for 150 ms
// springs it back. Auto-hide is disabled (Tokens.idleHideMs = 0).
Window {
    // KWin's alt+F4 must never destroy a shell surface: with no app window
    // focused, the focused layer surface receives the close and would die
    // (dock -> island -> panel cascade, observed on the v0.6.5 boot test).
    onClosing: (close) => { close.accepted = false }
    objectName: "dockWindow"
    visible: false
    color: "transparent"
    width: 1280
    height: 340
    flags: Qt.FramelessWindowHint

    id: dockRoot

    property string stateName: "expanded"        // expanded | sliver | hidden
    property int hoverIndex: -1

    function targetFor(d) {
        var B = Tokens.tileWidth
        var ad = Math.abs(d)
        if (ad >= Tokens.magFalloff * B)
            return B
        return B * (1 + Tokens.magStrength * (1 - ad / (Tokens.magFalloff * B)))
    }

    function resetField() {
        hoverIndex = -1
        tray.fieldGrowth = 0
        for (var i = 0; i < row.children.length; ++i) {
            var t = row.children[i]
            if (t.spring)
                t.spring.target = Tokens.tileWidth
        }
    }

    Timer {
        id: idleHideTimer
        interval: Tokens.idleHideMs
        running: Tokens.idleHideMs > 0
                 && dockRoot.stateName === "expanded" && dockRoot.hoverIndex < 0
        onTriggered: dockRoot.stateName = "sliver"
    }

    // Table 4 — reveal: pointer in bottom 8 px for 150 ms
    Timer {
        id: probeTimer
        interval: Tokens.sliverProbeMs
        onTriggered: dockRoot.stateName = "expanded"
    }

    HoverHandler {
        id: edgeProbe
        enabled: dockRoot.stateName !== "expanded"
        onPointChanged: {
            if (dockRoot.stateName === "sliver" && !probeTimer.running)
                probeTimer.restart()
        }
        onHoveredChanged: {
            if (hovered && dockRoot.stateName !== "expanded")
                probeTimer.restart()
        }
    }

    // Sliver — 120×4 px pill of light, 0.04% of the canvas (Edge Glass)
    Rectangle {
        width: Tokens.sliverWidth
        height: Tokens.sliverHeight
        radius: 2
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
        }
        color: Qt.rgba(1, 1, 1, 0.55)
        opacity: dockRoot.stateName === "sliver" ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Tokens.durSmooth
                easing.type: Easing.OutCubic
            }
        }
    }

    // The liquid glass tray
    Item {
        id: tray
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Tokens.dockMargin
        }
        // V1 — the pill's horizontal padding grows by the same delta the
        // magnified icons add: the row always grew the tray with it, but
        // the PADDING stayed 6 px, so the end tiles kept kissing the
        // rounded corners while the field was live (01b-dock-magnify:
        // Files at 3-4 px from the left edge). The solver writes the
        // largest spring rise over B here; both ends clear the corners.
        property real fieldGrowth: 0
        width: row.implicitWidth + Tokens.trayPadding * 2 + fieldGrowth
        // macOS behaviour — the tray is a FIXED SHELF. Its height NEVER
        // changes: the magnified icon OVERFLOWS above the tray's top edge and
        // hangs over the desktop (v1.3 reference plate: the icon fills ~79%
        // of the tray height at rest). Only the tray's WIDTH breathes — the
        // animated tile widths already do that part correctly.
        height: Tokens.iconSize + Tokens.trayPadding * 2 + Tokens.dotGap

        opacity: dockRoot.stateName === "expanded" ? 1 : 0
        scale: dockRoot.stateName === "expanded" ? 1 : 0.55
        transformOrigin: Item.Bottom
        Behavior on opacity {
            NumberAnimation {
                duration: Tokens.durSmooth
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Tokens.sliverSpringMs
                easing.type: Easing.OutBack
            }
        }

        // Tray capsule — light Liquid Glass (the user's macOS dock look)
        Rectangle {
            anchors.fill: parent
            radius: Tokens.trayRadius
            color: Tokens.dockGlassTint
            border.color: Tokens.dockGlassBorder
            border.width: 1

            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 1
                    leftMargin: Tokens.trayRadius
                    rightMargin: Tokens.trayRadius
                }
                height: 1
                color: Tokens.dockGlassHighlight
            }
        }

        // (1) Track — one hover handler over the whole tray
        HoverHandler {
            id: trayPointer
            onPointChanged: recompute(point.position.x)
            onHoveredChanged: if (!hovered) dockRoot.resetField()

            function recompute(px) {
                px -= row.x   // px is in tray coords, tile x is in row coords
                for (var i = 0; i < row.children.length; ++i) {
                    var t = row.children[i]
                    if (!t.spring)
                        continue
                    var center = t.x + t.width / 2   // live rect, not resting
                    t.spring.target = dockRoot.targetFor(px - center)
                }
            }
        }

        Row {
            id: row
            anchors {
                bottom: parent.bottom
                bottomMargin: Tokens.trayPadding
                horizontalCenter: parent.horizontalCenter
            }
            spacing: Tokens.tileGap

            Repeater {
                // W8/W9 — the resolved dock model: installed apps only, Tier B
                // slots wearing their own .desktop marks.
                model: Util.dockApps

                delegate: Item {
                    id: tile
                    required property int index
                    required property var modelData

                    property bool isSeparator: (modelData.type === "separator")
                    property alias iconItem: icon
                    property Spring spring: Spring {
                        mass: Tokens.dockSpringMass
                        stiffness: Tokens.dockSpringStiffness
                        damping: Tokens.dockSpringDamping
                        value: Tokens.tileWidth
                        target: Tokens.tileWidth
                    }

                    width: isSeparator ? 1 : spring.value   // (4) Write — width breathes
                    height: Tokens.tileHeight
                    visible: !isSeparator

                    // (5) Launch — bounce on a Translate so the scale never fights it
                    Item {
                        id: bounce
                        width: icon.width
                        height: icon.height
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                        }
                        transform: Translate { id: lift }

                        Image {
                            id: icon
                            source: "image://icons/" + (tile.modelData.icon || "application-x-executable")
                            width: Tokens.iconSize * (tile.spring.value / Tokens.tileWidth)
                            height: width
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                            sourceSize: Qt.size(128, 128)
                        }

                        // running dot — 4 px, floats 4 px clear of the icon
                        Rectangle {
                            width: Tokens.dotSize
                            height: Tokens.dotSize
                            radius: Tokens.dotSize / 2
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                bottom: parent.bottom
                                bottomMargin: -Tokens.dotGap
                            }
                            color: "#E8ECF2"
                            opacity: Util.isRunning(tile.modelData.cmd || "") ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Tokens.durQuick
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    SequentialAnimation {
                        id: bounceAnim
                        NumberAnimation { target: lift; property: "y"; to: -Tokens.bounceHopHigh * Tokens.tileWidth; duration: Tokens.bounceMs * 0.28; easing.type: Easing.OutQuad }
                        NumberAnimation { target: lift; property: "y"; to: 0; duration: Tokens.bounceMs * 0.22; easing.type: Easing.InQuad }
                        NumberAnimation { target: lift; property: "y"; to: -Tokens.bounceHopLow * Tokens.tileWidth; duration: Tokens.bounceMs * 0.28; easing.type: Easing.OutQuad }
                        NumberAnimation { target: lift; property: "y"; to: 0; duration: Tokens.bounceMs * 0.22; easing.type: Easing.InQuad }
                    }

                    function launch() {
                        bounceAnim.restart()
                        Util.launch(tile.modelData.cmd || "")
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tile.launch()
                    }

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered)
                                dockRoot.hoverIndex = tile.index
                            else if (dockRoot.hoverIndex === tile.index)
                                dockRoot.hoverIndex = -1
                        }
                    }
                }
            }
        }

        // App-name label — macOS dock tooltip: black bubble riding above the
        // magnifying icon's top edge, at every size
        Rectangle {
            id: nameLabel
            height: 22
            width: nameText.implicitWidth + 20
            radius: 11
            color: Qt.rgba(0.09, 0.09, 0.10, 0.94)
            border.color: Qt.rgba(1, 1, 1, 0.10)
            opacity: 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Tokens.durQuick
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: nameText
                anchors.centerIn: parent
                color: Tokens.fg
                font {
                    family: "Montserrat"
                    pixelSize: 11
                    weight: Font.Medium
                }
            }
        }

        // (3) Solve — springs integrated every frame while expanded
        FrameAnimation {
            running: dockRoot.stateName === "expanded"
            onTriggered: {
                var growth = 0
                for (var i = 0; i < row.children.length; ++i) {
                    var t = row.children[i]
                    if (t.spring) {
                        t.spring.step(frameTime)
                        // V1 — track the largest magnification rise for the
                        // tray padding (both ends must clear the corners)
                        if (t.spring.value - Tokens.tileWidth > growth)
                            growth = t.spring.value - Tokens.tileWidth
                    }
                }
                tray.fieldGrowth = growth
                // (1) Track, continued — point.position only fires when the
                // pointer MOVES; when the tiles slide under a stationary pointer
                // the field must be refreshed here, or the wave freezes
                // mid-motion (this is what broke the asymmetric 01b capture).
                if (trayPointer.hovered)
                    trayPointer.recompute(trayPointer.point.position.x)
                updateLabel()
            }

            function updateLabel() {
                var idx = dockRoot.hoverIndex
                if (idx < 0 || idx >= row.children.length) {
                    nameLabel.opacity = 0
                    return
                }
                var t = row.children[idx]
                if (!t || !t.iconItem || t.isSeparator) {
                    nameLabel.opacity = 0
                    return
                }
                var topPoint = tray.mapFromItem(t.iconItem, t.iconItem.width / 2, 0)
                nameText.text = t.modelData.name || ""
                nameLabel.x = topPoint.x - nameLabel.width / 2
                nameLabel.y = topPoint.y - 8 - nameLabel.height
                nameLabel.opacity = 1
            }
        }
    }
}
