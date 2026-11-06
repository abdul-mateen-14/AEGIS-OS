import QtQuick

// Panel Glass — proposal §3 Table 7 (dark rung).
// Layers 2-4: ink tint 52%, hairline border white 14%, 1 px inset top
// highlight. Layer 1 (28 px backdrop blur) is provided by KWin: the shell
// windows ship app_id "aegis-shell" and theme kwinrulesrc forces blur on it.
Rectangle {
    property int cornerRadius: 0
    radius: cornerRadius
    color: Tokens.glassTint
    border.color: Tokens.glassBorder
    border.width: 1

    // 4 · inner top highlight — the light source; makes panels feel lit
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 1
            leftMargin: Math.max(1, parent.cornerRadius)
            rightMargin: Math.max(1, parent.cornerRadius)
        }
        height: 1
        color: Tokens.glassHighlight
    }
}
