// The code panel: a diff (added lines on diff-add-bg with mint text and a plus,
// removed lines on diff-del-bg with danger text, struck through and a minus)
// or a plain command. Never shortens a path or command the user must judge:
// long lines scroll sideways inside the panel.
import QtQuick
import QtQuick.Controls.Basic as C

Rectangle {
    id: root
    property var lines: []      // [{kind: add|del|ctx, no, text}]
    property string command: "" // text mode, shown after a $ prompt
    property string caption: "" // file path above a diff
    property bool modified: false // an amber "modified" dot pops in next to the file name
    readonly property bool textMode: command !== ""

    radius: Theme.radiusMd
    color: Theme.surface2
    clip: true

    Rectangle {
        // the file tab's amber "modified" dot, popping in with OutBack
        x: parent.width - 20; y: 12
        width: 8; height: 8; radius: 4
        color: Theme.amber
        visible: root.modified && root.caption !== ""
        scale: visible ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
    }
    Column {
        anchors.fill: parent
        anchors.margins: Theme.space2

        Row {
            visible: root.caption !== "" && root.modified
            spacing: 0
        }
        Text {
            visible: root.caption !== ""
            width: parent.width - (root.modified ? 16 : 0)
            text: root.caption
            elide: Text.ElideMiddle
            color: Theme.inkMuted
            font.family: Theme.mono; font.pixelSize: 12
            height: visible ? 20 : 0
        }

        C.ScrollView {
            width: parent.width
            height: parent.height - (root.caption !== "" ? 20 : 0)
            contentWidth: Math.max(availableWidth, body.implicitWidth)
            clip: true
            C.ScrollBar.vertical.policy: C.ScrollBar.AsNeeded

            Item {
                id: body
                implicitWidth: root.textMode ? cmd.implicitWidth : diffCol.implicitWidth
                implicitHeight: root.textMode ? cmd.implicitHeight : diffCol.implicitHeight

                Text {
                    id: cmd
                    visible: root.textMode
                    textFormat: Text.PlainText
                    text: "$ " + root.command
                    color: Theme.ink
                    font.family: Theme.mono; font.pixelSize: 12
                    lineHeight: 17; lineHeightMode: Text.FixedHeight
                    wrapMode: Text.NoWrap
                }
                Column {
                    id: diffCol
                    visible: !root.textMode
                    Repeater {
                        model: root.textMode ? [] : root.lines
                        Rectangle {
                            id: ln
                            required property var modelData
                            required property int index
                            readonly property bool add: modelData.kind === "add"
                            readonly property bool del: modelData.kind === "del"
                            width: Math.max(root.width - 2 * Theme.space2, lineText.implicitWidth + 60)
                            height: 17
                            radius: 4
                            color: add ? Theme.diffAddBg : del ? Theme.diffDelBg : "transparent"
                            // New diff lines fade in over 140 ms, staggered 20 ms apart:
                            // removed lines come first (they are listed first), then added
                            opacity: 0
                            Timer { interval: Math.min(ln.index, 30) * 20; running: true; onTriggered: ln.opacity = 1 }
                            Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                            Row {
                                spacing: 6
                                leftPadding: 4
                                Text { width: 24; text: ln.modelData.no; horizontalAlignment: Text.AlignRight
                                    color: Theme.inkFaint; font.family: Theme.mono; font.pixelSize: 12 }
                                Text { width: 10; text: ln.add ? "+" : ln.del ? "−" : " "
                                    color: ln.add ? Theme.mint : ln.del ? Theme.danger : Theme.inkFaint
                                    font.family: Theme.mono; font.pixelSize: 12 }
                                Text {
                                    id: lineText
                                    textFormat: Text.PlainText
                                    text: ln.modelData.text
                                    color: ln.add ? Theme.mint : ln.del ? Theme.danger : Theme.ink
                                    font.family: Theme.mono; font.pixelSize: 12
                                    font.strikeout: ln.del
                                    opacity: ln.del ? 0.7 : 1
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
