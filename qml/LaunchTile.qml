// components/LaunchTiles: 104 x 84, radius-md, hover lifts to surface-3.
// Each pairs a glyph with a word.
import QtQuick
import Kisel.Core

FocusScope {
    id: root
    property string label: ""
    property string icon: ""       // a name from Icon.qml, or "github"
    property color glyph: Theme.kisel
    signal clicked()

    width: 104
    height: 84
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: tap.pressed || hover.hovered ? Theme.surface3 : Theme.surface2
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
        scale: tap.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Theme.tPress } }
        border.width: root.activeFocus ? 3 : 0
        border.color: Theme.kisel

        Column {
            anchors.centerIn: parent
            spacing: Theme.space2
            Item {
                width: 28; height: 28
                anchors.horizontalCenter: parent.horizontalCenter
                Icon { visible: root.icon !== "github"; anchors.centerIn: parent; size: 28; name: root.icon; color: root.glyph }
                GitHubMark { visible: root.icon === "github"; anchors.centerIn: parent; size: 26; color: root.glyph }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.label
                color: hover.hovered ? Theme.ink : Theme.inkMuted
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
            }
        }
    }
    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered) Sfx.play("hover")
    }
    TapHandler { id: tap; onTapped: root.clicked() }
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
