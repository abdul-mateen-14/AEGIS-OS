import QtQuick
import Aegis.Util

// Dynamic Island — the system's live-activity capsule (§2.4, Table 5b).
//
// The one opaque instrument in the shell: an ink capsule (#101216 → #08090C,
// hairline white 14%) hanging flush from the panel's bottom edge, dead
// center. Radius tracks height (r = h/2, capped 32) so the capsule never
// pinches. Morph spring: mass 1 · stiffness 420 · damping 28 (the Apple
// "boing" — about 4% overshoot, settled in ~450 ms); content crossfades
// 140 ms starting 90 ms into the move.
//
// v1.4: the idle capsule is the iPhone Pro-class pill, 104×32 px
// (was 148×30 in the proposal) — Tokens.islandIdleWidth/Height.
//
// M1 ships the geometry engine + click-cycling demo; the Live Activity API
// applications publish through (media, calls, charging, Aegis ID) lands in
// M2. Priority stack — call > Aegis ID > timer > media > charging — is
// enforced by the queue in Control Center (Table 5b: two lobes is the
// ceiling, everything else queues).
Window {
    objectName: "islandWindow"
    visible: false
    color: "transparent"
    width: 420
    height: 140
    flags: Qt.FramelessWindowHint

    id: islandRoot

    property string stateName: "idle"
    property var geo: Tokens.islandStates[stateName] || Tokens.islandStates.idle
    property var demoCycle: ["idle", "nowPlaying", "split", "call", "charging", "aegisId"]

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

    function nextState() {
        var i = demoCycle.indexOf(stateName)
        stateName = demoCycle[(i + 1) % demoCycle.length]
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
                    GradientStop { position: 0; color: "#5A9BFF" }
                    GradientStop { position: 1; color: "#1E3E8C" }
                }
                Image {
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
                    text: "Aurora Drift"
                    color: Tokens.paper
                    font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                }
                Text {
                    text: "Aegis Sound · EP 01"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font { family: "Montserrat"; pixelSize: 10.5 }
                }
                Row {
                    spacing: 3
                    // the only permanently animating element (off on tier C, M2)
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

            Row {
                width: 128
                height: Tokens.islandIdleHeight
                spacing: 6
                Image {
                    source: "qrc:/qml/aegis-mark.png"
                    width: 12
                    height: 12
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Now Playing"
                    color: Tokens.paper
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
            Row {
                width: 104
                height: Tokens.islandIdleHeight
                spacing: 5
                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    color: "#4ADE80"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "12:34"
                    color: Tokens.paper
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
                    text: "AM"
                    color: Tokens.paper
                    font { family: "Montserrat"; pixelSize: 13; weight: Font.DemiBold }
                }
            }
            Text {
                text: "Aegis Meet\nIncoming call"
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 10.5 }
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: 30; height: 30; radius: 15
                color: "#22C55E"
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 14 }
            }
            Rectangle {
                width: 30; height: 30; radius: 15
                color: "#EF4444"
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 13 }
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
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = "#FFD84D"
                    ctx.beginPath()
                    ctx.moveTo(width * 0.62, 0)
                    ctx.lineTo(width * 0.12, height * 0.55)
                    ctx.lineTo(width * 0.45, height * 0.55)
                    ctx.lineTo(width * 0.34, height)
                    ctx.lineTo(width * 0.88, height * 0.42)
                    ctx.lineTo(width * 0.54, height * 0.42)
                    ctx.closePath()
                    ctx.fill()
                }
            }
            Text {
                text: "82% · 40 min to full"
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 11 }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Aegis ID: mark · "Unlocked" ───────────────────────────────
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
                text: "Aegis ID · Unlocked"
                color: Tokens.paper
                font { family: "Montserrat"; pixelSize: 11; weight: Font.Medium }
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    MouseArea {
        anchors.fill: capsule
        cursorShape: Qt.PointingHandCursor
        onClicked: islandRoot.nextState()
    }
}
