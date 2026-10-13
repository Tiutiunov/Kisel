// One choice out of a few, in a single pill: the thumb (kisel, or `accent`) slides under the chosen
// word (140 ms, OutBack) while the words recolour in 100 ms. Left and Right step it.
//   model: [{ id, name }]   current: the chosen id   picked(id)
import QtQuick
import Kisel.Core

FocusScope {
    id: root
    property var model: []
    property string current: ""
    property color accent: Theme.kisel      // the thumb...
    property color accentInk: Theme.kiselInk // ...and the word on it
    signal picked(string id)

    readonly property int index: { for (let i = 0; i < model.length; ++i) if (model[i].id === current) return i; return -1 }
    property int made: 0
    property bool settled: false // the thumb is put where it belongs, not slid there, when first shown
    Component.onCompleted: Qt.callLater(() => settled = true)

    implicitWidth: row.width + 6
    implicitHeight: 32
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTabList

    function step(by) {
        const at = Math.max(0, Math.min(model.length - 1, index + by))
        if (at !== index) picked(model[at].id)
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface3
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? root.accent : Theme.line
    }
    Rectangle {
        id: thumb
        // (`made` counts the cells as the Repeater hands them over: its own count is told a moment too early)
        readonly property Item under: root.made > root.index && root.index >= 0 ? cells.itemAt(root.index) : null
        visible: !!under
        x: under ? under.x + 3 : 3
        y: 3
        width: under ? under.width : 0
        height: 26
        radius: 13
        color: root.accent
        border.width: 1.5; border.color: Theme.edge // a sticker, as the chips in the chat are
        Behavior on x { enabled: root.settled; NumberAnimation { duration: Theme.tFast; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
        Behavior on width { enabled: root.settled; NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic } }
    }
    Row {
        id: row
        x: 3; y: 3
        Repeater {
            id: cells
            model: root.model
            onItemAdded: ++root.made
            onItemRemoved: --root.made
            Item {
                id: cell
                required property var modelData
                readonly property bool on: root.current === modelData.id
                width: word.implicitWidth + 22
                height: 26
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.name
                Accessible.selected: on
                Rectangle { // at rest, under the pointer
                    anchors.fill: parent
                    radius: 13
                    color: Theme.veil
                    opacity: !cell.on && cellHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
                }
                Text {
                    id: word
                    anchors.centerIn: parent
                    text: cell.modelData.name
                    color: cell.on ? root.accentInk : Theme.inkMuted
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
                }
                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { if (!cell.on) { Sfx.play("click"); root.picked(cell.modelData.id) } } }
            }
        }
    }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
}
