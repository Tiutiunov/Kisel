// Chat with Claude. Text shows exactly as it streams (no typewriter). Dropping
// a file puts it above the input as a chip.
//
// The room is dressed for whoever is on stage (`who`): her colour is in the glow behind
// the messages, the sparkles, your bubbles, the edge of Claude's, the composer and the
// send button, and she sits in the empty chat waiting. Changing her changes the room.
import QtQuick
import QtQuick.Controls.Basic as C
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    property bool dropActive: false
    readonly property bool inputFocus: input.activeFocus

    // a: her colour. d: its deeper shade. on: text on it.
    property string who: "miku"
    readonly property var palettes: ({
        miku:  { name: "Miku",     a: "#39C5BB", d: "#22968E", on: "#04302c" },
        rin:   { name: "Rin",      a: "#FFD24A", d: "#E0A92E", on: "#3d2c00" },
        luka:  { name: "Luka",     a: "#F5A3C0", d: "#D9779D", on: "#4a1630" },
        zunda: { name: "Zundamon", a: "#B9DC6B", d: "#86B93F", on: "#24330a" },
        teto:  { name: "Teto",     a: "#E0405A", d: "#B02A44", on: "#FFFFFF" }
    })
    readonly property var pal: palettes[who] || palettes.miku
    readonly property color acc: pal.a
    readonly property color accDeep: pal.d
    readonly property color onAcc: pal.on
    function tinted(a) { return Qt.rgba(acc.r, acc.g, acc.b, a) }
    readonly property color wash: Qt.tint(Theme.surface2, tinted(0.1))

    width: 494
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
        const codeInk = mine ? root.onAcc : Theme.inkMuted
        t = t.replace(/```[a-zA-Z0-9_+-]*\n?([\s\S]*?)```/g, (m, code) =>
            "<pre><font face=\"" + mono + "\" color=\"" + codeInk + "\">" + code.replace(/\n+$/, "") + "</font></pre>")
        t = t.replace(/`([^`\n]+)`/g, "<font face=\"" + mono + "\" color=\"" + codeInk + "\">$1</font>")
        return t.replace(/\n/g, "<br>")
    }

    // her colour in the room: a soft glow in two corners (rings of it, each fainter and
    // wider, so there is no edge to see), and sparkles that turn slowly
    Repeater {
        model: 44
        Rectangle {
            required property int index
            readonly property bool low: index >= 22
            readonly property real r: 30 + (index % 22) * 11
            x: (low ? root.width - 30 : 30) - r
            y: (low ? root.height - 40 : 10) - r
            width: 2 * r; height: 2 * r; radius: r
            color: root.tinted(low ? 0.008 : 0.011)
        }
    }
    Repeater {
        model: [{ x: 18, y: 22, s: 12 }, { x: 452, y: 44, s: 9 }, { x: 398, y: 196, s: 14 }, { x: 60, y: 232, s: 8 }, { x: 250, y: 96, s: 7 }]
        Spark {
            id: mote
            required property var modelData
            required property int index
            x: modelData.x; y: modelData.y
            size: modelData.s
            tint: index % 2 ? "#FFFFFF" : root.acc
            opacity: list.count === 0 ? 0.55 : 0.16
            Behavior on opacity { NumberAnimation { duration: 400 } }
            SequentialAnimation on scale {
                running: root.active && !Theme.reduced
                loops: Animation.Infinite
                PauseAnimation { duration: mote.index * 330 }
                NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.1; duration: 700; easing.type: Easing.OutBack }
                PauseAnimation { duration: 1200 }
            }
            RotationAnimation on rotation { running: root.active && !Theme.reduced; from: 0; to: 90; duration: 6000 + mote.index * 900; loops: Animation.Infinite }
        }
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

            Rectangle { visible: msg.lastReply; x: 6; y: bubble.height + 7; width: 6; height: 6; radius: 3; color: root.acc }
            Text {
                visible: msg.lastReply
                x: 17
                y: bubble.height + 2
                text: root.pal.name + " \u00b7 " + msg.time
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
                // yours is in her colour; Claude's is the surface with a breath of it and her edge
                color: msg.mine ? root.acc : root.wash
                gradient: msg.mine ? mineShade : null
                border.width: msg.mine ? 0 : 1
                border.color: root.tinted(0.3)
                Gradient {
                    id: mineShade
                    GradientStop { position: 0; color: root.acc }
                    GradientStop { position: 1; color: root.accDeep }
                }
                // a new bubble rises 8 px while fading in over 140 ms (OutCubic)
                property real appear: Theme.reduced ? 1 : 0
                opacity: appear
                transform: Translate { y: (1 - bubble.appear) * 8 }
                NumberAnimation on appear { to: 1; duration: Theme.tFast; easing.type: Easing.OutCubic; running: !Theme.reduced }

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
                            Icon { name: "clip"; size: 14; color: msg.mine ? root.onAcc : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                            Text { id: chipText; text: msg.file; color: msg.mine ? root.onAcc : Theme.ink
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
                        color: msg.mine ? root.onAcc : Theme.ink
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
            spacing: Theme.space2
            // she waits here, in a ring of her colour
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76; height: 76
                Rectangle { anchors.fill: parent; radius: 38; color: root.tinted(0.14); border.width: 2; border.color: root.tinted(0.5) }
                Mascot {
                    anchors.centerIn: parent
                    size: 44
                    character: root.who
                    bench: true
                    paused: !(root.active && list.count === 0)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ask Claude anything"
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.pal.name + " is listening"
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
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
            Rectangle {
                height: 20; width: modelName.implicitWidth + 18; radius: 10
                color: root.tinted(0.14)
                Text { id: modelName; anchors.centerIn: parent; text: Chat.model; color: Theme.inkMuted; font.family: Theme.mono; font.pixelSize: 11 }
            }
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
            radius: 20
            color: root.wash
            border.width: input.activeFocus ? 2 : 1
            border.color: input.activeFocus ? root.acc : root.tinted(0.3)
            Rectangle { // a halo in her colour while you type
                anchors.fill: parent; anchors.margins: -4
                z: -1
                radius: 24
                color: root.tinted(0.18)
                opacity: input.activeFocus ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            C.ScrollView {
                anchors { left: parent.left; right: sendBtn.left; top: parent.top; bottom: parent.bottom; margins: 4; leftMargin: 12 }
                C.TextArea {
                    id: input
                    placeholderText: "Message Claude"
                    placeholderTextColor: Theme.inkFaint
                    wrapMode: TextEdit.Wrap
                    color: Theme.ink
                    selectionColor: root.acc
                    selectedTextColor: root.onAcc
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
                color: Chat.busy ? Theme.surface3 : (sendTap.pressed ? root.accDeep : root.acc)
                border.width: Chat.busy ? 0 : 2
                border.color: "#FFFFFF"
                scale: sendTap.pressed ? 0.9 : sendHover.hovered ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Accessible.role: Accessible.Button
                Accessible.name: Chat.busy ? "Stop" : "Send"
                Icon { anchors.centerIn: parent; size: 18; name: Chat.busy ? "cross" : "send"; color: Chat.busy ? Theme.ink : root.onAcc }
                TapHandler { id: sendTap; onTapped: Chat.busy ? Chat.cancel() : root.send() }
                HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
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
        border.color: root.acc
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
