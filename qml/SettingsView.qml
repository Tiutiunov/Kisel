// Settings, in six tabs: Claude Code (the hooks, the mods, always-allow rules), Services
// (GitHub, Discord), Characters, Look and sound, Place, Kisel (updates, quit). Keys go to
// the wallet and are never shown again.
import QtQuick
import QtQuick.Controls.Basic as C
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    signal toast(string text)
    readonly property bool inputFocus: ghField.inputFocus

    width: 494

    property var plan: null          // hooks preview being confirmed
    property bool planInstall: true
    property string note: ""
    property string tab: "claude"
    readonly property var tabList: [{ id: "claude", name: "Claude Code" }, { id: "services", name: Tr.t("Services") }, { id: "cast", name: Tr.t("Characters") },
        { id: "look", name: Tr.t("Look and sound") }, { id: "place", name: Tr.t("Place") }, { id: "kisel", name: "Kisel" }]
    function show(t) { tab = t; scroll.contentItem.contentY = 0 }
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

    // (development: `--tab <id>` and `--scroll <px>` with `--grab`, to look at the other tabs and further down)
    Timer {
        interval: 400
        running: Qt.application.arguments.indexOf("--scroll") > 0 || Qt.application.arguments.indexOf("--tab") > 0
        onTriggered: {
            const a = Qt.application.arguments
            if (a.indexOf("--tab") > 0)
                root.tab = a[a.indexOf("--tab") + 1]
            if (a.indexOf("--scroll") > 0)
                scroll.contentItem.contentY = Number(a[a.indexOf("--scroll") + 1])
        }
    }
    // Rin has been clicked about an update: Settings opens at "Updates"
    function showUpdates() { show("kisel") }

    // the tabs: they stay put while the tab under them scrolls
    Row {
        id: tabs
        spacing: 6
        Repeater {
            model: root.tabList
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: root.tab === modelData.id
                width: chipText.implicitWidth + 20; height: 28; radius: 14
                color: on ? Theme.kisel : chipHover.hovered ? Theme.surface3 : Theme.surface2
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                border.width: activeFocus ? 2 : 0; border.color: Theme.ink
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
                    color: chip.on ? Theme.onKisel : Theme.inkMuted
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
            width: root.width - 12
            spacing: Theme.space3

            // ==== Claude Code: the hooks, the mods, what is always allowed ====
            Column {
                visible: root.tab === "claude"
                width: parent.width
                spacing: Theme.space3

                // ---- Claude Code ----
                Text { text: "Claude Code"; color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Row {
                    spacing: Theme.space2
                    Icon { name: Hooks.health === "ok" ? "check" : "cross"; size: 16
                        color: Hooks.health === "ok" ? Theme.mint : Hooks.health === "stale" ? Theme.danger : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.note !== "" ? root.note
                            : Hooks.health === "ok" ? Tr.t("Connected")
                            : Hooks.health === "stale" ? Tr.t("Needs repair")
                            : Hooks.health === "unreadable" ? Tr.t("settings.json is not valid JSON")
                            : Tr.t("Not connected")
                        color: Theme.ink; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
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
                // what Kisel does when the hooks are missing or broken (it never answers a permission for you)
                Row {
                    spacing: Theme.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("If hooks break")
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: [{ id: "ask", name: Tr.t("Ask me") }, { id: "auto", name: Tr.t("Repair") }, { id: "off", name: Tr.t("Do nothing") }]
                        KButton {
                            required property var modelData
                            primary: Prefs.hookWatch === modelData.id
                            text: modelData.name
                            onClicked: Prefs.hookWatch = modelData.id
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: Theme.inkFaint; font.family: Theme.sans; font.pixelSize: 11
                    text: Prefs.hookWatch === "auto" ? Tr.t("Hooks that were connected and went stale are repaired by themselves, with a dated backup. New hooks are never added without your click.")
                        : Prefs.hookWatch === "ask" ? Tr.t("Kisel tells you when the hooks are missing or stale. The change is made only after you confirm it here.")
                        : Tr.t("Kisel does not check the hooks.")
                }
                Column {
                    visible: !!root.plan
                    width: parent.width
                    spacing: Theme.space2
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: root.plan && root.plan.ok ? Theme.inkMuted : Theme.danger
                        font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
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

                // ---- the mods: Kisel's two plugins for Claude Code ----
                // (They are what the chat talks to a session through, so they stand where the
                // API key used to: with them the chat needs no key. Kisel runs Claude Code's own
                // command line for this, only on the click, and shows the commands first.)
                Row {
                    spacing: Theme.space2
                    Text { text: Tr.t("Claude Code mods"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                    // the guide, in case: it opens under the section
                    Item {
                        id: modsInfo
                        property bool open: false
                        width: 22; height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("How the mods work")
                        Rectangle { anchors.fill: parent; radius: 11; color: modsInfo.open ? Theme.kisel : infoHover.hovered ? Theme.surface3 : "transparent" }
                        Icon { anchors.centerIn: parent; name: "info"; size: 18; color: modsInfo.open ? Theme.onKisel : Theme.inkMuted }
                        HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { Sfx.play("click"); modsInfo.open = !modsInfo.open } }
                        Keys.onReturnPressed: modsInfo.open = !modsInfo.open
                        Keys.onSpacePressed: modsInfo.open = !modsInfo.open
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
                            { head: Tr.t("What they are"), body: Tr.t("Two plugins that Kisel installs into Claude Code. kisel-prompts joins a session to this chat. cache-band adds a line about the prompt cache above the prompt box.") },
                            { head: Tr.t("1. You need the claude command"), body: Tr.t("Open a terminal and run: claude --version. If it is not found, install Claude Code's command line first: npm install -g @anthropic-ai/claude-code. The desktop app alone is not enough for the button.") },
                            { head: Tr.t("2. Press Install mods"), body: Tr.t("Kisel runs the three commands shown under the button. Nothing else on your computer is changed. It takes a few seconds; the line above turns to Installed.") },
                            { head: Tr.t("3. Start a new session"), body: Tr.t("Plugins load when a session starts. Close the Claude Code chat or terminal you had open and start it again.") },
                            { head: Tr.t("4. Write from Kisel"), body: Tr.t("Click the bar, open Chat. Within a couple of seconds the field reads Write to Claude Code. What you send goes to the session as your own prompt; Claude's replies appear here too.") },
                            { head: Tr.t("What else shows up"), body: Tr.t("The rings in the chat are your limits: the five-hour window, the week, and how full the session's context is. Miku holds Claude's little one there.") },
                            { head: Tr.t("If the field still says Message Claude"), body: Tr.t("No session is listening. Check that the session was started after installing, and that Kisel sees it (Miku reacts when Claude works). The session and Kisel must run under the same Windows user.") },
                            { head: Tr.t("Doing it by hand"), body: Tr.t("The same three commands work in any terminal. To take the mods out: Remove mods here, or claude plugin uninstall kisel-prompts@kisel and cache-band@kisel.") },
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
                Row {
                    spacing: Theme.space2
                    Icon { name: Mods.state === "installed" ? "check" : "cross"; size: 16
                        color: Mods.state === "installed" ? Theme.mint : Mods.state === "failed" ? Theme.danger : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Mods.state === "installed" ? Tr.t("Installed")
                            : Mods.state === "outdated" ? Tr.t("Installed, an update is ready")
                            : Mods.state === "partial" ? Tr.t("Partly installed")
                            : Mods.state === "working" ? Tr.t("Working on it")
                            : Mods.state === "checking" ? Tr.t("Checking")
                            : Mods.state === "noclaude" ? Tr.t("Claude Code was not found")
                            : Mods.state === "nomods" ? Tr.t("This build has no mods to install")
                            : Mods.state === "failed" ? Tr.t("Couldn't install")
                            : Tr.t("Not installed")
                        color: Theme.ink; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
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
                }
                Text {
                    visible: Mods.state === "failed" && Mods.detail !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: Mods.detail
                    color: Theme.danger; font.family: Theme.mono; font.pixelSize: 11
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: Theme.inkFaint; font.family: Theme.sans; font.pixelSize: 11
                    text: Tr.t("Two plugins for Claude Code. One joins your session to the chat here: what you write goes to it as your prompt, and Claude's replies and your limits come back. The other shows the prompt cache above the prompt. They load in sessions started after this.")
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

                // ---- always-allow ----
                Text { text: Tr.t("Always allowed"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Row {
                    spacing: Theme.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Prefs.alwaysCount === 0 ? Tr.t("Nothing yet. \"Always\" on a card adds a rule here.")
                                                      : Prefs.alwaysCount + (Prefs.alwaysCount === 1 ? Tr.t(" rule") : Tr.t(" rules"))
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    KButton { visible: Prefs.alwaysCount > 0; variant: "danger"; text: Tr.t("Clear"); onClicked: { Prefs.clearAlwaysRules(); root.toast(Tr.t("Rules cleared")) } }
                }
            }

            // ==== what Kisel is joined to: GitHub, Discord ====
            Column {
                visible: root.tab === "services"
                width: parent.width
                spacing: Theme.space3

                // ---- GitHub: a read-only token for the widget ----
                Text { text: "GitHub"; color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Row {
                    spacing: Theme.space2
                    KField {
                        id: ghField
                        width: 280
                        echoMode: TextInput.Password
                        placeholder: GitHub.hasToken ? Tr.t("Token saved in ") + Vault.storeName : Tr.t("Personal access token (read-only)")
                        onAccepted: root.saveGitHub()
                    }
                    KButton { id: ghSave; variant: "primary"; text: Tr.t("Save"); onClicked: root.saveGitHub() }
                    KButton { visible: GitHub.hasToken; variant: "ghost"; text: Tr.t("Remove")
                        onClicked: { Vault.remove("github"); root.toast(Tr.t("GitHub token removed")) } }
                }

                // ---- Discord: "Working with Claude Code" in your profile ----
                // (Off unless switched on: it tells other people what you are doing. Kisel talks
                // only to the Discord running on this computer. See DiscordPresence.)
                Text { text: "Discord"; color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                KToggle { label: Tr.t("Show in Discord that I work with Claude Code"); checked: Prefs.discordOn; onToggled: (v) => Prefs.discordOn = v }
                KToggle { visible: Prefs.discordOn; label: Tr.t("Show the session's name too"); checked: Prefs.discordProject; onToggled: (v) => Prefs.discordProject = v }
                Row { // (Kisel has an application of its own: another is asked for only if Discord turns that one down)
                    visible: Prefs.discordOn && (Discord.state === "noid" || Discord.state === "refused")
                    spacing: Theme.space2
                    KField {
                        id: discordField
                        width: 280
                        placeholder: Prefs.discordAppId !== "" ? "Application ID: " + Prefs.discordAppId : Tr.t("Discord Application ID")
                        onAccepted: root.saveDiscord()
                    }
                    KButton { id: discordSave; variant: "primary"; text: Tr.t("Save"); onClicked: root.saveDiscord() }
                }
                Row {
                    visible: Prefs.discordOn
                    spacing: Theme.space2
                    Icon { name: Discord.state === "on" ? "check" : "cross"; size: 16
                        color: Discord.state === "on" ? Theme.mint : Discord.state === "refused" ? Theme.danger : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: Discord.state === "on" ? Tr.t("Connected to Discord")
                            : Discord.state === "noid" ? Tr.t("Needs an Application ID")
                            : Discord.state === "refused" ? Tr.t("Discord did not take this Application ID")
                            : Tr.t("Discord is not running")
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
                Text {
                    visible: Prefs.discordOn && (Discord.state === "noid" || Discord.state === "refused")
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Tr.t("Discord shows an activity under the name of a Discord application. Make one called Kisel at discord.com/developers/applications, copy its Application ID here, and add a picture named kisel under Rich Presence, Art Assets if you want one. The ID is a public number, not a password.")
                    color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 12
                }
            }

            // ==== who is on stage, and what each of them is tied to ====
            Column {
                visible: root.tab === "cast"
                width: parent.width
                spacing: Theme.space3

                // ---- who is on stage ----
                Text { text: Tr.t("On stage"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Row {
                    spacing: Theme.space2
                    Repeater {
                        model: root.jobs
                        KButton {
                            required property var modelData
                            primary: Prefs.character === modelData.id
                            text: root.names[Prefs.faces[modelData.id]]
                            onClicked: Prefs.character = modelData.id
                        }
                    }
                }

                // ---- who does what: each job goes to one of the five; the one who had it takes
                // the job its new owner leaves, so nobody is left idle and nothing is done twice ----
                Text { text: Tr.t("Who does what"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Repeater {
                    model: root.jobs
                    Column {
                        id: job
                        required property var modelData
                        width: parent.width
                        spacing: 6
                        Row {
                            spacing: Theme.space2
                            height: 28
                            KToggle {
                                visible: job.modelData.id !== "miku"
                                enabled: job.modelData.can
                                opacity: enabled ? 1 : 0.5
                                anchors.verticalCenter: parent.verticalCenter
                                label: job.modelData.name
                                checked: job.modelData.on
                                onToggled: (v) => root.setJob(job.modelData.id, v)
                            }
                            Text { // (Claude Code is what Kisel is for: it has no switch)
                                visible: job.modelData.id === "miku"
                                anchors.verticalCenter: parent.verticalCenter
                                text: job.modelData.name
                                color: Theme.ink; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                        }
                        Row {
                            spacing: 6
                            Repeater {
                                model: ["miku", "rin", "luka", "zunda", "teto"]
                                KButton {
                                    required property string modelData
                                    primary: Prefs.faces[job.modelData.id] === modelData
                                    text: root.names[modelData]
                                    onClicked: { Sfx.play("click"); Prefs.setFace(job.modelData.id, modelData) }
                                }
                            }
                        }
                    }
                }
            }

            // ==== look and sound ====
            Column {
                visible: root.tab === "look"
                width: parent.width
                spacing: Theme.space3

                Row {
                    spacing: Theme.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Theme")
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: [{ id: "system", name: Tr.t("System") }, { id: "dark", name: Tr.t("Dark") }, { id: "light", name: Tr.t("Light") }]
                        KButton {
                            required property var modelData
                            primary: Prefs.theme === modelData.id
                            text: modelData.name
                            onClicked: Prefs.theme = modelData.id
                        }
                    }
                }

                // ---- the interface's language ----
                Row {
                    spacing: Theme.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Language")
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: [{ id: "en", name: "English" }, { id: "ru", name: "\u0420\u0443\u0441\u0441\u043a\u0438\u0439" }]
                        KButton {
                            required property var modelData
                            primary: Tr.lang === modelData.id
                            text: modelData.name
                            onClicked: Prefs.language = modelData.id
                        }
                    }
                }

                KToggle { label: Tr.t("Sounds"); checked: Prefs.soundOn; onToggled: (v) => Prefs.soundOn = v }
                KToggle { label: Tr.t("Reduce motion"); checked: Prefs.reduceMotion; onToggled: (v) => Prefs.reduceMotion = v }
                KSlider {
                    from: 0; to: 10
                    value: Prefs.closeDelay
                    label: Prefs.closeDelay === 0 ? Tr.t("Close at once when the pointer leaves") : Tr.t("Close ") + Prefs.closeDelay + Tr.t(" s after the pointer leaves")
                    onMoved: (v) => Prefs.closeDelay = v
                }
            }

            // ==== where Kisel sits: the monitor, the edge, how far along it ====
            Column {
                visible: root.tab === "place"
                width: parent.width
                spacing: Theme.space3

                // ---- screen: a little map of your monitors, tap one to move Kisel there ----
                Text { text: Tr.t("Screen"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Item {
                    id: map
                    width: parent.width
                    height: 96
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
                            border.color: here ? Theme.kisel : Theme.line
                            scale: tap.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label + (here ? Tr.t(", Kisel is here") : "")
                            Accessible.checked: here

                            // the island, drawn tiny at the top edge of the monitor it is on
                            Rectangle {
                                id: pill
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: -1
                                width: mon.here ? 34 : 0
                                height: mon.here ? 9 : 0
                                radius: 4
                                color: Theme.kisel
                                Behavior on width { NumberAnimation { duration: Theme.tBase; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
                                Behavior on height { NumberAnimation { duration: Theme.tBase; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
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
                                    text: mon.modelData.w + "\u00d7" + mon.modelData.h
                                    color: Theme.inkFaint
                                    font.family: Theme.mono; font.pixelSize: 11
                                }
                            }
                            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: tap; onTapped: { Displays.select(mon.modelData.name); root.toast(Tr.t("Kisel moved to ") + mon.modelData.name) } }
                        }
                    }
                }
                Row {
                    spacing: Theme.space2
                    KButton {
                        visible: Displays.wanted !== ""
                        text: Tr.t("Follow primary")
                        onClicked: { Displays.select(""); root.toast(Tr.t("Following the primary monitor")) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.inkMuted
                        font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                        text: Displays.wanted === "" ? Tr.t("Kisel follows your primary monitor (") + Displays.current + Tr.t("), also after a restart")
                            : Tr.t("Kisel stays on ") + Displays.wanted + Tr.t(", also after a restart")
                    }
                }

                // where the island sits: the edge, and how far along it
                Row {
                    spacing: Theme.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Place")
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: [{ id: "top", name: Tr.t("Top") }, { id: "bottom", name: Tr.t("Bottom") }, { id: "left", name: Tr.t("Left") }, { id: "right", name: Tr.t("Right") }]
                        KButton {
                            required property var modelData
                            primary: Shell.edge === modelData.id
                            text: modelData.name
                            onClicked: root.place(modelData.id, Shell.along / Shell.edgeLength(Shell.edge))
                        }
                    }
                }
                KSlider {
                    id: alongSlider
                    from: 0; to: 20
                    value: Math.round(Shell.along / Shell.edgeLength(Shell.edge) * 20)
                    label: value === 10 ? Tr.t("In the middle of the edge") : (Shell.edge === "left" || Shell.edge === "right" ? (value < 10 ? Tr.t("Toward the top") : Tr.t("Toward the bottom")) : (value < 10 ? Tr.t("Toward the left") : Tr.t("Toward the right")))
                    onMoved: (v) => root.place(Shell.edge, v / 20)
                }
                KToggle { label: Tr.t("Start when I sign in"); checked: Shell.autostart; onToggled: (v) => Shell.autostart = v }
                KToggle { visible: Shell.canAvoidPanels; label: Tr.t("Stay clear of the taskbar"); checked: Prefs.avoidPanels; onToggled: (v) => Prefs.avoidPanels = v }
            }

            // ==== Kisel itself: updates, quit ====
            Column {
                visible: root.tab === "kisel"
                width: parent.width
                spacing: Theme.space3

                // ---- updates: Kisel asks GitHub at start and once a day (one question, nothing
                // about you in it), unless that is switched off; it installs nothing by itself ----
                Text { visible: Updates.available; text: Tr.t("Updates"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
                Row {
                    visible: Updates.available
                    spacing: Theme.space2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 250)
                        wrapMode: Text.WordWrap
                        text: Updates.state === "checking" ? Tr.t("Asking GitHub...")
                            : Updates.state === "current" ? "Kisel " + Updates.current + Tr.t(" is the newest")
                            : Updates.state === "found" ? "Kisel " + Updates.latest + Tr.t(" is out (you have ") + Updates.current + ")"
                            : Updates.state === "downloading" ? Tr.t("Downloading ") + Updates.latest + "  " + Math.round(Updates.progress * 100) + "%"
                            : Updates.state === "starting" ? Tr.t("Installing. Kisel will be right back.")
                            : "Kisel " + Updates.current
                        color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
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
                KToggle { visible: Updates.available; label: Tr.t("Check for updates by itself"); checked: Prefs.updateCheck; onToggled: (v) => Prefs.updateCheck = v }
                Rectangle { // the download, as it comes
                    visible: Updates.state === "downloading"
                    width: 280; height: 6; radius: 3
                    color: Theme.surface3
                    Rectangle { width: parent.width * Updates.progress; height: parent.height; radius: 3; color: Theme.kisel }
                }
                Text {
                    visible: Updates.available && Updates.state === "failed"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Tr.d(Updates.error)
                    color: Theme.danger; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
                }

                KButton { text: Tr.t("Quit Kisel"); variant: "danger"; onClicked: Shell.quit() }
                Item { width: 1; height: Theme.space2 }
            }
        }
    }

    function saveDiscord() {
        const id = discordField.text.trim()
        if (!/^[0-9]{15,22}$/.test(id)) {
            note = Tr.t("An Application ID is a long number")
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
            note = Tr.t("Couldn't reach ") + Vault.storeName
        }
    }
}
