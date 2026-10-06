// The collapsed pill's state chip (components/CollapsedPill): amber "Needs you",
// mint "Done", danger "Failed". 24 px high, pill radius, surface-0 text; it pops
// in with 220 ms OutBack. The chip and the label carry the status, never colour alone.
import QtQuick

Item {
    id: root
    property string kind: "" // needs | done | failed | ""

    // keep the last word while the chip scales away
    property string shownKind: ""
    onKindChanged: { if (kind !== "") shownKind = kind }
    Component.onCompleted: shownKind = kind

    readonly property bool on: kind !== ""
    implicitWidth: on ? label.implicitWidth + 24 : 0
    implicitHeight: 24
    width: implicitWidth
    height: 24
    visible: scale > 0.01
    scale: on ? 1 : 0
    opacity: on ? 1 : 0
    transformOrigin: Item.Left
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.shownKind === "needs" ? Theme.amber : root.shownKind === "done" ? Theme.mint : Theme.danger
        Behavior on color { ColorAnimation { duration: 160 } }
        Text {
            id: label
            anchors.centerIn: parent
            text: root.shownKind === "needs" ? "Needs you" : root.shownKind === "done" ? "Done" : "Failed"
            color: Theme.surface0
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
        }
    }
}
