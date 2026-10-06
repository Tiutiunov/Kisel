// On a side dock the state chip becomes an icon-only 24 px disc under the mascot
// (the same colours, with a glyph inside: bars, dots, "!", check, cross); the text
// appears when the card opens.
import QtQuick

Item {
    id: root
    property string kind: "" // "" | work | think | needs | done | failed
    width: 24; height: 24
    scale: kind !== "" ? 1 : 0
    opacity: kind !== "" ? 1 : 0
    visible: scale > 0.01
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

    property string shown: ""
    onKindChanged: if (kind !== "") shown = kind
    Rectangle {
        anchors.fill: parent; radius: 12
        color: root.shown === "needs" ? Theme.amber : root.shown === "done" ? Theme.mint
             : root.shown === "failed" ? Theme.danger : Theme.info
        Behavior on color { ColorAnimation { duration: 160 } }
        PillBars { visible: root.shown === "work"; running: visible; ink: Theme.surface0; anchors.centerIn: parent; scale: 0.7 }
        PillDots { visible: root.shown === "think"; running: visible; ink: Theme.surface0; anchors.centerIn: parent; scale: 0.7 }
        Text { visible: root.shown === "needs"; anchors.centerIn: parent; text: "!"; color: Theme.surface0
            font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.ExtraBold }
        Icon { visible: root.shown === "done"; anchors.centerIn: parent; size: 14; name: "check"; color: Theme.surface0 }
        Icon { visible: root.shown === "failed"; anchors.centerIn: parent; size: 13; name: "cross"; color: Theme.surface0 }
    }
}
