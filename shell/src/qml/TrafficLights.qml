import QtQuick

// Table 14 — traffic lights. 3 × 12 px filled circles, hues matched to macOS
// within a tight ΔE; 1 px inset border of the same hue darkened 40%; 8 px gap;
// hover glyph fades in at 80 ms; unfocused all three fall to ink at 30%.
// T6 — hover glyphs use an explicit hue-tinted white per button (same hue,
// S × 0.15, V = 1). The old Qt.lighter(hue, 3.4) clamps HSV value at 1.0 for
// the close/minimize hues and rendered the glyph at the circle's own color —
// invisible. The aurorae theme (gen-aurorae-buttons.py) carries the same
// tints so shell and decorated windows share one glyph semantic.
//
// T15-D10 (W47) — the "calendar traffic lights are not working" report:
// the 12 px circle was a brutal click target, so every light now rides a
// transparent 18×18 hit area (the macOS-sized target) and the grabbing
// MouseArea keeps the titleband DragHandler passive — a click on a light
// can never convert into a window move, and a fast double-click on a
// light is two light clicks, never a maximize. The visible anatomy is
// UNCHANGED: same 12 px circles, same 8 px circle gap (items are 18 wide,
// so the Row spacing drops to 2), same hues.
Row {
    id: root

    property bool focused: true
    signal closeClicked()
    signal minClicked()
    signal maxClicked()

    spacing: 2
    Repeater {
        // Row has no model/delegate of its own — the Repeater provides both.
        model: [
            { hue: "#FF5F57", tint: "#FFE7E6", glyph: "\u00d7", sig: "closeClicked" },
            { hue: "#FEBC2E", tint: "#FFF5E0", glyph: "\u2212", sig: "minClicked" },
            { hue: "#28C840", tint: "#E0FFE5", glyph: "+",     sig: "maxClicked" }
        ]

        delegate: Item {
            width: 18; height: 18

            Rectangle {
                anchors.centerIn: parent
                width: 12; height: 12; radius: 6
                color: root.focused ? modelData.hue : Qt.rgba(0.04, 0.05, 0.06, 0.3)
                border.color: Qt.darker(modelData.hue, 1.4)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font { pixelSize: 9; bold: true }
                    color: modelData.tint
                    opacity: ma.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 80 } }
                }
            }

            // the click target — 18×18, centered on the 12 px dot
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root[modelData.sig]()
            }
        }
    }
}
