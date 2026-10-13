// Settings: one page, six parts, each a card of its own: Claude Code (the hooks, the mods,
// always-allow rules), Characters, Look and sound, Bar (the monitor, the edge, when it
// shuts and hides), Services (GitHub, Discord), Kisel (updates, start at sign-in, quit).
// The chips above it do not turn pages: they scroll to a part, and the one being read is
// lit, so everything is in one place and nothing has to be looked for. In a card a
// setting is a line: what it is on the left, the control on the right. Each part has a
// candy colour of its own, as each character's card has: its sign, its card, its
// switches and its chip are of it, so a part is known at a glance. Keys go to the wallet
// and are never shown again.
import QtQuick
import QtQuick.Controls.Basic as C
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    signal toast(string text)
    readonly property bool inputFocus: ghField.inputFocus || discordField.inputFocus

    width: 494

    property var plan: null          // hooks preview being confirmed
    property bool planInstall: true
    property string note: ""
    // the candy colours, as the cards have them, and the ink that reads on any of them
    readonly property var candy: ({ teal: "#39C5BB", lime: "#B9DC6B", lemon: "#FFE08A", lilac: "#C9A8FF", sky: "#9CD4FF", pink: "#FF9EBB" })
    readonly property color candyInk: "#2a0f18"
    readonly property var names: ({ miku: "Miku", rin: "Rin", luka: "Luka", zunda: "Zundamon", teto: "Teto" })
    // the five jobs (each known by the one who had it first), whether it is switched on, and whether this computer can do it at all
    readonly property var jobs: [
        { id: "miku", name: "Claude Code", on: true, can: true },
        { id: "rin", name: Tr.t("Notifications"), on: Prefs.rinNotes, can: Notes.available },
        { id: "luka", name: Tr.t("Internet"), on: Prefs.lukaNet, can: Net.available },
        { id: "zunda", name: Tr.t("Music"), on: Prefs.zundaSpotify, can: Media.available },
        { id: "teto", name: Tr.t("Computer"), on: Prefs.tetoSystem, can: Sys.available }
    ]
    function setJob(id, v) {
        if (id === "rin") Prefs.rinNotes = v
        else if (id === "luka") Prefs.lukaNet = v
        else if (id === "zunda") Prefs.zundaSpotify = v
        else if (id === "teto") Prefs.tetoSystem = v
    }
    onActiveChanged: { if (active) { plan = null; note = ""; Mods.refresh() } }

    Timer { id: clearPlan; interval: 2200; onTriggered: root.plan = null }
    // dock the island on `edge`, `fraction` of the way along it, and remember that for this monitor
    function place(edge, fraction) {
        const len = Shell.edgeLength(edge)
        const used = Shell.setDock(edge, fraction * len)
        Prefs.setDock(Displays.current, edge, used / len)
    }
    function startPlan(install) {
        planInstall = install
        plan = Hooks.preview(install)
    }
    function confirmPlan() {
        if (Hooks.apply(planInstall)) {
            // the pill becomes a disc, a check draws itself, then it reads "Connected"
            writeBtn.success(planInstall ? Tr.t("Connected") : Tr.t("Removed"))
            Sfx.play("done")
            clearPlan.restart()
        } else {
            note = Tr.t("Couldn't write settings.json")
        }
    }

    // ---- the parts, and getting to one ----
    readonly property Flickable flick: scroll.contentItem
    readonly property var parts: [
        { id: "claude", name: "Claude Code", item: partClaude }, { id: "cast", name: Tr.t("Characters"), item: partCast },
        { id: "look", name: Tr.t("Look and sound"), item: partLook }, { id: "place", name: Tr.t("Bar"), item: partBar },
        { id: "services", name: Tr.t("Services"), item: partServices }, { id: "kisel", name: "Kisel", item: partKisel }]
    property string going: "" // the part being scrolled to: its chip is lit on the way
    // the part whose heading is at the top of what is seen, or was last to pass it
    readonly property string here: {
        if (going !== "") return going
        let at = parts[0].id
        for (const p of parts)
            if (p.item.y <= flick.contentY + 30) at = p.id
        return at
    }
    function show(id, atOnce) {
        for (const p of parts) {
            if (p.id !== id) continue
            const y = Math.max(0, Math.min(p.item.y, flick.contentHeight - flick.height))
            glide.stop()
            if (atOnce || Theme.reduced || !root.active) { going = ""; flick.contentY = y; return }
            going = id
            glide.to = y
            glide.start()
        }
    }
    Connections { target: root.flick; function onMovementStarted() { glide.stop() } } // the wheel or a drag takes over
    NumberAnimation { id: glide; target: root.flick; property: "contentY"; duration: Theme.tBase; easing.type: Easing.OutCubic; onStopped: root.going = "" }

    // (development: `--tab <id>` and `--scroll <px>` with `--grab`, to look at the other parts and further down)
    Timer {
        interval: 400
        running: Qt.application.arguments.indexOf("--scroll") > 0 || Qt.application.arguments.indexOf("--tab") > 0
        onTriggered: {
            const a = Qt.application.arguments
            if (a.indexOf("--tab") > 0)
                root.show(a[a.indexOf("--tab") + 1], true)
            if (a.indexOf("--scroll") > 0)
                root.flick.contentY = Number(a[a.indexOf("--scroll") + 1])
        }
    }
    // Rin has been clicked about an update: Settings opens at "Kisel", where updates are
    function showUpdates() { show("kisel", true) }

    // ---- what the page is made of ----
    // a part: its sign and name, and a card of lines under them
    component Part: Column {
        id: part
        property string title: ""
        property string icon: "gear"
        property color tint: Theme.kisel
        function wash(a) { return Qt.rgba(tint.r, tint.g, tint.b, a) }
        default property alias lines: body.data
        width: parent ? parent.width : 0
        spacing: Theme.space2
        Row {
            x: 2
            spacing: Theme.space2
            Rectangle { // its sign: a sticker in its colour
                width: 28; height: 28; radius: 10
                color: part.tint
                border.width: 2; border.color: Theme.edge
                rotation: -4
                Icon { anchors.centerIn: parent; name: part.icon; size: 16; color: root.candyInk }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: part.title; color: Theme.ink; font.family: Theme.display; font.pixelSize: 17; font.weight: Font.DemiBold }
            Spark { anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -5; size: 9; tint: Theme.inkOf(part.tint) }
        }
        Rectangle {
            width: parent.width
            height: body.height + 24
            radius: 16
            // (the colour is strongest at the top, where the part begins, and thins out down the card)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(Theme.surface1, part.wash(Theme.dark ? 0.13 : 0.22)) }
                GradientStop { position: 1; color: Qt.tint(Theme.surface1, part.wash(Theme.dark ? 0.04 : 0.08)) }
            }
            border.width: 1.5; border.color: part.wash(Theme.dark ? 0.38 : 0.7)
            Column { id: body; x: 12; y: 12; width: parent.width - 24; spacing: 10 }
        }
    }
    // a line: what it is (and a quieter word about it) on the left, the control on the
    // right; `stacked` puts the control under the words, for one too wide to sit beside them
    component Line: Item {
        id: line
        property string label: ""
        property string hint: ""
        property color hintColor: Theme.inkFaint
        property bool stacked: false
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: stacked ? words.height + (slot.height > 0 ? 8 + slot.height : 0) : Math.max(words.height, slot.height, 28)
        Column {
            id: words
            y: line.stacked ? 0 : (line.height - height) / 2
            width: line.stacked ? line.width : line.width - slot.width - 12
            spacing: 1
            Text { visible: line.label !== ""; width: parent.width; wrapMode: Text.Wrap; text: line.label; color: Theme.ink; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { visible: line.hint !== ""; width: parent.width; wrapMode: Text.Wrap; text: line.hint; color: line.hintColor; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
        }
        Row {
            id: slot
            spacing: Theme.space2
            x: line.stacked ? 0 : line.width - width
            y: line.stacked ? words.height + 8 : (line.height - height) / 2
        }
    }
    component Sep: Rectangle { property color tint: Theme.ink; width: parent ? parent.width : 0; height: 1; color: Qt.rgba(tint.r, tint.g, tint.b, 0.18) }
    component Small: Text { width: parent ? parent.width : 0; wrapMode: Text.Wrap; color: Theme.inkFaint; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
    // how something stands: a tick or a cross, and a word
    component Status: Row {
        property bool good: false
        property bool bad: false
        property string text: ""
        spacing: 6
        Icon { anchors.verticalCenter: parent.verticalCenter; name: parent.good ? "check" : "cross"; size: 16; color: parent.good ? Theme.mint : parent.bad ? Theme.danger : Theme.inkMuted }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.text; color: Theme.ink; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
    // the five of them in a row, one picked: `faceOf` says whose face stands for an entry
    component Faces: Row {
        id: faces
        property var model: ["miku", "rin", "luka", "zunda", "teto"]
        property string current: ""
        property var faceOf: (id) => id
        property bool alive: false // they breathe (the stage); or are portraits (the table under it)
        property color accent: Theme.kisel
        signal picked(string id)
        spacing: 2
        Repeater {
            model: faces.model
            Item {
                id: seat
                required property string modelData
                readonly property bool on: faces.current === modelData
                width: 34; height: 34
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.names[faces.faceOf(modelData)]
                Accessible.checked: on
                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: seat.on ? Theme.surface3 : seatHover.hovered ? Theme.veil : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                    border.width: seat.on || seat.activeFocus ? 2 : 0
                    border.color: seat.on ? faces.accent : Theme.ink
                }
                Mascot {
                    anchors.centerIn: parent
                    size: 24
                    bench: true
                    still: !faces.alive
                    paused: !root.active
                    character: faces.faceOf(seat.modelData)
                    opacity: seat.on || seatHover.hovered ? 1 : 0.7
                    scale: seatTap.pressed ? 0.9 : seat.on ? 1.08 : 0.9
                    Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
                    Behavior on scale { NumberAnimation { duration: Theme.tFast; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
                }
                HoverHandler { id: seatHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: seatTap; onTapped: { Sfx.play("click"); faces.picked(seat.modelData) } }
                Keys.onReturnPressed: faces.picked(modelData)
                Keys.onSpacePressed: faces.picked(modelData)
            }
        }
    }

    // the chips: they stay put while the page scrolls under them
    Row {
        id: tabs
        spacing: 6
        Repeater {
            model: root.parts
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: root.here === modelData.id
                width: chipText.implicitWidth + 20; height: 28; radius: 14
                readonly property color tint: modelData.item.tint
                color: on ? tint : chipHover.hovered ? Theme.surface3 : Theme.surface2
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                border.width: activeFocus || on ? 2 : 1.5 // (a ring of its part's colour at rest, the sticker's edge when lit)
                border.color: activeFocus ? Theme.ink : on ? Theme.edge : Qt.rgba(tint.r, tint.g, tint.b, Theme.dark ? 0.55 : 0.9)
                scale: chipTap.pressed ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: Theme.tPress } }
                activeFocusOnTab: true
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.name
                Accessible.selected: on
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.name
                    color: chip.on ? root.candyInk : Theme.inkMuted
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
                }
                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: chipTap; onTapped: { Sfx.play("click"); root.show(chip.modelData.id) } }
                Keys.onReturnPressed: root.show(modelData.id)
                Keys.onSpacePressed: root.show(modelData.id)
            }
        }
    }
    C.ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.topMargin: tabs.height + Theme.space3
        contentWidth: availableWidth
        clip: true
        C.ScrollBar.vertical.policy: C.ScrollBar.AsNeeded

        Column {
            id: page
            width: root.width - 12
            spacing: Theme.space4

            // ==== Claude Code: the hooks, the mods, what is always allowed ====
            Part {
                id: partClaude
                title: "Claude Code"; icon: "terminal"; tint: root.candy.teal

                Item {
                    width: parent.width
                    height: 36
                    Status {
                        anchors.verticalCenter: parent.verticalCenter
                        good: Hooks.health === "ok"; bad: Hooks.health === "stale" || root.note !== ""
                        text: root.note !== "" ? root.note
                            : Hooks.health === "ok" ? Tr.t("Connected")
                            : Hooks.health === "stale" ? Tr.t("Needs repair")
                            : Hooks.health === "unreadable" ? Tr.t("settings.json is not valid JSON")
                            : Tr.t("Not connected")
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2
                        KButton {
                            visible: !root.plan && Hooks.health !== "unreadable"
                            primary: Hooks.health !== "ok"
                            text: Hooks.health === "stale" ? Tr.t("Repair hooks") : Hooks.installed ? Tr.t("Remove hooks") : Tr.t("Connect Claude Code")
                            onClicked: root.startPlan(Hooks.health === "stale" || !Hooks.installed)
                        }
                        KButton {
                            visible: !root.plan && Hooks.health === "stale"
                            variant: "ghost"
                            text: Tr.t("Remove hooks")
                            onClicked: root.startPlan(false)
                        }
                    }
                }
                Column { // the change, shown before it is made
                    visible: !!root.plan
                    width: parent.width
                    spacing: Theme.space2
                    Small {
                        color: root.plan && root.plan.ok ? Theme.inkMuted : Theme.danger
                        text: !root.plan ? "" : !root.plan.ok ? Tr.d(root.plan.error)
                            : !root.plan.changed ? Tr.t("Nothing to change in ") + root.plan.path
                            : Tr.t("This is the exact change to ") + root.plan.path + Tr.t(". A backup is saved first as ") + root.plan.backup
                    }
                    CodePanel {
                        visible: !!root.plan && root.plan.ok && root.plan.changed
                        width: parent.width
                        height: 150
                        lines: root.plan && root.plan.ok ? root.plan.diff : []
                    }
                    Row {
                        spacing: Theme.space2
                        KButton { id: writeBtn; visible: !!root.plan && root.plan.ok && root.plan.changed; variant: "primary"; text: Tr.t("Write change"); onClicked: root.confirmPlan() }
                        KButton { variant: "ghost"; text: Tr.t("Cancel"); onClicked: root.plan = null }
                    }
                }
                // what Kisel does when the hooks are missing or broken (it never answers a permission for you)
                Line {
                    stacked: true
                    label: Tr.t("If hooks break")
                    hint: Prefs.hookWatch === "auto" ? Tr.t("Hooks that were connected and went stale are repaired by themselves, with a dated backup. New hooks are never added without your click.")
                        : Prefs.hookWatch === "ask" ? Tr.t("Kisel tells you when the hooks are missing or stale. The change is made only after you confirm it here.")
                        : Tr.t("Kisel does not check the hooks.")
                    KSegment {
                        accent: partClaude.tint; accentInk: root.candyInk;
                        model: [{ id: "ask", name: Tr.t("Ask me") }, { id: "auto", name: Tr.t("Repair") }, { id: "off", name: Tr.t("Do nothing") }]
                        current: Prefs.hookWatch
                        onPicked: (id) => Prefs.hookWatch = id
                    }
                }
                Sep { tint: partClaude.tint }

                // ---- the mods: Kisel's plugin for Claude Code ----
                // (They are what the chat talks to a session through, so they stand where the
                // API key used to: with them the chat needs no key. Kisel runs Claude Code's own
                // command line for this, only on the click, and shows the commands first.)
                Line {
                    label: Tr.t("Claude Code mods")
                    Status {
                        anchors.verticalCenter: parent.verticalCenter
                        good: Mods.state === "installed"; bad: Mods.state === "failed"
                        text: Mods.state === "installed" ? Tr.t("Installed")
                            : Mods.state === "outdated" ? Tr.t("Installed, an update is ready")
                            : Mods.state === "partial" ? Tr.t("Partly installed")
                            : Mods.state === "working" ? Tr.t("Working on it")
                            : Mods.state === "checking" ? Tr.t("Checking")
                            : Mods.state === "noclaude" ? Tr.t("Claude Code was not found")
                            : Mods.state === "nomods" ? Tr.t("This build has no mods to install")
                            : Mods.state === "failed" ? Tr.t("Couldn't install")
                            : Tr.t("Not installed")
                    }
                }
                Small { text: Tr.t("A plugin for Claude Code. It joins your session to the chat here: what you write goes to it as your prompt, and Claude's replies and your limits come back. It loads in sessions started after this.") }
                Row {
                    spacing: Theme.space2
                    KButton {
                        visible: Mods.state === "none" || Mods.state === "partial" || Mods.state === "failed"
                        primary: true
                        text: Mods.state === "partial" ? Tr.t("Install the rest") : Tr.t("Install mods")
                        onClicked: { Sfx.play("click"); Mods.install() }
                    }
                    KButton {
                        visible: Mods.state === "outdated"
                        primary: true
                        text: Tr.t("Update mods")
                        onClicked: { Sfx.play("click"); Mods.update() }
                    }
                    KButton {
                        visible: Mods.state === "installed" || Mods.state === "partial" || Mods.state === "outdated"
                        variant: "ghost"
                        text: Tr.t("Remove mods")
                        onClicked: { Sfx.play("click"); Mods.remove() }
                    }
                    KButton { // the guide, in case: it opens under the buttons
                        id: modsInfo
                        property bool open: false
                        variant: open ? "secondary" : "ghost"
                        icon: "info"
                        text: Tr.t("How the mods work")
                        onClicked: { Sfx.play("click"); open = !open }
                    }
                }
                Small {
                    visible: Mods.state === "failed" && Mods.detail !== ""
                    text: Mods.detail
                    color: Theme.danger; font.family: Theme.mono; font.weight: Font.Normal
                }
                Column { // the commands, as they will be run
                    visible: Mods.state === "none" || Mods.state === "partial" || Mods.state === "failed"
                    width: parent.width
                    spacing: 1
                    Repeater {
                        model: Mods.commands
                        Text { required property string modelData; width: parent.width; elide: Text.ElideMiddle; text: modelData; color: Theme.inkFaint; font.family: Theme.mono; font.pixelSize: 10 }
                    }
                }
                Rectangle {
                    visible: modsInfo.open
                    width: parent.width
                    height: guide.height + 20
                    radius: Theme.radiusMd
                    color: Theme.surface2
                    border.width: 1; border.color: Theme.line
                    Column {
                        id: guide
                        x: 12; y: 10
                        width: parent.width - 24
                        spacing: 8
                        Repeater {
                            model: [
                            { head: Tr.t("What they are"), body: Tr.t("A plugin that Kisel installs into Claude Code. kisel-prompts joins a session to this chat.") },
                            { head: Tr.t("1. You need the claude command"), body: Tr.t("Open a terminal and run: claude --version. If it is not found, install Claude Code's command line first: npm install -g @anthropic-ai/claude-code. The desktop app alone is not enough for the button.") },
                            { head: Tr.t("2. Press Install mods"), body: Tr.t("Kisel runs the two commands shown under the button. Nothing else on your computer is changed. It takes a few seconds; the line above turns to Installed.") },
                            { head: Tr.t("3. Start a new session"), body: Tr.t("Plugins load when a session starts. Close the Claude Code chat or terminal you had open and start it again.") },
                            { head: Tr.t("4. Write from Kisel"), body: Tr.t("Click the bar, open Chat. Within a couple of seconds the field reads Write to Claude Code. What you send goes to the session as your own prompt; Claude's replies appear here too.") },
                            { head: Tr.t("What else shows up"), body: Tr.t("The rings in the chat are your limits: the five-hour window, the week, and how full the session's context is. Miku holds Claude's little one there.") },
                            { head: Tr.t("If the field still says Message Claude"), body: Tr.t("No session is listening. Check that the session was started after installing, and that Kisel sees it (Miku reacts when Claude works). The session and Kisel must run under the same user.") },
                            { head: Tr.t("Doing it by hand"), body: Tr.t("The same two commands work in any terminal. To take the mod out: Remove mods here, or claude plugin uninstall kisel-prompts@kisel.") },
                            { head: Tr.t("What it can and cannot do"), body: Tr.t("It only passes text: your prompts in, Claude's words and the limit figures out, through a folder in your home folder (.kisel, inbox). It never answers a permission for you.") }
                            ]
                            Column {
                                required property var modelData
                                width: guide.width
                                spacing: 1
                                Text { width: parent.width; wrapMode: Text.Wrap; text: modelData.head; color: Theme.ink; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold }
                                Text { width: parent.width; wrapMode: Text.Wrap; text: modelData.body; color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
                            }
                        }
                    }
                }
                Sep { tint: partClaude.tint }

                // ---- always-allow ----
                Line {
                    label: Tr.t("Always allowed")
                    hint: Prefs.alwaysCount === 0 ? Tr.t("Nothing yet. \"Always\" on a card adds a rule here.")
                                                  : Prefs.alwaysCount + Tr.tn(Prefs.alwaysCount, Prefs.alwaysCount === 1 ? " rule" : " rules")
                    KButton { visible: Prefs.alwaysCount > 0; variant: "danger"; text: Tr.t("Clear"); onClicked: { Prefs.clearAlwaysRules(); root.toast(Tr.t("Rules cleared")) } }
                }
            }

            // ==== who is on stage, and what each of them is tied to ====
            Part {
                id: partCast
                title: Tr.t("Characters"); icon: "smile"; tint: root.candy.lime

                Line {
                    label: Tr.t("On stage")
                    hint: root.names[Prefs.faces[Prefs.character]]
                    Faces {
                        accent: partCast.tint;
                        alive: true
                        current: Prefs.character
                        faceOf: (job) => Prefs.faces[job]
                        onPicked: (job) => Prefs.character = job
                    }
                }
                Sep { tint: partCast.tint }
                // ---- who does what: each job goes to one of the five; the one who had it takes
                // the job its new owner leaves, so nobody is left idle and nothing is done twice ----
                Small { text: Tr.t("Who does what"); color: Theme.inkMuted; font.pixelSize: 12; font.weight: Font.ExtraBold }
                Repeater {
                    model: root.jobs
                    Line {
                        id: job
                        required property var modelData
                        label: modelData.name
                        hint: root.names[Prefs.faces[modelData.id]]
                        opacity: modelData.can ? 1 : 0.5
                        Faces {
                            accent: partCast.tint;
                            anchors.verticalCenter: parent.verticalCenter
                            current: Prefs.faces[job.modelData.id]
                            onPicked: (who) => Prefs.setFace(job.modelData.id, who)
                        }
                        Item { // (Claude Code is what Kisel is for: it has no switch, only the room of one)
                            width: 44; height: 28
                            anchors.verticalCenter: parent.verticalCenter
                            KToggle {
                                accent: partCast.tint; accentInk: root.candyInk;
                                visible: job.modelData.id !== "miku"
                                enabled: job.modelData.can
                                bare: true
                                label: job.modelData.name
                                checked: job.modelData.on
                                onToggled: (v) => root.setJob(job.modelData.id, v)
                            }
                        }
                    }
                }
            }

            // ==== look and sound ====
            Part {
                id: partLook
                title: Tr.t("Look and sound"); icon: "sun"; tint: root.candy.lemon

                Line {
                    label: Tr.t("Theme")
                    KSegment {
                        accent: partLook.tint; accentInk: root.candyInk;
                        model: [{ id: "system", name: Tr.t("System") }, { id: "dark", name: Tr.t("Dark") }, { id: "light", name: Tr.t("Light") }]
                        current: Prefs.theme
                        onPicked: (id) => Prefs.theme = id
                    }
                }
                Line { // the interface's language
                    label: Tr.t("Language")
                    KSegment {
                        accent: partLook.tint; accentInk: root.candyInk;
                        model: [{ id: "en", name: "English" }, { id: "ru", name: "Русский" }]
                        current: Tr.lang
                        onPicked: (id) => Prefs.language = id
                    }
                }
                Line {
                    label: Tr.t("Reduce motion")
                    KToggle { accent: partLook.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Reduce motion"); checked: Prefs.reduceMotion; onToggled: (v) => Prefs.reduceMotion = v }
                }
                Sep { tint: partLook.tint }
                Line {
                    label: Tr.t("Sounds")
                    KToggle { accent: partLook.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Sounds"); checked: Prefs.soundOn; onToggled: (v) => Prefs.soundOn = v }
                }
                Line {
                    visible: Prefs.soundOn
                    label: Tr.t("Volume")
                    hint: Prefs.soundVolume + "%"
                    KSlider {
                        accent: partLook.tint;
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 10
                        value: Math.round(Prefs.soundVolume / 10)
                        Accessible.name: Tr.t("Volume")
                        onMoved: (v) => { Prefs.soundVolume = v * 10; Sfx.play("click") }
                    }
                }
            }

            // ==== the bar: the monitor it is on, the edge, how far along it, when it shuts and hides ====
            Part {
                id: partBar
                title: Tr.t("Bar"); icon: "pill"; tint: root.candy.lilac

                // ---- screen: a little map of your monitors, tap one to move Kisel there ----
                Line {
                    label: Tr.t("Screen")
                    hint: Displays.wanted === "" ? Tr.t("Kisel follows your primary monitor (") + Displays.current + Tr.t("), also after a restart")
                        : Tr.t("Kisel stays on ") + Displays.wanted + Tr.t(", also after a restart")
                    KButton {
                        visible: Displays.wanted !== ""
                        text: Tr.t("Follow primary")
                        onClicked: { Displays.select(""); root.toast(Tr.t("Following the primary monitor")) }
                    }
                }
                Item {
                    id: map
                    width: parent.width
                    height: 84
                    readonly property var list: Displays.screens
                    readonly property real minX: Math.min.apply(null, list.map(s => s.x))
                    readonly property real minY: Math.min.apply(null, list.map(s => s.y))
                    readonly property real maxX: Math.max.apply(null, list.map(s => s.x + s.w))
                    readonly property real maxY: Math.max.apply(null, list.map(s => s.y + s.h))
                    readonly property real k: Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY))
                    // centre the whole map in the row
                    readonly property real offX: (width - (maxX - minX) * k) / 2
                    readonly property real offY: (height - (maxY - minY) * k) / 2

                    Repeater {
                        model: map.list
                        Rectangle {
                            id: mon
                            required property var modelData
                            readonly property bool here: Displays.current === modelData.name
                            x: map.offX + (modelData.x - map.minX) * map.k
                            y: map.offY + (modelData.y - map.minY) * map.k
                            width: modelData.w * map.k - 4
                            height: modelData.h * map.k - 4
                            radius: 8
                            color: mh.hovered || tap.pressed ? Theme.surface3 : Theme.surface2
                            Behavior on color { ColorAnimation { duration: Theme.tHover } }
                            border.width: here ? 2 : 1
                            border.color: here ? partBar.tint : Theme.line
                            scale: tap.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label + (here ? Tr.t(", Kisel is here") : "")
                            Accessible.checked: here

                            // the bar, drawn tiny on the edge it is docked to, as far along it as it really is
                            Rectangle {
                                id: pill
                                readonly property bool upright: Shell.edge === "left" || Shell.edge === "right"
                                readonly property real at: Shell.along / Math.max(1, Shell.edgeLength(Shell.edge))
                                readonly property real len: mon.here ? 30 : 0
                                width: upright ? (mon.here ? 8 : 0) : len
                                height: upright ? len : (mon.here ? 8 : 0)
                                x: upright ? (Shell.edge === "left" ? -1 : mon.width - width + 1) : Math.max(3, Math.min(mon.width - width - 3, mon.width * at - width / 2))
                                y: upright ? Math.max(3, Math.min(mon.height - height - 3, mon.height * at - height / 2)) : (Shell.edge === "top" ? -1 : mon.height - height + 1)
                                radius: 4
                                color: partBar.tint
                                Behavior on x { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
                                Behavior on y { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, mon.width - 12)
                                    elide: Text.ElideRight
                                    text: mon.modelData.name || mon.modelData.label
                                    color: Theme.ink
                                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, mon.width - 12)
                                    elide: Text.ElideRight
                                    text: mon.modelData.w + "×" + mon.modelData.h
                                    color: Theme.inkFaint
                                    font.family: Theme.mono; font.pixelSize: 11
                                }
                            }
                            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: tap; onTapped: { Displays.select(mon.modelData.name); root.toast(Tr.t("Kisel moved to ") + mon.modelData.name) } }
                        }
                    }
                }
                Sep { tint: partBar.tint }

                // where the bar sits: the edge, and how far along it
                Line {
                    label: Tr.t("Edge")
                    KSegment {
                        accent: partBar.tint; accentInk: root.candyInk;
                        model: [{ id: "top", name: Tr.t("Top") }, { id: "bottom", name: Tr.t("Bottom") }, { id: "left", name: Tr.t("Left") }, { id: "right", name: Tr.t("Right") }]
                        current: Shell.edge
                        onPicked: (id) => root.place(id, Shell.along / Shell.edgeLength(Shell.edge))
                    }
                }
                // exactly at an end of the edge or in its middle (by hand it lands a few pixels off), or anywhere between
                Line {
                    id: alongLine
                    readonly property bool upright: Shell.edge === "left" || Shell.edge === "right"
                    readonly property real at: Shell.along / Shell.edgeLength(Shell.edge)
                    readonly property int keepOut: 162 // (as near a corner as the bar goes: IslandWindow::kCornerKeepOut)
                    stacked: true
                    label: Tr.t("Along the edge")
                    KSegment {
                        accent: partBar.tint; accentInk: root.candyInk;
                        model: [{ id: "0", name: alongLine.upright ? Tr.t("Top") : Tr.t("Left") }, { id: "0.5", name: Tr.t("Centre") }, { id: "1", name: alongLine.upright ? Tr.t("Bottom") : Tr.t("Right") }]
                        current: Math.abs(alongLine.at - 0.5) < 0.002 ? "0.5" : Shell.along <= alongLine.keepOut + 1 ? "0" : Shell.along >= Shell.edgeLength(Shell.edge) - alongLine.keepOut - 1 ? "1" : ""
                        onPicked: (id) => root.place(Shell.edge, Number(id))
                    }
                    KSlider {
                        accent: partBar.tint;
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 20
                        value: Math.round(alongLine.at * 20)
                        Accessible.name: Tr.t("Along the edge")
                        onMoved: (v) => root.place(Shell.edge, v / 20)
                    }
                }
                Line {
                    visible: Shell.canAvoidPanels
                    label: Tr.t("Stay clear of the taskbar")
                    KToggle { accent: partBar.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Stay clear of the taskbar"); checked: Prefs.avoidPanels; onToggled: (v) => Prefs.avoidPanels = v }
                }
                Sep { tint: partBar.tint }
                Line {
                    label: Tr.t("Close the card")
                    hint: Prefs.closeDelay === 0 ? Tr.t("At once, when the pointer leaves") : Tr.t("%1 s after the pointer leaves").replace("%1", Prefs.closeDelay)
                    KSlider {
                        accent: partBar.tint;
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 10
                        value: Prefs.closeDelay
                        Accessible.name: Tr.t("Close the card")
                        onMoved: (v) => Prefs.closeDelay = v
                    }
                }
                // how long the bar rests before it hides in its edge (the last step: it never does)
                Line {
                    label: Tr.t("Hide the bar")
                    hint: Prefs.tuckDelay === 0 ? Tr.t("Never") : Tr.t("After %1 of rest").replace("%1", tuckSlider.word(Prefs.tuckDelay))
                    KSlider {
                        accent: partBar.tint;
                        id: tuckSlider
                        readonly property var steps: [10, 20, 30, 60, 120, 300, 600, 0]
                        function word(s) { return s < 60 ? s + Tr.t(" s") : s / 60 + Tr.t(" min") }
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: steps.length - 1
                        value: { let at = steps.indexOf(Prefs.tuckDelay); if (at < 0) { at = 0; while (at < steps.length - 2 && steps[at] < Prefs.tuckDelay) ++at } return at }
                        Accessible.name: Tr.t("Hide the bar")
                        onMoved: (v) => Prefs.tuckDelay = steps[v]
                    }
                }
            }

            // ==== what Kisel is joined to: GitHub, Discord ====
            Part {
                id: partServices
                title: Tr.t("Services"); icon: "link"; tint: root.candy.sky

                // ---- GitHub: a read-only token for the widget ----
                Line {
                    stacked: true
                    label: "GitHub"
                    hint: Tr.t("For your pull requests in Repos. A read-only personal access token is enough.")
                    KField {
                        id: ghField
                        width: GitHub.hasToken ? 220 : 300
                        echoMode: TextInput.Password
                        placeholder: GitHub.hasToken ? Tr.t("Token saved in ") + Vault.storeName : Tr.t("Personal access token (read-only)")
                        onAccepted: root.saveGitHub()
                    }
                    KButton { id: ghSave; variant: "primary"; text: Tr.t("Save"); onClicked: root.saveGitHub() }
                    KButton { visible: GitHub.hasToken; variant: "ghost"; text: Tr.t("Remove")
                        onClicked: { Vault.remove("github"); root.toast(Tr.t("GitHub token removed")) } }
                }
                Sep { tint: partServices.tint }

                // ---- Discord: "Working with Claude Code" in your profile ----
                // (Off unless switched on: it tells other people what you are doing. Kisel talks
                // only to the Discord running on this computer. See DiscordPresence.)
                Line {
                    label: "Discord"
                    hint: Tr.t("Show in Discord that I work with Claude Code")
                    KToggle { accent: partServices.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Show in Discord that I work with Claude Code"); checked: Prefs.discordOn; onToggled: (v) => Prefs.discordOn = v }
                }
                Line {
                    visible: Prefs.discordOn
                    label: Tr.t("Show the session's name too")
                    KToggle { accent: partServices.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Show the session's name too"); checked: Prefs.discordProject; onToggled: (v) => Prefs.discordProject = v }
                }
                Status {
                    visible: Prefs.discordOn
                    good: Discord.state === "on"; bad: Discord.state === "refused"
                    text: Discord.state === "on" ? Tr.t("Connected to Discord")
                        : Discord.state === "noid" ? Tr.t("Needs an Application ID")
                        : Discord.state === "refused" ? Tr.t("Discord did not take this Application ID")
                        : Tr.t("Discord is not running")
                }
                Row { // (Kisel has an application of its own: another is asked for only if Discord turns that one down)
                    visible: Prefs.discordOn && (Discord.state === "noid" || Discord.state === "refused")
                    spacing: Theme.space2
                    KField {
                        id: discordField
                        width: 300
                        placeholder: Prefs.discordAppId !== "" ? "Application ID: " + Prefs.discordAppId : Tr.t("Discord Application ID")
                        onAccepted: root.saveDiscord()
                    }
                    KButton { id: discordSave; variant: "primary"; text: Tr.t("Save"); onClicked: root.saveDiscord() }
                }
                Small {
                    visible: Prefs.discordOn && (Discord.state === "noid" || Discord.state === "refused")
                    text: Tr.t("Discord shows an activity under the name of a Discord application. Make one called Kisel at discord.com/developers/applications, copy its Application ID here, and add a picture named kisel under Rich Presence, Art Assets if you want one. The ID is a public number, not a password.")
                }
            }

            // ==== Kisel itself: updates, starting with the computer, quit ====
            Part {
                id: partKisel
                title: "Kisel"; icon: "heart"; tint: root.candy.pink

                // ---- updates: Kisel asks GitHub at start and once a day (one question, nothing
                // about you in it), unless that is switched off; it installs nothing by itself ----
                Line {
                    visible: Updates.available
                    label: Updates.state === "checking" ? Tr.t("Asking GitHub...")
                        : Updates.state === "current" ? "Kisel " + Updates.current + Tr.t(" is the newest")
                        : Updates.state === "found" ? "Kisel " + Updates.latest + Tr.t(" is out (you have ") + Updates.current + ")"
                        : Updates.state === "downloading" ? Tr.t("Downloading ") + Updates.latest + "  " + Math.round(Updates.progress * 100) + "%"
                        : Updates.state === "starting" ? Tr.t("Installing. Kisel will be right back.")
                        : "Kisel " + Updates.current
                    hint: Updates.state === "failed" ? Tr.d(Updates.error) : ""
                    hintColor: Theme.danger
                    KButton {
                        visible: Updates.state !== "found" && Updates.state !== "downloading" && Updates.state !== "starting"
                        enabled: Updates.state !== "checking"
                        icon: "refresh"; text: Tr.t("Check for updates")
                        onClicked: Updates.check()
                    }
                    KButton {
                        visible: Updates.state === "found"
                        variant: "primary"; text: Tr.t("Update and restart")
                        onClicked: Updates.update()
                    }
                }
                Line { visible: !Updates.available; label: "Kisel " + Updates.current }
                Rectangle { // the download, as it comes
                    visible: Updates.state === "downloading"
                    width: parent.width; height: 6; radius: 3
                    color: Theme.surface3
                    Rectangle { width: parent.width * Updates.progress; height: parent.height; radius: 3; color: Theme.kisel }
                }
                Line {
                    visible: Updates.available
                    label: Tr.t("Check for updates by itself")
                    KToggle { accent: partKisel.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Check for updates by itself"); checked: Prefs.updateCheck; onToggled: (v) => Prefs.updateCheck = v }
                }
                Line {
                    label: Tr.t("Start when I sign in")
                    KToggle { accent: partKisel.tint; accentInk: root.candyInk; bare: true; label: Tr.t("Start when I sign in"); checked: Shell.autostart; onToggled: (v) => Shell.autostart = v }
                }
                Sep { tint: partKisel.tint }
                Line {
                    label: Tr.t("Quit Kisel")
                    hint: Tr.t("The bar goes away until Kisel is started again.")
                    KButton { text: Tr.t("Quit"); variant: "danger"; onClicked: Shell.quit() }
                }
            }
            // (room under the last part, so that its heading too can come up to the top)
            Item { width: 1; height: Math.max(Theme.space2, scroll.height - partKisel.height - page.spacing) }
        }
    }

    function saveDiscord() {
        const id = discordField.text.trim()
        if (!/^[0-9]{15,22}$/.test(id)) {
            root.toast(Tr.t("An Application ID is a long number"))
            return
        }
        Prefs.discordAppId = id
        discordField.text = ""
        discordSave.success(Tr.t("Saved"))
        Sfx.play("done")
    }
    function saveGitHub() {
        if (ghField.text.trim() === "")
            return
        if (Vault.store("github", ghField.text.trim())) {
            ghField.text = ""
            ghSave.success(Tr.t("Saved"))
            Sfx.play("done")
        } else {
            root.toast(Tr.t("Couldn't reach ") + Vault.storeName)
        }
    }
}
