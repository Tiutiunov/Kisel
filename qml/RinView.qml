// Rin's Home: the notifications that came last. It takes the whole of Home's place
// (494 x 138), in the sticker style of Teto's monitor and in Rin's orange.
//
// A list of the newest few, newest on top: a dot for one not looked at yet, the program,
// how long ago. A click on a row brings that program up. What a notification says is
// shown only when the "Show text" key is on (it is off until pressed: see Notices); it
// is plain text, one line, cut where the row ends.
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    readonly property color orange: "#FFB13B"
    readonly property color lemon: "#FFE08A"
    readonly property var list: Notes.recent

    // how long ago, in a word; `tick` moves it on while the card is open
    property double tick: Date.now()
    Timer { interval: 20000; repeat: true; running: root.visible; onTriggered: root.tick = Date.now() }
    onVisibleChanged: if (visible) tick = Date.now()
    function ago(at) {
        const s = Math.max(0, (Math.max(root.tick, Date.now() - 1000) - at) / 1000)
        return s < 60 ? Tr.t("now") : s < 3600 ? Math.floor(s / 60) + Tr.t(" min") : s < 86400 ? Math.floor(s / 3600) + Tr.t(" h") : Math.floor(s / 86400) + Tr.t(" d")
    }

    Row {
        x: 8; y: 12
        spacing: 6
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        Spark { anchors.verticalCenter: parent.verticalCenter; size: 11; tint: root.orange
            RotationAnimation on rotation { running: root.visible && !Theme.reduced; from: 0; to: 90; duration: 3000; loops: Animation.Infinite } }
        Text {
            text: Tr.t("The latest notifications")
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
        }
    }

    // the key: what they say, shown or not
    Rectangle {
        id: wordsKey
        x: root.width - width - 6; y: 8
        width: wordsLabel.implicitWidth + 20; height: 22
        radius: 11
        color: Qt.rgba(root.orange.r, root.orange.g, root.orange.b, wordsTap.pressed ? 0.5 : Notes.words ? 0.34 : wordsHover.hovered ? 0.24 : 0.12)
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
        border.width: wordsKey.activeFocus ? 2 : 1
        border.color: Qt.rgba(root.orange.r, root.orange.g, root.orange.b, Notes.words ? 1 : 0.5)
        opacity: Motion.rise(root.age, 0)
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: wordsLabel.text
        Text {
            id: wordsLabel
            anchors.centerIn: parent
            text: Notes.words ? Tr.t("Hide text") : Tr.t("Show text")
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
        HoverHandler { id: wordsHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Sfx.play("hover") }
        TapHandler { id: wordsTap; onTapped: wordsKey.flip() }
        Keys.onReturnPressed: flip()
        Keys.onSpacePressed: flip()
        function flip() { Sfx.play("click"); Prefs.noteWords = !Prefs.noteWords }
    }

    ListView {
        id: rows
        x: 8; y: 36
        width: root.width - 14
        height: 96
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        visible: root.list.length > 0
        opacity: Motion.rise(root.age, 1)
        transform: Translate { y: Motion.lift(root.age, 1) }
        model: root.list
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: rows.width
            height: 30
            radius: 10
            color: rowTap.pressed || rowHover.hovered ? "#3a3142" : "#2b2430"
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            Rectangle { // not looked at yet
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: row.modelData.fresh ? root.orange : "#5a5262"
            }
            Text {
                id: appName
                x: 26
                width: Math.min(implicitWidth, 120)
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.app
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.lemon
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
            }
            Text {
                x: appName.x + appName.width + 8
                width: when.x - x - 8
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: row.modelData.title !== "" && row.modelData.text !== "" ? row.modelData.title + ": " + row.modelData.text
                    : row.modelData.title + row.modelData.text
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
            Text {
                id: when
                x: row.width - width - 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.ago(row.modelData.at)
                color: Theme.inkMuted
                font.family: Theme.mono; font.pixelSize: 10
            }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: rowTap; onTapped: { Sfx.play("click"); Notes.openRecent(row.index) } }
        }
    }

    // nothing has come yet: what Rin makes of that
    Rectangle {
        visible: root.list.length === 0
        x: 8; y: 44
        width: root.width - 14
        height: 42
        radius: 12
        color: Qt.rgba(root.orange.r, root.orange.g, root.orange.b, 0.14)
        border.width: 2
        border.color: Qt.rgba(root.orange.r, root.orange.g, root.orange.b, 0.45)
        opacity: Motion.rise(root.age, 1)
        transform: Translate { y: Motion.lift(root.age, 1) }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            verticalAlignment: Text.AlignVCenter
            text: Tr.t("Nothing yet! I will shout the moment something comes.")
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
        }
    }
}
