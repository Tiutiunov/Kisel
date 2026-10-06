// A number whose digits roll: when the text changes, the old one rolls up and
// out while the new one rolls up in (100 percent of its height, 160 ms).
import QtQuick

Item {
    id: root
    property string text: ""
    property color color: Theme.inkFaint
    property int pixelSize: 11
    property int weight: Font.DemiBold
    property string family: Theme.sans

    implicitWidth: cur.implicitWidth
    implicitHeight: cur.implicitHeight
    width: implicitWidth
    height: implicitHeight
    clip: true

    property string shown: text
    property real roll: 1 // 0 = old text in place, 1 = new text in place
    onTextChanged: {
        if (text === shown) return
        old.text = shown
        shown = text
        if (Theme.reduced) { roll = 1; return }
        roll = 0
        rollAnim.restart()
    }
    NumberAnimation { id: rollAnim; target: root; property: "roll"; to: 1; duration: 160; easing.type: Easing.OutCubic }

    Text {
        id: old
        y: -root.height * root.roll
        opacity: 1 - root.roll
        color: root.color; font.family: root.family; font.pixelSize: root.pixelSize; font.weight: root.weight
    }
    Text {
        id: cur
        y: root.height * (1 - root.roll)
        text: root.shown
        color: root.color; font.family: root.family; font.pixelSize: root.pixelSize; font.weight: root.weight
    }
}
