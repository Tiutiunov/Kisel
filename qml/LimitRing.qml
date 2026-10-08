// One of the account's limits as a small ring: how much of it is used, the figure in the
// middle and its name underneath. Green, then lemon from 70 percent, red from 90.
import QtQuick

Item {
    id: root
    property real used: 0      // 0..100
    property string name: ""
    readonly property color tone: used >= 90 ? "#E0405A" : used >= 70 ? "#FFE08A" : "#B9DC6B"
    width: 40; height: name === "" ? 40 : 54

    property real shown: used
    Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    onShownChanged: ring.requestPaint()
    onToneChanged: ring.requestPaint()

    Canvas {
        id: ring
        width: 40; height: 40
        onPaint: {
            const g = getContext("2d"), c = 20, r = 16
            g.reset(); g.lineWidth = 4; g.lineCap = "round"
            g.strokeStyle = "#2b2430"; g.beginPath(); g.arc(c, c, r, 0, Math.PI * 2, false); g.stroke()
            const a = Math.max(0, Math.min(1, root.shown / 100))
            if (a > 0.001) { g.strokeStyle = root.tone; g.beginPath(); g.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * a, false); g.stroke() }
        }
        Text {
            anchors.centerIn: parent
            text: Math.round(root.used)
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
        }
    }
    Text {
        visible: root.name !== ""
        y: 42
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.name
        color: Theme.inkMuted
        font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
    }
}
