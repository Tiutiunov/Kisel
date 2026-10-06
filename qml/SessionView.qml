// Session: the steps Claude took (left), the file it is changing (right) and
// the last command. Pending steps are dim, the running one shows a spinner.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    readonly property var s: Hub.session

    width: 494
    opacity: active ? 1 : 0
    visible: opacity > 0
    enabled: active
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

    // steps
    Column {
        id: steps
        width: 190
        spacing: Theme.space1
        Text {
            width: parent.width
            text: root.s.prompt ? root.s.prompt : "No prompt yet"
            elide: Text.ElideRight
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
        }
        Repeater {
            model: root.s.steps || []
            Row {
                id: step
                required property var modelData
                readonly property bool running: modelData.state === "running"
                spacing: Theme.space2
                height: 22
                Item {
                    width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                    Spinner { anchors.fill: parent; visible: step.running }
                    DrawnCheck { // the check draws itself in 180 ms
                        anchors.centerIn: parent; size: 16; color: Theme.kisel
                        progress: step.modelData.state === "done" ? 1 : 0
                        Behavior on progress { NumberAnimation { duration: 180 } }
                    }
                    Icon { anchors.centerIn: parent; size: 14; name: "cross"; color: Theme.danger; visible: step.modelData.state === "failed" }
                }
                Text {
                    width: 190 - 24
                    text: step.modelData.text
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: step.running ? Theme.ink : Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 13
                    font.weight: step.running ? Font.ExtraBold : Font.DemiBold
                }
            }
        }
    }

    // code panel
    CodePanel {
        x: 202
        width: parent.width - 202
        height: terminal.visible ? parent.height - 48 : parent.height
        lines: root.s.diff || []
        modified: !!root.s.file && (root.s.added > 0 || root.s.removed > 0)
        caption: root.s.file ? root.s.file + (root.s.added || root.s.removed ? "   +" + root.s.added + " −" + root.s.removed : "") : ""
        visible: !!root.s.file
    }
    Text {
        x: 202
        visible: !root.s.file
        text: "Nothing changed yet"
        color: Theme.inkFaint
        font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
    }

    // terminal: the command, separated by a hairline
    Item {
        id: terminal
        visible: !!root.s.command
        x: 202
        y: parent.height - 40
        width: parent.width - 202
        height: 40
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Row {
            y: 10
            spacing: Theme.space2
            Icon { name: "terminal"; size: 16; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
            Text {
                width: terminal.width - 28
                text: root.s.command || ""
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.mono; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
