// Home. Miku's is Claude Code's, in the sticker style of the others and in her teal: a
// round light with how many sessions there are and what they are doing, two keys (the
// chat and GitHub), the newest session with its last line, and a line from Miku herself.
// Beside her line is a key: Connect while Claude Code is not connected, Open when there
// is a session to look at. Zundamon's, Teto's and Luka's Homes dissolve in over it.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    signal go(string view)

    readonly property var s: Hub.session
    // The first-launch assembly reveals the real elements one by one as the
    // flying shapes become them (1 = shown, the normal state).
    property real revealCard: 1
    property real revealButton: 1
    property var revealTiles: [1, 1, 1, 1]
    // Where the shapes should land, in this view's coordinates.
    readonly property rect hookRect: Qt.rect(218, 32, 270, 38)
    readonly property rect buttonRect: Qt.rect(426, 82, 62, 42)
    readonly property var tileRects: [Qt.rect(98, 14, 104, 48), Qt.rect(98, 70, 104, 48)]
    readonly property bool hasSession: !!s.id
    // Home belongs to whoever is chosen. Miku's is this one, Claude Code's; Zundamon's is her
    // Spotify player. The ones with no service of their own yet show Claude's.
    property string own: "" // whose Home this is, says the island: "" (Claude's) | zunda | teto | luka
    readonly property bool ownHome: own !== ""
    // (the one last shown stays through the dissolve back to Claude's)
    property string shownOwn: ""
    onOwnChanged: if (own !== "") shownOwn = own
    // one Home dissolves into the other: Claude's goes first, hers follows
    property real ownU: ownHome ? 1 : 0
    Behavior on ownU { NumberAnimation { duration: Theme.reduced ? 140 : 320; easing.type: Easing.InOutCubic } }
    readonly property real claudeU: Math.max(0, 1 - ownU * 2)

    width: 494

    Repeater { id: counter; model: Hub.sessions; delegate: Item {} } // only counts

    readonly property color teal: "#39C5BB"
    readonly property color deep: "#22968E"
    readonly property string st: hasSession ? (s.state || "idle") : ""
    readonly property bool busy: st === "work" || st === "think"
    readonly property color stTint: busy ? root.teal : st === "alert" ? "#FFE08A" : st === "done" ? "#B9DC6B"
        : st === "failed" ? "#E0405A" : Qt.rgba(root.teal.r, root.teal.g, root.teal.b, 0.45)
    readonly property string stWord: !Hooks.installed ? "Not connected" : !hasSession ? "Listening"
        : st === "work" ? "Working" : st === "think" ? "Thinking" : st === "alert" ? "Needs you"
        : st === "done" ? "Done" : st === "failed" ? "Failed" : "Idle"
    readonly property string line: !Hooks.installed ? "Claude Code is not connected yet. Shall we fix that?"
        : !Hub.serverUp ? "I cannot listen for hooks right now. Sorry!"
        : !hasSession ? "Ready and listening. Start a session and I will watch it."
        : st === "think" ? "Thinking it over. Give it a moment."
        : st === "work" ? "Working on it. I will tell you when it is done."
        : st === "alert" ? "Claude needs you. Have a look?"
        : st === "done" ? "All done! Come and see."
        : st === "failed" ? "That one went wrong. Want to see why?"
        : "Nothing is running. I am right here."

    // ---- Miku's Home: Claude Code ----
    Item {
        id: claude
        anchors.fill: parent
        visible: root.claudeU > 0
        opacity: root.claudeU

        Row {
            id: left
            x: 8; y: 12
            spacing: 12

            // the light: how many sessions, and a ring that turns while one is busy
            Item {
                width: 78; height: 114
                opacity: Motion.rise(root.age, 0)
                transform: Translate { y: Motion.lift(root.age, 0) }
                Canvas {
                    id: ring
                    width: 78; height: 78
                    property real turn: 0
                    NumberAnimation on turn {
                        running: root.active && root.busy && claude.visible && !Theme.reduced
                        from: 0; to: 1; duration: 1400; loops: Animation.Infinite
                    }
                    onTurnChanged: requestPaint()
                    property color tint: root.stTint
                    Behavior on tint { ColorAnimation { duration: 300 } }
                    onTintChanged: requestPaint()
                    property bool busy: root.busy
                    onBusyChanged: requestPaint()
                    onPaint: {
                        const g = getContext("2d"), c = 39
                        g.reset()
                        g.lineCap = "round"
                        g.strokeStyle = "#FFFFFF"; g.lineWidth = 12
                        g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                        g.strokeStyle = "#2b2430"; g.lineWidth = 8
                        g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                        g.strokeStyle = tint; g.lineWidth = 8
                        const from = -Math.PI / 2 + 2 * Math.PI * turn
                        g.beginPath(); g.arc(c, c, 31, from, from + (busy ? 0.7 * Math.PI : 2 * Math.PI), false); g.stroke()
                    }
                }
                Text {
                    anchors.horizontalCenter: ring.horizontalCenter
                    anchors.verticalCenter: ring.verticalCenter
                    text: !Hooks.installed ? "off" : counter.count
                    color: Theme.ink
                    font.family: Theme.display; font.pixelSize: 19; font.weight: Font.Bold
                }
                Text {
                    y: 82
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: counter.count === 1 ? "Session" : "Sessions"
                    color: Theme.ink
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
                }
                Text {
                    y: 98
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.stWord
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.DemiBold
                }
            }

            // the two keys
            Column {
                y: 2
                spacing: 8
                Key1 {
                    over: "Claude"; label: "Chat"; icon: "chat"
                    opacity: root.revealTiles[0] * Motion.rise(root.age, 1)
                    transform: Translate { y: Motion.lift(root.age, 1) }
                    onClicked: root.go("chat")
                }
                Key1 {
                    over: "Repos"; label: "GitHub"; icon: "github"
                    opacity: root.revealTiles[1] * Motion.rise(root.age, 2)
                    transform: Translate { y: Motion.lift(root.age, 2) }
                    onClicked: root.go("github")
                }
            }
        }

        Item {
            id: side
            x: left.x + left.width + 16
            y: 12
            width: parent.width - x - 6
            height: parent.height - 24

            Row {
                spacing: 6
                opacity: Motion.rise(root.age, 1)
                transform: Translate { y: Motion.lift(root.age, 1) }
                Spark { anchors.verticalCenter: parent.verticalCenter; size: 11; tint: root.teal
                    RotationAnimation on rotation { running: root.active && claude.visible && !Theme.reduced; from: 0; to: 90; duration: 3000; loops: Animation.Infinite } }
                Text {
                    width: Math.min(implicitWidth, side.width - 17)
                    elide: Text.ElideRight
                    text: root.hasSession ? root.s.name + (counter.count > 1 ? "  +" + (counter.count - 1) : "") : "Claude Code"
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                }
            }

            // the newest session's last line (or the dots: ready and listening)
            Rectangle {
                id: strip
                y: 20
                width: side.width
                height: 38
                radius: 12
                color: stripTap.pressed || stripHover.hovered && root.hasSession ? "#3a3142" : "#2b2430"
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                opacity: root.revealCard * Motion.rise(root.age, 2)
                transform: Translate { y: Motion.lift(root.age, 2) }
                Item {
                    x: 10
                    width: 24; height: parent.height
                    Item {
                        visible: !root.hasSession
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54; height: 22
                        scale: 0.42; transformOrigin: Item.Left
                        // hooks installed but nothing heard yet: the first connection takes the jelly trio
                        JellyTrio { scale: 0.5; transformOrigin: Item.Left; running: root.active && claude.visible && !root.hasSession && Hooks.installed && !Prefs.hookSeen }
                        DotWave { running: root.active && claude.visible && !root.hasSession && !(Hooks.installed && !Prefs.hookSeen); opacity: running ? 1 : 0 }
                    }
                    Item {
                        visible: root.hasSession
                        anchors.centerIn: parent
                        width: 16; height: 16
                        Spinner { anchors.fill: parent; visible: root.busy }
                        DrawnCheck { anchors.centerIn: parent; size: 16; color: "#B9DC6B"; visible: root.st === "done" }
                        Icon { anchors.centerIn: parent; size: 14; name: "cross"; color: "#FF8FA0"; visible: root.st === "failed" }
                        Icon { anchors.centerIn: parent; size: 15; name: "bell"; color: "#FFE08A"; visible: root.st === "alert" }
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#8a8292"; visible: root.st === "idle" }
                    }
                }
                Text {
                    x: 42
                    width: parent.width - x - 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasSession ? (root.s.line || root.s.cwd || "") : Hooks.installed ? "waiting for a session" : "not connected"
                    elide: Text.ElideRight
                    color: "#F2ECF5"
                    opacity: root.hasSession ? 1 : 0.6
                    font.family: Theme.mono; font.pixelSize: 11
                }
                HoverHandler { id: stripHover; cursorShape: root.hasSession ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { id: stripTap; enabled: root.hasSession; onTapped: root.go("session") }
            }

            // what Miku makes of it
            Rectangle {
                y: 70
                width: side.width - (key.visible ? key.width + 6 : 0)
                height: 42
                radius: 12
                readonly property color tone: root.st === "failed" ? "#E0405A" : root.st === "alert" ? "#FFE08A" : root.teal
                readonly property bool loud: root.st === "failed" || root.st === "alert"
                color: Qt.rgba(tone.r, tone.g, tone.b, loud ? 0.3 : 0.14)
                border.width: 2
                border.color: Qt.rgba(tone.r, tone.g, tone.b, loud ? 1 : 0.5)
                opacity: Motion.rise(root.age, 3)
                transform: Translate { y: Motion.lift(root.age, 3) }
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: root.line
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                    lineHeight: 14; lineHeightMode: Text.FixedHeight
                }
            }
        }

        // the key beside her line: Connect, or Open
        Rectangle {
            id: key
            readonly property bool connects: !Hooks.installed
            visible: connects || root.hasSession
            x: side.x + side.width - width
            y: side.y + 70
            width: 62; height: 42
            radius: 12
            color: keyTap.pressed ? root.deep : root.teal
            border.width: activeFocus ? 3 : 2; border.color: "#FFFFFF"
            opacity: root.revealButton * Motion.rise(root.age, 3)
            property real pulse: 1
            scale: pulse * (keyTap.pressed ? 0.92 : keyHover.hovered ? 1.06 : 1)
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: connects ? "Connect Claude Code" : "Open session"
            function act() { root.go(connects ? "settings" : "session") }
            Column {
                anchors.centerIn: parent
                spacing: 0
                Icon { anchors.horizontalCenter: parent.horizontalCenter; size: 17; name: key.connects ? "plus" : "terminal"; color: "#04302c" }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: key.connects ? "Connect" : "Open"
                    color: "#04302c"
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
                }
            }
            // first launch: the key pulses twice (scale 1 -> 1.08 -> 1, 600 ms each, 400 ms apart)
            SequentialAnimation {
                id: pulseAnim
                NumberAnimation { target: key; property: "pulse"; to: 1.08; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { target: key; property: "pulse"; to: 1; duration: 300; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 400 }
                NumberAnimation { target: key; property: "pulse"; to: 1.08; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { target: key; property: "pulse"; to: 1; duration: 300; easing.type: Easing.InOutSine }
            }
            HoverHandler { id: keyHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Sfx.play("hover") }
            TapHandler { id: keyTap; onTapped: key.act() }
            Keys.onReturnPressed: key.act()
            Keys.onSpacePressed: key.act()
        }
    }
    function pulseConnect() { if (!Hooks.installed) pulseAnim.restart() }

    // a key: a glyph, a small word over a big one
    component Key1: FocusScope {
        id: k
        property string over: ""
        property string label: ""
        property string icon: ""       // a name from Icon.qml, or "github"
        signal clicked()
        width: 104; height: 48
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(root.teal.r, root.teal.g, root.teal.b, kt.pressed ? 0.5 : kh.hovered ? 0.32 : 0.14)
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            border.width: k.activeFocus ? 3 : 2; border.color: "#FFFFFF"
            scale: kt.pressed ? 0.94 : kh.hovered ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Item {
                x: 8; width: 24; height: parent.height
                Icon { visible: k.icon !== "github"; anchors.centerIn: parent; size: 22; name: k.icon; color: root.teal }
                GitHubMark { visible: k.icon === "github"; anchors.centerIn: parent; size: 20; color: root.teal }
            }
            Text {
                x: 38; y: 7
                text: k.over
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
            }
            Text {
                x: 38; y: 21
                text: k.label
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 14; font.weight: Font.Bold
            }
        }
        HoverHandler { id: kh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Sfx.play("hover") }
        TapHandler { id: kt; onTapped: k.clicked() }
        Keys.onReturnPressed: k.clicked()
        Keys.onSpacePressed: k.clicked()
    }

    // ---- Zundamon's Home is her player ----
    PlayerView {
        visible: root.ownU > 0.01 && root.shownOwn === "zunda"
        opacity: root.ownU
        age: root.age
    }
    // ---- Teto's is how the computer is doing ----
    TetoView {
        visible: root.ownU > 0.01 && root.shownOwn === "teto"
        opacity: root.ownU
        age: root.age
    }
    // ---- Luka's is how the connection is doing ----
    LukaView {
        visible: root.ownU > 0.01 && root.shownOwn === "luka"
        opacity: root.ownU
        age: root.age
    }
}
