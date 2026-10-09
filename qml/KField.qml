// Single-line input on surface-2. Border line -> 2 px kisel ring on focus.
import QtQuick
import QtQuick.Controls.Basic as C

Rectangle {
    id: root
    property alias text: input.text
    property alias placeholder: input.placeholderText
    property alias echoMode: input.echoMode
    property alias inputFocus: input.activeFocus
    signal accepted()

    implicitHeight: 36
    radius: Theme.radiusMd
    color: Theme.surface2
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Theme.kisel : Theme.line

    C.TextField {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space3
        background: null
        color: Theme.ink
        placeholderTextColor: Theme.inkFaint
        selectionColor: Theme.kisel
        selectedTextColor: Theme.kiselInk
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.DemiBold
        verticalAlignment: TextInput.AlignVCenter
        onAccepted: root.accepted()
    }
}
