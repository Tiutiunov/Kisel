// Chat with Claude. Text shows exactly as it streams (no typewriter). Dropping
// a file puts it above the input as a chip.
import QtQuick
import QtQuick.Controls.Basic as C
import Kisel.Core

Item {
    id: root
    property bool active: false
    property bool dropActive: false
    readonly property bool inputFocus: input.activeFocus

    width: 494
    opacity: active ? 1 : 0
    visible: opacity > 0
    enabled: active
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    // focus the input once the fade ends
    onActiveChanged: if (active) focusTimer.restart()
    Timer { id: focusTimer; interval: Theme.tFast; onTriggered: input.forceActiveFocus() }

    function send() {
        if (input.text.trim() === "" || Chat.busy)
            return
        Sfx.play("send")
        Chat.send(input.text)
        input.text = ""
    }
    Connections {
        target: Chat
        function onReplyFinished() { Sfx.play("receive") }
    }

    // Escape everything, then turn `code` into the mono face and ``` blocks into <pre>.
    function styled(text, mine) {
        let t = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const mono = Theme.mono
        const codeInk = mine ? Theme.onKisel : Theme.inkMuted
        t = t.replace(/```[a-zA-Z0-9_+-]*\n?([\s\S]*?)```/g, (m, code) =>
            "<pre><font face=\"" + mono + "\" color=\"" + codeInk + "\">" + code.replace(/\n+$/, "") + "</font></pre>")
        t = t.replace(/`([^`\n]+)`/g, "<font face=\"" + mono + "\" color=\"" + codeInk + "\">$1</font>")
        return t.replace(/\n/g, "<br>")
    }

    // messages
    ListView {
        id: list
        width: parent.width
        height: composer.y - Theme.space2
        model: Chat.messages
        spacing: Theme.space2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onCountChanged: positionViewAtEnd()
        onContentHeightChanged: if (atYEnd || Chat.busy) positionViewAtEnd()
        C.ScrollBar.vertical: C.ScrollBar { policy: C.ScrollBar.AsNeeded }

        delegate: Item {
            id: msg
            required property string role
            required property string text
            required property string file
            required property string time
            required property int index
            readonly property bool mine: role === "user"
            readonly property bool lastReply: !mine && index === list.count - 1 && !Chat.busy && text !== ""
            width: ListView.view.width
            height: bubble.height + (lastReply ? 18 : 0)

            Text {
                visible: msg.lastReply
                x: 6
                y: bubble.height + 2
                text: "Kisel \u00b7 " + msg.time
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
            Rectangle {
                id: bubble
                // A new bubble rises 8 px while fading in over 140 ms
                x: msg.mine ? parent.width - width - 8 : 0
                width: Math.min(parent.width * 0.86, body.implicitWidth + 24)
                height: body.implicitHeight + (chip.visible ? 28 : 0) + 20
                radius: Theme.radiusMd
                // one corner is squared toward the speaker
                bottomRightRadius: msg.mine ? 4 : Theme.radiusMd
                bottomLeftRadius: msg.mine ? Theme.radiusMd : 4
                color: msg.mine ? Theme.kisel : Theme.surface2
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic } }

                Column {
                    x: 12; y: 10
                    width: parent.width - 24
                    spacing: 4
                    Rectangle {
                        id: chip
                        visible: msg.file !== ""
                        height: 24; width: chipText.implicitWidth + 32; radius: 12
                        color: Qt.rgba(0, 0, 0, 0.18)
                        Row { anchors.centerIn: parent; spacing: 4
                            Icon { name: "clip"; size: 14; color: msg.mine ? Theme.onKisel : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                            Text { id: chipText; text: msg.file; color: msg.mine ? Theme.onKisel : Theme.ink
                                font.family: Theme.mono; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    JellyTrio {
                        // before the first token: the waiting loader, not a bare ellipsis
                        visible: msg.text === "" && !msg.mine
                        running: visible && Chat.busy
                        height: visible ? 16 : 0
                        width: 120
                    }
                    Text {
                        id: body
                        visible: msg.text !== ""
                        width: parent.width
                        // Model output is untrusted: it is escaped first, then only
                        // `code` and ``` blocks become our own font tags. No links.
                        text: msg.text === "" ? "" : root.styled(msg.text, msg.mine)
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        color: msg.mine ? Theme.onKisel : Theme.ink
                        font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                        lineHeight: 18; lineHeightMode: Text.FixedHeight
                    }
                }
            }
        }

        // empty chat: ready and listening
        Column {
            visible: list.count === 0
            anchors.centerIn: parent
            spacing: Theme.space3
            DotWave { anchors.horizontalCenter: parent.horizontalCenter; running: root.active && list.count === 0 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ask Claude anything"
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
            }
        }
    }

    // composer
    Column {
        id: composer
        y: parent.height - height
        width: parent.width
        spacing: Theme.space1

        Rectangle { // error line on diff-del-bg
            visible: Chat.error !== ""
            width: parent.width; height: 26; radius: Theme.radiusSm
            color: Theme.diffDelBg
            Row { x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.space1
                Icon { name: "cross"; size: 14; color: Theme.danger; anchors.verticalCenter: parent.verticalCenter }
                Text { width: 440; elide: Text.ElideRight; text: Chat.error; color: Theme.danger
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
        }
        Row {
            spacing: Theme.space2
            Text { text: Chat.model; color: Theme.inkFaint; font.family: Theme.mono; font.pixelSize: 11 }
            Rectangle {
                visible: Chat.attachedName !== ""
                height: 20; width: attach.implicitWidth + 36; radius: 10; color: Theme.surface3
                Row { anchors.centerIn: parent; spacing: 4
                    Icon { name: "clip"; size: 12; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: attach; text: Chat.attachedName; color: Theme.ink; font.family: Theme.mono; font.pixelSize: 11 }
                    Icon { name: "cross"; size: 12; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter
                        TapHandler { onTapped: Chat.detach() } }
                }
            }
        }
        Rectangle {
            width: parent.width
            // grows with its text in 100 ms, up to 110 px
            height: Math.min(110, Math.max(40, input.contentHeight + 22))
            Behavior on height { NumberAnimation { duration: 100 } }
            radius: Theme.radiusMd
            color: Theme.surface2
            border.width: input.activeFocus ? 2 : 1
            border.color: input.activeFocus ? Theme.kisel : Theme.line

            C.ScrollView {
                anchors { left: parent.left; right: sendBtn.left; top: parent.top; bottom: parent.bottom; margins: 4; leftMargin: 8 }
                C.TextArea {
                    id: input
                    placeholderText: "Message Claude"
                    placeholderTextColor: Theme.inkFaint
                    wrapMode: TextEdit.Wrap
                    color: Theme.ink
                    selectionColor: Theme.kisel
                    selectedTextColor: Theme.onKisel
                    font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    background: null
                    Keys.onPressed: (e) => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                            root.send()
                            e.accepted = true
                        }
                    }
                }
            }
            Rectangle {
                id: sendBtn
                width: 32; height: 32; radius: 16
                anchors { right: parent.right; rightMargin: 4; bottom: parent.bottom; bottomMargin: 4 }
                color: Chat.busy ? Theme.surface3 : (sendTap.pressed ? Theme.kiselDeep : Theme.kisel)
                scale: sendTap.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: Theme.tPress } }
                Accessible.role: Accessible.Button
                Accessible.name: Chat.busy ? "Stop" : "Send"
                Icon { anchors.centerIn: parent; size: 18; name: Chat.busy ? "cross" : "send"; color: Chat.busy ? Theme.ink : Theme.onKisel }
                TapHandler { id: sendTap; onTapped: Chat.busy ? Chat.cancel() : root.send() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }

    // drop overlay: dark, 2 px kisel outline, one line of text
    Rectangle {
        anchors.fill: parent
        anchors.margins: -8
        radius: Theme.radiusMd
        color: Qt.rgba(0.055, 0.043, 0.051, 0.88)
        border.width: 2
        border.color: Theme.kisel
        opacity: root.dropActive ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
        Column {
            anchors.centerIn: parent
            spacing: Theme.space3
            DotWave { anchors.horizontalCenter: parent.horizontalCenter; drop: true; running: root.dropActive }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Drop the file on me"
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.ExtraBold
            }
        }
    }
}
