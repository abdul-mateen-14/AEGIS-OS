import QtQuick
import QtQuick.Controls
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

    // W52 — the exclusive zone follows the tray state so maximized
    // windows keep the macOS contract (stop above the RESTING dock;
    // hidden reclaims the strip). The numbers mirror main.cpp
    // DOCK_RESERVE: tray iconSize + trayPadding*2 + dotGap, +12 for the
    // dock window's 10 px bottom margin + the 2 px cushion.
    function publishReserve() {
        if (typeof AegisSurfaces === "undefined")
            return
        AegisSurfaces.setDockExclusiveZone(
            stateName === "expanded"
                ? Tokens.iconSize + Tokens.trayPadding * 2 + Tokens.dotGap + 12
                : stateName === "sliver" ? Tokens.sliverHeight + 12 : 0)
    }
    onStateNameChanged: publishReserve()

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

    // W21 — publish the RESTING tile centers for the aegis-dockzoom
    // effect (transported through kwinrc — see Util.publishDockTileMap).
    // Computed at rest on purpose: the magnification wave moves tiles
    // transiently and the effect should anchor where the tile lives, not
    // where it is mid-wave.
    // D25 — the format is quote-free "head=cx,cy;head2=cx,cy", keyed by
    // the command HEAD (the window resourceClass). The old JSON rode
    // QSettings IniFormat, which escaped the quotes as \" — an invalid
    // KConfig escape the guest journal flagged twice per session
    // ("Invalid escape sequence «\"»").
    function publishTileMap() {
        var parts = []
        for (var i = 0; i < row.children.length; ++i) {
            var t = row.children[i]
            if (!t.iconItem || t.isSeparator)
                continue
            var cmd = t.modelData.cmd || ""
            if (!cmd)
                continue
            var p = t.iconItem.mapToItem(null,
                                         t.iconItem.width / 2,
                                         t.iconItem.height / 2)
            parts.push(cmd.split(" ")[0] + "="
                       + Math.round(p.x + dockRoot.x) + ","
                       + Math.round(p.y + dockRoot.y))
        }
        Util.publishDockTileMap(parts.join(";"))
    }

    Component.onCompleted: { publishTileMap(); publishReserve() }
    // the layer-shell configure assigns the window position AFTER the
    // component completes — republish when it lands and once later
    onXChanged: publishTileMap()
    onYChanged: publishTileMap()
    Timer {
        interval: 1500
        running: true
        onTriggered: dockRoot.publishTileMap()
    }

    // W22 — the Add-to-Dock input pill (right-click on the tray glass).
    // Anchored to the WINDOW, not the tray: the tray folds to 0.55 scale
    // and the pill must not distort with it. The dock surface's keyboard
    // interactivity is OnDemand, so the field takes typing directly.
    // Enter adds, Escape cancels; nothing is added unless the user asks.
    Rectangle {
        id: addPill
        property bool open: false
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Tokens.dockMargin + Tokens.iconSize
                          + Tokens.trayPadding * 2 + Tokens.dotGap + 12
        }
        width: 470
        height: 58
        radius: 29
        color: Tokens.dockGlassTint
        border.color: Tokens.dockGlassBorder
        border.width: 1
        opacity: open ? 1 : 0
        scale: open ? 1 : 0.92
        visible: opacity > 0
        onOpenChanged: if (open) urlField.forceActiveFocus()
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutBack }
        }

        function commit() {
            if (urlField.text.trim().length === 0) {
                open = false
                return
            }
            Util.addWebShortcut(urlField.text)
            urlField.text = ""
            open = false
        }

        Row {
            anchors { fill: parent; margins: 11 }
            spacing: 8

            TextField {
                id: urlField
                width: 330
                height: 36
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Paste a link — https://…"
                font { family: "Montserrat"; pixelSize: 12 }
                color: Tokens.fg
                placeholderTextColor: Tokens.fgMuted
                selectByMouse: true
                background: Rectangle {
                    radius: 18
                    color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.06)
                                         : Qt.rgba(0, 0, 0, 0.05)
                    border.color: urlField.activeFocus ? Tokens.accent
                                                       : Tokens.glassBorder
                }
                onAccepted: addPill.commit()
                Keys.onEscapePressed: addPill.open = false
            }

            Rectangle {
                width: 62; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: Tokens.accent
                Text {
                    anchors.centerIn: parent
                    text: "Add"
                    color: "#FFFFFF"
                    font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: addPill.commit()
                }
            }

            Rectangle {
                width: 36; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: Util.darkMode ? Qt.rgba(1, 1, 1, 0.08)
                                     : Qt.rgba(0, 0, 0, 0.06)
                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    color: Tokens.fgMuted
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: addPill.open = false
                }
            }
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

        // Tray capsule — light Liquid Glass (the user's macOS dock look).
        // §5.2 — the hero surface keeps its own wash: a 12 px vertical
        // gradient inside the top edge, formalizing the measured 56→52
        // top-to-bottom luminance drift (dockWash token).
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

            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 2
                    leftMargin: Tokens.trayRadius
                    rightMargin: Tokens.trayRadius
                }
                height: 12
                gradient: Gradient {
                    GradientStop { position: 0; color: Tokens.dockWash }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
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

        // W22 — right-click on the empty tray glass opens the Add flow.
        // Strictly opt-in: the default dock carries zero web tiles (W9).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            cursorShape: Qt.ArrowCursor
            enabled: !addPill.open
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    addPill.open = true
            }
        }

        Menu {
            id: webMenu
            property string webId: ""
            // §5.5 — Sheet Glass rung (radius 12 menu deviation, TASKS)
            background: GlassPanel {
                rung: "sheet"
                cornerRadius: 12
            }
            MenuItem {
                text: "Remove from Dock"
                onTriggered: Util.removeWebShortcut(webMenu.webId)
            }
        }

        // W36.2 — the first-party tile menu: New Window always, Quit for
        // a running app, Empty Trash on the Trash slot. Right-click was a
        // silent no-op on these tiles — the W37 sweep flags exactly that.
        Menu {
            id: tileMenu
            property bool trash: false
            property bool running: false
            property string head: ""
            property string launchCmd: ""
            dim: false
            // §5.5 — Sheet Glass rung (radius 12 menu deviation, TASKS)
            background: GlassPanel {
                rung: "sheet"
                cornerRadius: 12
            }
            MenuItem {
                text: "New Window"
                onTriggered: Util.launch(tileMenu.launchCmd)
            }
            MenuItem {
                visible: tileMenu.running && !tileMenu.trash
                text: "Quit"
                onTriggered: Util.quitApp(tileMenu.head)
            }
            MenuItem {
                visible: tileMenu.trash
                text: "Empty Trash"
                onTriggered: Util.emptyTrash()
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
                        // W27 — a dock click brings an existing window
                        // back (activateOrLaunch falls through to a
                        // normal launch otherwise; argumented cmds like
                        // the Trash slot never re-focus). Tier B slots
                        // carry the resolved .desktop Exec in launch.
                        Util.activateOrLaunch(tile.modelData.cmd || "",
                                              tile.modelData.launch
                                              || tile.modelData.cmd || "")
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                if (tile.modelData.web) {
                                    // W22 — user-added web shortcuts are
                                    // removable; first-party slots are not
                                    webMenu.webId = tile.modelData.id || ""
                                    webMenu.popup()
                                } else if (!tile.isSeparator) {
                                    // W36.2 — every first-party tile gets a
                                    // real menu (right-click was a silent
                                    // no-op here — the W37 sweep flags it)
                                    tileMenu.trash =
                                        (tile.modelData.cmd || "")
                                        .indexOf("trash:///") >= 0
                                    tileMenu.head =
                                        (tile.modelData.cmd || "")
                                        .split(" ")[0]
                                    tileMenu.launchCmd =
                                        tile.modelData.launch
                                        || tile.modelData.cmd || ""
                                    tileMenu.running =
                                        Util.isRunning(tileMenu.head)
                                    tileMenu.popup()
                                }
                                return
                            }
                            tile.launch()
                        }
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
