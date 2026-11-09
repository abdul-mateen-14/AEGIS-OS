import QtQuick

// Table 14 — traffic lights. 3 × 12 px filled circles, hues matched to macOS
// within a tight ΔE; 1 px inset border of the same hue darkened 40%; 8 px gap;
// hover glyph fades in at 80 ms; unfocused all three fall to ink at 30%.
Row {
    id: root

    property bool focused: true
    signal closeClicked()
    signal minClicked()
    signal maxClicked()

    spacing: 8
    Repeater {
        // Row has no model/delegate of its own — the Repeater provides both.
        model: [
            { hue: "#FF5F57", glyph: "\u00d7", sig: "closeClicked" },
            { hue: "#FEBC2E", glyph: "\u2212", sig: "minClicked" },
            { hue: "#28C840", glyph: "+",     sig: "maxClicked" }
        ]

        delegate: Rectangle {
            width: 12; height: 12; radius: 6
            color: root.focused ? modelData.hue : Qt.rgba(0.04, 0.05, 0.06, 0.3)
            border.color: Qt.darker(modelData.hue, 1.4)
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: modelData.glyph
                font { pixelSize: 9; bold: true }
                color: Qt.lighter(modelData.hue, 3.4)
                opacity: ma.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 80 } }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root[modelData.sig]()
            }
        }
    }
}
