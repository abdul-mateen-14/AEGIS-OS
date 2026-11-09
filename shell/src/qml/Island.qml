import QtQuick
import Aegis.Util
import Aegis.Activity
import Aegis.Governor

// Dynamic Island — the system's live-activity capsule (§2.4, Table 5b).
//
// The one opaque instrument in the shell: an ink capsule (#101216 → #08090C,
// hairline white 14%) hanging flush from the panel's bottom edge, dead
// center. Radius tracks height (r = h/2, capped 32) so the capsule never
// pinches. Morph spring: mass 1 · stiffness 420 · damping 28 (the Apple
// "boing" — about 4% overshoot, settled in ~450 ms); content crossfades
// 140 ms starting 90 ms into the move.
//
// M2: the island no longer plays a demo cycle — it renders exactly what
// applications publish through the Live Activity API (org.aegis.Island).
// States are data rows: one geometry record per kind in
// Tokens.islandStates, priority stack call > aegisId > timer > media >
// charging > generic enforced by the C++ queue. Two simultaneous
// activities render as the split capsule — two lobes 8 px apart breathing
// as one wave; two lobes is the ceiling, everything else queues in
// Control Center. Charging is shell-owned: published automatically on
// the AC transition. The Now Playing visualizer is the only permanently
// animating element and is switched off on tier C (Governor).
Window {
    objectName: "islandWindow"
    visible: false
    color: "transparent"
    width: 420
    height: 140
    flags: Qt.FramelessWindowHint

    id: islandRoot

    // ── live activity feed ─────────────────────────────────────────
    property var activities: Activity.activities
    property var primary: activities.length > 0 ? activities[0] : null
    property var secondary: activities.length > 1 ? activities[1] : null
    property var pd: primary ? primary.data : ({})
    property var sd: secondary ? secondary.data : ({})

    // one geometry record per kind — media renders as nowPlaying
    function stateFor(kind) {
        return kind === "media" ? "nowPlaying" : kind
    }

    property string stateName: activities.length === 0
                               ? "idle"
                               : (activities.length === 1
                                  ? stateFor(primary.kind) : "split")

    // split lobes are data-driven too: width per kind, 8 px apart
    function lobeWidth(kind) {
        if (kind === "media")
            return 132
        if (kind === "call")
            return 150
        if (kind === "aegisId")
            return 128
        return 108
    }

    property var geo: stateName === "split"
        ? ({ w: lobeWidth(primary.kind) + 8 + lobeWidth(secondary.kind),
             h: Tokens.islandIdleHeight,
             r: Tokens.islandIdleHeight / 2 })
        : (Tokens.islandStates[stateName] || Tokens.islandStates.idle)

    // shared crossfade choreography — 140 ms starting 90 ms into the move
    component CrossfadeAnim: SequentialAnimation {
        PauseAnimation { duration: Tokens.islandCrossfadeDelayMs }
        NumberAnimation {
            duration: Tokens.islandCrossfadeMs
            easing.type: Easing.OutCubic
        }
    }

    // One geometry record per state (§2.4): width, height, radius, content
    Spring {
        id: wSpring
        mass: Tokens.islandSpringMass
        stiffness: Tokens.islandSpringStiffness
        damping: Tokens.islandSpringDamping
        value: Tokens.islandIdleWidth
        target: islandRoot.geo.w
    }
    Spring {
        id: hSpring
        mass: Tokens.islandSpringMass
        stiffness: Tokens.islandSpringStiffness
        damping: Tokens.islandSpringDamping
        value: Tokens.islandIdleHeight
        target: islandRoot.geo.h
    }

    FrameAnimation {
        running: Math.abs(wSpring.target - wSpring.value) > 0.05
                 || Math.abs(hSpring.target - hSpring.value) > 0.05
        onTriggered: {
            wSpring.step(frameTime)
            hSpring.step(frameTime)
        }
    }

    Rectangle {
        id: capsule
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }
        width: wSpring.value
        height: hSpring.value
        radius: Tokens.islandRadius(height)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        gradient: Gradient {
            GradientStop { position: 0; color: Tokens.ink }
            GradientStop { position: 1; color: Tokens.inkDeep }
        }

        // ── Idle: Aegis mark 14 px + idle dot ────────────────────────
        Row {
            anchors.centerIn: parent
            spacing: 7
            opacity: islandRoot.stateName === "idle" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Image {
                source: "qrc:/qml/aegis-mark.png"
                width: 14
                height: 14
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: 3
                height: 3
                radius: 1.5
                color: Tokens.accent
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Now Playing: 64 px art · title/artist · 3-bar visualizer ──
        Row {
            anchors.centerIn: parent
            spacing: 12
            opacity: islandRoot.stateName === "nowPlaying" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Rectangle {
                width: 64
                height: 64
                radius: 12
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: islandRoot.pd.artColor1 || "#5A9BFF"
                    }
                    GradientStop {
                        position: 1
                        color: islandRoot.pd.artColor2 || "#1E3E8C"
                    }
                }
                Image {
                    visible: !islandRoot.pd.artColor1
                    source: "qrc:/qml/aegis-mark.png"
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    fillMode: Image.PreserveAspectFit
                    opacity: 0.85
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: islandRoot.pd.title || "Now Playing"
                    color: Tokens.paper
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 200)
                    font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                }
                Text {
                    text: islandRoot.pd.artist || ""
                    color: Qt.rgba(1, 1, 1, 0.55)
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 200)
                    visible: text !== ""
                    font { family: "Montserrat"; pixelSize: 11 }
                }
                Row {
                    spacing: 3
                    // the only permanently animating element (off on tier C)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 3
                            height: 14
                            radius: 1.5
                            color: Tokens.accent
                            anchors.bottom: parent.bottom
                            SequentialAnimation on scale {
                                running: Governor.tier !== "C"
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.3; to: 1.0; duration: 380 + index * 90; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 1.0; to: 0.3; duration: 380 + index * 90; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }
        }

        // ── Split compact: two lobes 8 px apart, breathing as one wave ─
        Row {
            anchors.centerIn: parent
            spacing: 8
            opacity: islandRoot.stateName === "split" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            // lobe 1 — higher-priority activity
            Row {
                width: islandRoot.lobeWidth(islandRoot.primary.kind)
                height: Tokens.islandIdleHeight
                spacing: 6

                Item {
                    width: 12
                    height: Tokens.islandIdleHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        visible: islandRoot.primary.kind !== "timer"
                                 && islandRoot.primary.kind !== "charging"
                                 && islandRoot.primary.kind !== "call"
                        source: "qrc:/qml/aegis-mark.png"
                        width: 12
                        height: 12
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible: islandRoot.primary.kind === "call"
                        width: 6
                        height: 6
                        radius: 3
                        color: "#4ADE80"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Canvas {
                        visible: islandRoot.primary.kind === "charging"
                        width: 8
                        height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        onPaint: islandRoot.paintBolt(getContext("2d"), width, height)
                    }
                    Text {
                        visible: islandRoot.primary.kind === "timer"
                        text: "⏱"
                        color: Tokens.accent
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: islandRoot.lobeText(islandRoot.primary)
                    color: Tokens.paper
                    elide: Text.ElideRight
                    width: parent.width - 18
                    font { family: "Montserrat"; pixelSize: 10 }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: 1
                height: Tokens.islandIdleHeight * 0.5
                color: Qt.rgba(1, 1, 1, 0.10)
                anchors.verticalCenter: parent.verticalCenter
            }

            // lobe 2 — second activity
            Row {
                width: islandRoot.lobeWidth(islandRoot.secondary.kind)
                height: Tokens.islandIdleHeight
                spacing: 6

                Item {
                    width: 12
                    height: Tokens.islandIdleHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        visible: islandRoot.secondary.kind !== "timer"
                                 && islandRoot.secondary.kind !== "charging"
                                 && islandRoot.secondary.kind !== "call"
                        source: "qrc:/qml/aegis-mark.png"
                        width: 12
                        height: 12
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible: islandRoot.secondary.kind === "call"
                        width: 6
                        height: 6
                        radius: 3
                        color: "#4ADE80"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Canvas {
                        visible: islandRoot.secondary.kind === "charging"
                        width: 8
                        height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        onPaint: islandRoot.paintBolt(getContext("2d"), width, height)
                    }
                    Text {
                        visible: islandRoot.secondary.kind === "timer"
                        text: "⏱"
                        color: Tokens.accent
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: islandRoot.lobeText(islandRoot.secondary)
                    color: Tokens.paper
                    elide: Text.ElideRight
                    width: parent.width - 18
                    font { family: "Montserrat"; pixelSize: 10 }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Incoming call: 38 px avatar · caller · accept / decline ───
        Row {
            anchors.centerIn: parent
            spacing: 10
            opacity: islandRoot.stateName === "call" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Rectangle {
                width: 38
                height: 38
                radius: 19
                color: Qt.rgba(1, 1, 1, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: islandRoot.pd.initials
                          || (islandRoot.pd.caller || "A").slice(0, 2).toUpperCase()
                    color: Tokens.paper
                    font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                }
            }
            Text {
                text: (islandRoot.pd.caller || "Aegis Meet") + "\nIncoming call"
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 11 }
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: 30; height: 30; radius: 15
                color: "#22C55E"
                anchors.verticalCenter: parent.verticalCenter

                Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 14 }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Activity.respondActivity(islandRoot.primary.id, "accept")
                }
            }
            Rectangle {
                width: 30; height: 30; radius: 15
                color: "#EF4444"
                anchors.verticalCenter: parent.verticalCenter

                Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 13 }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Activity.respondActivity(islandRoot.primary.id, "decline")
                }
            }
        }

        // ── Charging: bolt · 82% · 40 min to full ─────────────────────
        Row {
            anchors.centerIn: parent
            spacing: 7
            opacity: islandRoot.stateName === "charging" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Canvas {
                width: 12
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                onPaint: islandRoot.paintBolt(getContext("2d"), width, height)
            }
            Text {
                text: (islandRoot.pd.percent !== undefined
                       ? islandRoot.pd.percent + "% · "
                       : "")
                      + (islandRoot.pd.minutes !== undefined
                         ? islandRoot.pd.minutes + " min to full"
                         : "Charging")
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 11 }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Timer: label · remaining ─────────────────────────────────
        Row {
            anchors.centerIn: parent
            spacing: 8
            opacity: islandRoot.stateName === "timer" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                               Tokens.accent.b, 0.18)
                border.width: 1.5
                border.color: Tokens.accent
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "⏱"
                    color: "#8FB8FF"
                    font.pixelSize: 11
                }
            }
            Text {
                text: (islandRoot.pd.label || "Timer")
                      + (islandRoot.pd.remaining
                         ? "  ·  " + islandRoot.pd.remaining : "")
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 11; weight: Font.Medium }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Aegis ID: mark · message ─────────────────────────────────
        Row {
            anchors.centerIn: parent
            spacing: 8
            opacity: islandRoot.stateName === "aegisId" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Image {
                source: "qrc:/qml/aegis-mark.png"
                width: 18
                height: 18
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: islandRoot.pd.message || "Aegis ID · Unlocked"
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 11; weight: Font.Medium }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Generic: title · subtitle ────────────────────────────────
        Row {
            anchors.centerIn: parent
            spacing: 10
            opacity: islandRoot.stateName === "generic" ? 1 : 0
            Behavior on opacity { CrossfadeAnim { } }

            Image {
                source: "qrc:/qml/aegis-mark.png"
                width: 16
                height: 16
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: islandRoot.pd.title || ""
                    color: Tokens.paper
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 240)
                    visible: text !== ""
                    font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
                }
                Text {
                    text: islandRoot.pd.subtitle || ""
                    color: Qt.rgba(1, 1, 1, 0.55)
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 240)
                    visible: text !== ""
                    font { family: "Montserrat"; pixelSize: 10 }
                }
            }
        }
    }

    // bolt glyph shared by charging states
    function paintBolt(ctx, w, h) {
        ctx.reset()
        ctx.fillStyle = "#FFD84D"
        ctx.beginPath()
        ctx.moveTo(w * 0.62, 0)
        ctx.lineTo(w * 0.12, h * 0.55)
        ctx.lineTo(w * 0.45, h * 0.55)
        ctx.lineTo(w * 0.34, h)
        ctx.lineTo(w * 0.88, h * 0.42)
        ctx.lineTo(w * 0.54, h * 0.42)
        ctx.closePath()
        ctx.fill()
    }

    // compact one-line text per kind — the split lobes
    function lobeText(act) {
        if (!act)
            return ""
        const d = act.data || {}
        switch (act.kind) {
        case "media":
            return d.title || "Now Playing"
        case "timer":
            return d.remaining || d.label || "Timer"
        case "charging":
            return (d.percent !== undefined ? d.percent + "%" : "")
        case "call":
            return d.caller || "Call"
        case "aegisId":
            return d.message || "Aegis ID"
        default:
            return d.title || "Activity"
        }
    }

    MouseArea {
        anchors.fill: capsule
        cursorShape: Qt.PointingHandCursor
        onClicked: Util.ccOpen = true
    }
}
