// Toggle: the thumb slides 18 px in 140 ms OutBack, the track recolours in 120 ms.
import QtQuick

FocusScope {
    id: root
    property bool checked: false
    property string label: ""
    signal toggled(bool value)

    implicitWidth: row.implicitWidth
    implicitHeight: 28
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.checked: checked

    Row {
        id: row
        spacing: Theme.space2
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            width: 44; height: 26; radius: 13
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? Theme.kisel : Theme.surface3
            border.width: root.activeFocus ? 2 : 1
            border.color: root.activeFocus ? Theme.kisel : Theme.line
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                y: 3; width: 20; height: 20; radius: 10
                x: root.checked ? 21 : 3
                color: root.checked ? Theme.kiselInk : Theme.ink
                Behavior on x { NumberAnimation { duration: Theme.tFast; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
            }
        }
        Text {
            visible: root.label !== ""
            text: root.label
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    TapHandler { onTapped: { root.checked = !root.checked; root.toggled(root.checked) } }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    Keys.onSpacePressed: { root.checked = !root.checked; root.toggled(root.checked) }
}
