import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aegis.Util

// Aegis Calculator — M3 first-party app (proposal §8, plate 12).
//
// The macOS-Calculator grammar on the Aegis anatomy: right-aligned display
// with a running history tape, 4 × 5 key grid (function · number · accent
// rows), full keyboard support (digits, +-*/, Enter, Escape, Backspace).
// The one decision worth writing down: repeated equals repeats the last
// operation — the desktop-calculator contract, not the expression-parser one.
Window {
    id: win

    width: 340; height: 560
    minimumWidth: 300; minimumHeight: 480
    visible: true
    title: "Calculator"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    // ── calculator state ─────────────────────────────────────────────────
    property string display: "0"
    property double accumulator: 0
    property string pendingOp: ""          // + − × ÷
    property bool justEvaluated: false
    property var tape: []                  // [{expr, result}] newest last

    function applyOp(a, b, op) {
        if (op === "+") return a + b
        if (op === "−") return a - b
        if (op === "×") return a * b
        if (op === "÷") return b === 0 ? NaN : a / b
        return b
    }

    function fmt(v) {
        if (isNaN(v)) return "Error"
        if (!isFinite(v)) return "∞"
        // 12 significant digits, no trailing zeros, no exponent spam
        let s = Number(v.toPrecision(12)).toString()
        if (s.length > 14) s = v.toExponential(6)
        return s
    }

    function digit(d) {
        if (display === "Error") display = "0"
        if (justEvaluated) { display = "0"; justEvaluated = false }
        if (display.replace(/[-.]/g, "").length >= 12) return
        display = display === "0" ? d : display + d
    }

    function dot() {
        if (justEvaluated) { display = "0"; justEvaluated = false }
        if (display.indexOf(".") < 0) display += "."
    }

    function clearAll() {
        display = "0"
        accumulator = 0
        pendingOp = ""
        justEvaluated = false
    }

    function backspace() {
        if (justEvaluated || display === "Error") { clearAll(); return }
        display = display.length > 1 ? display.slice(0, -1) : "0"
        if (display === "-") display = "0"
    }

    function negate() {
        if (display !== "0" && display !== "Error")
            display = display.startsWith("-") ? display.slice(1) : "-" + display
    }

    function percent() {
        display = fmt(Number(display) / 100)
    }

    function operatorPressed(op) {
        const v = Number(display)
        if (isNaN(v)) { clearAll(); return }
        if (pendingOp !== "" && !justEvaluated) {
            const r = applyOp(accumulator, v, pendingOp)
            tape.push({ expr: fmt(accumulator) + " " + pendingOp + " " + fmt(v), result: fmt(r) })
            if (tape.length > 4) tape.shift()
            accumulator = r
            display = fmt(r)
        } else {
            accumulator = v
        }
        pendingOp = op
        justEvaluated = true
    }

    function equals() {
        if (pendingOp === "") return
        const v = Number(display)
        const r = applyOp(accumulator, v, pendingOp)
        tape.push({ expr: fmt(accumulator) + " " + pendingOp + " " + fmt(v), result: fmt(r) })
        if (tape.length > 4) tape.shift()
        display = fmt(r)
        accumulator = isNaN(r) ? 0 : r
        justEvaluated = true
    }

    AppWindow {
        id: appBody
        anchors.fill: parent
        title: "Calculator"

        toolbar: [
            Text {
                text: "Basic"
                font { pixelSize: 12; weight: Font.DemiBold }
                color: Tokens.fg
            },
            Text {
                text: "keyboard works too"
                font.pixelSize: 10
                color: Tokens.fgMuted
            },
            Item { Layout.fillWidth: true },
            AbstractButton {
                Layout.preferredHeight: 28; Layout.preferredWidth: 76
                contentItem: Text {
                    text: "Clear tape"
                    font.pixelSize: 11
                    color: Tokens.fgMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    border.color: Tokens.glassBorder
                    color: Util.darkMode ? "#262930" : "#E8ECF4"
                }
                onClicked: win.tape = []
            }
        ]

        // keyboard support on the content area
        FocusScope {
            anchors.fill: parent
            focus: true

            Keys.onPressed: function (event) {
                const k = event.text
                if (k >= "0" && k <= "9") { win.digit(k); event.accepted = true }
                else if (k === "." || k === ",") { win.dot(); event.accepted = true }
                else if (k === "+") { win.operatorPressed("+"); event.accepted = true }
                else if (k === "-") { win.operatorPressed("−"); event.accepted = true }
                else if (k === "*" || k === "x") { win.operatorPressed("×"); event.accepted = true }
                else if (k === "/") { win.operatorPressed("÷"); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { win.equals(); event.accepted = true }
                else if (event.key === Qt.Key_Escape) { win.clearAll(); event.accepted = true }
                else if (event.key === Qt.Key_Backspace) { win.backspace(); event.accepted = true }
                else if (k === "%") { win.percent(); event.accepted = true }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ── display ─────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 172
                    spacing: 4

                    Item { Layout.fillHeight: true; Layout.fillWidth: true }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Repeater {
                            model: win.tape
                            delegate: Text {
                                Layout.fillWidth: true
                                text: modelData.expr + " = " + modelData.result
                                font.pixelSize: 10
                                color: Tokens.fgMuted
                                horizontalAlignment: Text.AlignRight
                                rightPadding: 16
                                opacity: 0.4 + 0.2 * index
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.pendingOp !== ""
                              ? fmt(win.accumulator) + " " + win.pendingOp
                              : ""
                        font.pixelSize: 12
                        color: Tokens.fgMuted
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.display
                        font {
                            family: "Montserrat"
                            weight: Font.DemiBold
                            pixelSize: win.display.length > 9 ? 34 : 48
                        }
                        color: Tokens.fg
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 16
                        bottomPadding: 10
                        elide: Text.ElideLeft
                        maximumLineCount: 1
                    }
                }

                // ── key grid ────────────────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 12
                    Layout.topMargin: 0
                    columns: 4
                    columnSpacing: 8
                    rowSpacing: 8

                    component Key: AbstractButton {
                        id: keyBtn
                        property string label: ""
                        property bool isAccent: false
                        property bool isFunction: false
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentItem: Text {
                            text: keyBtn.label
                            font { family: "Montserrat"; pixelSize: 18; weight: Font.DemiBold }
                            color: keyBtn.isAccent ? "#FFFFFF" : Tokens.fg
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 12
                            color: keyBtn.pressed
                                   ? (keyBtn.isAccent ? Qt.darker(Tokens.accent, 1.15)
                                                      : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.16) : "#DCE2EE"))
                                   : keyBtn.isAccent ? Tokens.accent
                                                     : (keyBtn.isFunction
                                                        ? (Util.darkMode ? Qt.rgba(1, 1, 1, 0.05) : "#E8ECF4")
                                                        : (Util.darkMode ? Qt.rgba(1, 1, 1, 0.10) : "#FFFFFF"))
                            border.width: 1
                            border.color: Tokens.glassBorder
                            opacity: keyBtn.enabled ? 1 : 0.5
                            Behavior on color { ColorAnimation { duration: 90 } }
                        }
                    }

                    Key { label: "C"; isFunction: true; onClicked: win.clearAll() }
                    Key { label: "±"; isFunction: true; onClicked: win.negate() }
                    Key { label: "%"; isFunction: true; onClicked: win.percent() }
                    Key { label: "÷"; isFunction: true; onClicked: win.operatorPressed("÷") }

                    Key { label: "7"; onClicked: win.digit("7") }
                    Key { label: "8"; onClicked: win.digit("8") }
                    Key { label: "9"; onClicked: win.digit("9") }
                    Key { label: "×"; isFunction: true; onClicked: win.operatorPressed("×") }

                    Key { label: "4"; onClicked: win.digit("4") }
                    Key { label: "5"; onClicked: win.digit("5") }
                    Key { label: "6"; onClicked: win.digit("6") }
                    Key { label: "−"; isFunction: true; onClicked: win.operatorPressed("−") }

                    Key { label: "1"; onClicked: win.digit("1") }
                    Key { label: "2"; onClicked: win.digit("2") }
                    Key { label: "3"; onClicked: win.digit("3") }
                    Key { label: "+"; isFunction: true; onClicked: win.operatorPressed("+") }

                    Key {
                        label: "0"
                        Layout.columnSpan: 2
                        onClicked: win.digit("0")
                    }
                    Key { label: "."; onClicked: win.dot() }
                    Key {
                        label: "="
                        isAccent: true
                        onClicked: win.equals()
                    }
                }
            }
        }
    }
}
