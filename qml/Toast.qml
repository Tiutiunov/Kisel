// A pill on surface-3 for 3.5 s; it rises 6 px and fades in over 140 ms, and
// fades out over 140 ms. Call show("text").
import QtQuick

Item {
    id: root
    property string text: ""
    property bool open: false

    width: pill.width
    height: pill.height
    opacity: open ? 1 : 0
    visible: opacity > 0
    y: baseY - (open ? 6 : 0)
    property real baseY: 0
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    Behavior on y { enabled: !Theme.reduced; NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic } }

    function show(message) {
        text = message
        open = true
        hold.restart()
    }
    Timer { id: hold; interval: 3500; onTriggered: root.open = false }

    Rectangle {
        id: pill
        width: label.implicitWidth + 28
        height: 28
        radius: Theme.radiusPill
        color: Theme.surface3
        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
        }
    }
}
