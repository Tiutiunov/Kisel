// The island: a dark pill docked to one edge of the screen that grows into a card,
// or (floating) a mascot that lives free on the desktop and opens its card in
// place. Sizes, timings and behaviour follow motion.md.
//
//   docked   on top, bottom, left or right: collapsed 288 x 32, Coucou's compact bar,
//            with Kisel wholly inside it (32 x 248 on the sides) -> home 660x200 | session 300 | permission 236/310/290 | github
//            276 | chat 412 | settings 440. The bar's size and manners follow Coucou's
//            island: a click opens it (280 ms OutCubic), it closes a moment after the
//            pointer leaves (Settings: at once to 10 s) unless something holds it open, and after a minute with
//            nothing to show it slides into the edge; touching the edge there, or any
//            activity, brings it back.
//   floating the mascot (120 px) is the whole window; click opens the card where it
//            stands, click again or the close icon closes it. It wanders while idle.
//   picking up  (switched off: `canPickUp`. The island is moved from Settings, "Place".)
//            Hold the mascot for 350 ms: a ring fills, then Kisel is drawn out of
//            the pill on a jelly neck. Carry it anywhere; near an edge a zone shows,
//            and letting go there docks it on that edge. Letting go elsewhere drops
//            it. Walls resist; a seam between two monitors lets it move across.
import QtQuick
import Kisel.Core

Item {
    id: root

    property string view: "home"
    property bool expanded: false
    property bool autoOpened: false   // opened by an event, not by the pointer
    property bool dropActive: false   // a file is being dragged over
    property bool dropHappy: false
    readonly property bool floating: Shell.floating
    // Holding the mascot no longer draws it out of the bar: where the island sits is
    // chosen in Settings. The carrying code below stays for the day it is wanted again.
    readonly property bool canPickUp: false
    readonly property real isoX: Shell.viewWide ? Shell.grabX : Shell.originX // the island's origin on the output
    readonly property real isoY: Shell.viewWide ? Shell.grabY : Shell.originY

    function showToast(text) { toast.show(text) }

    // ---- geometry --------------------------------------------------------------
    readonly property int viewHeight: {
        switch (view) {
        case "session": return 300
        case "permission": return Hub.permission.kind === "diff" ? 310 : Hub.permission.kind === "question" ? 298 : 236
        case "github": return 276
        case "chat": return 412
        case "settings": return 440
        default: return 200
        }
    }
    // ---- where the island is: an edge, or floating ---------------------------------
    readonly property string edge: Shell.edge
    readonly property bool vertical: !floating && (edge === "left" || edge === "right")
    readonly property bool atBottom: !floating && edge === "bottom"
    readonly property string dockSide: floating || barAir ? "none" : edge // (in the hand the bar is round all over)
    // Collapsed: Coucou's compact bar, 288 x 32 with 14 px corners; a 32 x 248 one on the
    // sides; the mascot alone (120 px) while floating. Kisel sits inside the bar, 4 px
    // clear of its edges, and never reaches out of it.
    readonly property int pillT: 32      // the bar's thickness
    readonly property int mini: 24       // the mascot in the bar
    readonly property int miniPad: (pillT - mini) / 2
    readonly property int miniLead: 14   // from the bar's leading end to the mascot
    // On a side edge the bar stands on end, its long side on the edge, and everything in
    // it goes one under another: the head of the bar is its top, the bench its bottom,
    // and whatever moves along the lying bar moves down this one (`vertical`).
    readonly property int sideH: 248     // the standing bar's length
    readonly property int sideBenchH: 4 * 16 + 10
    readonly property int inward: edge === "right" ? -1 : 1 // (which way the screen is from a side edge)
    readonly property int pillMin: 288 + Math.round(duoW + heraldW) // (a little wider while two sit at its head, or Rin holds up her sign)
    readonly property int pillMax: 288 + Math.round(duoW + heraldW)
    readonly property int labelX: miniLead + mini + 10 + Math.round(duoW + heraldW)
    // The cast. One of them is the mascot; the other four wait at the bar's far end, two
    // by two, as Coucou keeps its other agents, and a click on one swaps her in.
    readonly property var cast: ["miku", "rin", "luka", "zunda", "teto"]
    // Who is on stage: whoever has something to show.
    //   Miku is Claude Code's. She does not stand there for as long as Claude works (that
    //   can be an hour): she steps in for a few seconds when there is news (a task begins,
    //   Claude turns to another session, a task is done) and stays while a request waits
    //   for an answer. Then she goes.
    //   Zundamon is Spotify's: while a tune plays she has something to show.
    // So with Miku chosen and music on, the stage is Zundamon's between Miku's visits, and
    // the two keep changing places. Anyone else who was chosen simply stays (and Miku
    // still visits); with no music the chosen one is who you see.
    property string guest: ""
    readonly property bool zundaLive: Prefs.zundaSpotify && Media.available && Media.active && Media.playing
    // (Picking Miku by hand in the open card is a wish to see Miku and Claude's Home, music
    // or not: she stays until the card closes. `mikuPinned`.)
    property bool mikuPinned: false
    readonly property string chosen: Prefs.character
    onChosenChanged: mikuPinned = chosen === "miku" && expanded
    //   Teto is the computer's: she has something to show when it is in trouble (the
    //   processor flat out or the memory full), and that comes
    //   before music.
    //   (...or when the memory has just been cleaned: she comes to say what was freed)
    readonly property bool tetoLive: Prefs.tetoSystem && Sys.available && (Sys.strain || Sys.cleaning || Sys.justCleaned)
    //   Luka is the connection's: she has something to show when the line is down or
    //   slow, and for a few seconds after it comes back. That comes after Teto's troubles
    //   and before music.
    readonly property bool lukaLive: Prefs.lukaNet && Net.available && (Net.trouble || Net.justBack)
    //   (...and while something is being downloaded, and for a few seconds after: but
    //   that is no trouble, and gives way to music)
    readonly property bool lukaBusy: Prefs.lukaNet && Net.available && (Speed.running || Speed.justDone || ((Net.downloading || Net.justFetched) && !Speed.busy))
    //   And when a minute has passed with nothing to show while a tune plays, the stage
    //   goes to Zundamon and her player whoever was chosen (`idleTune`), until Claude
    //   works again or someone is picked by hand. With no tune the bar tucks away instead.
    property bool idleTune: false
    //   A click on Miku herself in the bar (while she visits, or sits there as the
    //   partner) is a wish for Miku and Claude's Home, not for whoever rests: the card
    //   opens hers and stays hers until it closes (`mikuAsked`).
    property bool mikuAsked: false
    readonly property string rest: mikuAsked ? "miku" : idleTune && zundaLive ? "zunda"
        : Prefs.character !== "miku" || mikuPinned ? Prefs.character
        : tetoLive ? "teto" : lukaLive ? "luka" : zundaLive ? "zunda" : lukaBusy ? "luka" : "miku"
    // (When Kisel starts it is Miku who comes out to say hello, whoever was chosen: she
    // is its face. Once she is in the bar the chosen one takes over from her as after any
    // visit of hers. `opened` is false until then.)
    property bool opened: false
    readonly property bool opening: greeting || assembling
    function openedNow() {
        if (opened) return
        if (rest !== "miku") { guest = "miku"; guestTimer.restart() }
        opened = true
    }
    onOpeningChanged: if (!opening) openedNow()
    Timer { interval: 2500; running: true; onTriggered: if (!root.opening) root.openedNow() } // (started without a greeting)
    // (The chat is Miku's too, whoever was chosen: it is Claude one talks to there, and
    // she sits in it with his little one in her arms.)
    readonly property bool inChat: expanded && view === "chat"
    // (A click on the partner in the bar is a wish for her card, not for Miku's, though
    // Miku has the stage while Claude works: the card opens hers and stays hers until it
    // closes (`askedWho`), as a click on Miku opens Miku's.)
    property string askedWho: ""
    function hasCard(who) {
        return who === "zunda" ? Prefs.zundaSpotify && Media.available
             : who === "teto" ? Prefs.tetoSystem && Sys.available
             : who === "luka" ? Prefs.lukaNet && Net.available : false
    }
    readonly property string stage: !opened || inChat ? "miku" : askedWho !== "" && Hub.pendingCount === 0 ? askedWho : guest !== "" ? guest : rest // (a request waiting is Miku's to show, whoever was asked for)
    function stepIn() {
        if (rest === "miku") return
        guest = "miku"
        guestTimer.restart()
    }
    // picked by hand, from the bench or in Settings
    function choose(who) {
        Prefs.character = who
        idleTune = false
        guest = ""
        mikuAsked = false; askedWho = "" // (a pick by hand is the latest word on whose card it is)
        mikuPinned = who === "miku" && expanded
        if (who === "miku") stepIn() // (with music on the stage is Zundamon's: Miku at least comes out to say hello)
    }
    Timer { id: guestTimer; interval: 3000
        // (she also stays for as long as her "Done" is up: it is her news; and for as long as
        // Claude works: the bar and the card are hers then, whoever was chosen, and the
        // chosen one keeps her company. Picking someone from the bench by hand still wins.)
        onTriggered: { if (Hub.pendingCount > 0 || (root.doneHold && Hub.chip === "done") || root.claudeBusy) restart(); else root.guest = "" } }
    readonly property string sessionId: Hub.session.id || ""
    onSessionIdChanged: if (sessionId !== "") { Relay.watch(sessionId); stepIn() } // (its inbox, for prompts typed here: see SessionView)
    readonly property bool claudeBusy: Hub.mood === "work" || Hub.mood === "think"
    onClaudeBusyChanged: if (claudeBusy) { idleTune = false; stepIn() }
    // The chosen one with a service of her own (Zundamon with Spotify) minds that service:
    // Claude's working is Miku's news, not hers.
    readonly property bool ownAct: opened && guest === "" && rest === "zunda" && Prefs.zundaSpotify && Media.available
    readonly property var benchAfter: cast.filter(c => c !== stage && !(duo && c === buddyWho) && !(heraldRin && c === "rin"))
    readonly property var bench: benchAfter.filter(c => !flying.includes(c)) // (whoever is in the air has not sat down yet)

    // ---- a dance to the tune ----------------------------------------------------------
    // The bench sits as it always does. But when two or three are at the head of the bar
    // and a tune is playing, now and then (between their other scenes, every eight to
    // fourteen seconds) they dance to it together: humming, they step from side to side as
    // one, hopping in turn, then all jump at once and finish with a wave down the row.
    property bool lastDance: false
    function row() { return [mascot].concat(duo ? [buddy] : []).concat(heraldRin ? [herald] : []) }
    function hopRow(odd) { row().forEach((m, i) => { if (i % 2 === odd) m.jump(0.4, true) }) }
    readonly property bool canGroove: zundaLive && (duo || heraldRin) && !expanded && !floating && !mfree
        && !tucked && !assembling && !greeting && !Theme.reduced
    onCanGrooveChanged: if (!canGroove && (skGroove.running || skDisco.running)) { stopDances(); mainDx = 0; buddyDx = 0; heraldDx = 0 }
    Timer {
        interval: 12000
        repeat: true
        running: root.canGroove
        onTriggered: {
            interval = 25000 + Math.random() * 20000
            let busy = skTrade.running || sweeping || noteWave.running || flying.length > 0 || arriving.length > 0
            for (const k of root.skits) busy = busy || k.running
            for (const k of root.noteSkits) busy = busy || k.running
            if (busy) interval = 900 // (a scene is on: straight after it)
            else { root.duoLook = false; root.lastDance = !root.lastDance; (root.lastDance ? skDisco : skGroove).restart() } // (the two take turns)
        }
    }
    SequentialAnimation {
        id: skGroove
        ScriptAction { script: root.row().forEach(m => { m.play("sing", 3600) }) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.hopRow(0) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.hopRow(1) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.hopRow(0) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.hopRow(1) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: 2; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.hopRow(0) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: -2; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.hopRow(1) }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: 0; duration: 210; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 210; easing.type: Easing.InOutSine } }
        ScriptAction { script: root.row().forEach(m => { m.jump(0.7, true); m.play("smug", 1000) }) } // (all up at once, with a spin)
        PauseAnimation { duration: 520 }
        ScriptAction { script: { const r = root.row(); r[r.length - 1].jump(0.35, true) } }
        PauseAnimation { duration: 140 }
        ScriptAction { script: { const r = root.row(); if (r.length > 2) r[1].jump(0.35, true) } }
        PauseAnimation { duration: 140 }
        ScriptAction { script: { root.row()[0].jump(0.35, true) } }
        PauseAnimation { duration: 300 }
    }

    // The other dance, and the plainer of the two to read as one: notes rise over their
    // heads the whole time (`discoOn`), they lean from side to side in time, neighbours
    // opposite ways (`lean`), hopping in turn; then each spins once, one after another
    // down the row; all that a second time, the other way round; a last lean each way,
    // and they all jump. (About nine seconds.)
    property real lean: 0
    property bool discoOn: false
    function stopDances() { skGroove.stop(); skDisco.stop(); lean = 0; discoOn = false }
    SequentialAnimation {
        id: skDisco
        ScriptAction { script: root.discoOn = true }
        ScriptAction { script: root.row().forEach(m => m.play("sing", 2300)) }
        NumberAnimation { target: root; property: "lean"; to: 8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(0) }
        NumberAnimation { target: root; property: "lean"; to: -8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(1) }
        NumberAnimation { target: root; property: "lean"; to: 8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(0) }
        NumberAnimation { target: root; property: "lean"; to: -8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(1) }
        NumberAnimation { target: root; property: "lean"; to: 0; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: { const m = root.row()[0]; m.play("smug", 750); m.jump(0.55, true) } }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { const m = root.row()[1]; if (m) { m.play("smug", 750); m.jump(0.55, true) } } }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { const m = root.row()[2]; if (m) { m.play("smug", 750); m.jump(0.55, true) } } }
        PauseAnimation { duration: 450 }
        ScriptAction { script: root.row().forEach(m => m.play("sing", 2300)) }
        NumberAnimation { target: root; property: "lean"; to: -8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(0) }
        NumberAnimation { target: root; property: "lean"; to: 8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(1) }
        NumberAnimation { target: root; property: "lean"; to: -8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(0) }
        NumberAnimation { target: root; property: "lean"; to: 8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(1) }
        NumberAnimation { target: root; property: "lean"; to: 0; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: { const m = root.row()[0]; m.play("smug", 750); m.jump(0.55, true) } }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { const m = root.row()[1]; if (m) { m.play("smug", 750); m.jump(0.55, true) } } }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { const m = root.row()[2]; if (m) { m.play("smug", 750); m.jump(0.55, true) } } }
        PauseAnimation { duration: 450 }
        ScriptAction { script: root.row().forEach(m => m.play("sing", 1200)) }
        NumberAnimation { target: root; property: "lean"; to: 8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(0) }
        NumberAnimation { target: root; property: "lean"; to: -8; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.hopRow(1) }
        NumberAnimation { target: root; property: "lean"; to: 0; duration: 230; easing.type: Easing.InOutSine }
        ScriptAction { script: root.row().forEach(m => { m.jump(0.75, true); m.play("hype", 1000) }) }
        PauseAnimation { duration: 750 }
        ScriptAction { script: root.discoOn = false }
    }

    // ---- back to the bench ------------------------------------------------------------
    // Nobody who leaves the head of the bar just vanishes: she somersaults over it, in an
    // arc, to her seat on the bench at the far end, and lands there. That goes for the
    // partner when Claude's work is done, for the one on stage when another takes her
    // place, and for Rin when her notifications have been looked at. (Several may be in the air at once.)
    // (Each of the five has a double that does the flying, kept ready and out of sight:
    // one made on the spot would first play its own coming-in. `flying` names those in the air.)
    property var flying: []
    function launch(who, fromX) {
        if (who === "" || expanded || floating || mfree || tucked || assembling || greeting || Theme.reduced) return
        if (head.includes(who) || flying.includes(who)) return // (`head` is fresh here; other bindings may not have caught up)
        const f = flyers.itemAt(cast.indexOf(who))
        if (!f) return
        flying = flying.concat([who])
        f.go(fromX)
    }
    function landed(who) { flying = flying.filter(c => c !== who); arriving = arriving.filter(c => c !== who) }
    function groundAll() { for (let i = 0; i < flyers.count; ++i) { const f = flyers.itemAt(i); if (f) f.stop() } flying = []; arriving = [] }
    // ...and nobody just appears at the head either: she comes the same way, off her seat
    // on the bench and over the bar to her place (`arriving`; her place stays empty until
    // she lands). `role` says which place: "main", "buddy" or "herald".
    property var arriving: []
    property var benchWas: []
    function launchIn(who, role) {
        if (who === "" || expanded || floating || mfree || tucked || assembling || greeting || Theme.reduced) return
        const seat = benchWas.indexOf(who)
        if (seat < 0 || flying.includes(who) || arriving.includes(who)) return
        const f = flyers.itemAt(cast.indexOf(who))
        if (!f) return
        arriving = arriving.concat([who])
        f.come(seat, role)
    }
    // (who sat where a moment ago)
    // Who is at the head of the bar, and where each of them sits. Whenever that changes,
    // whoever was there and no longer is takes off from where she sat.
    readonly property var head: [stage].concat(duo ? [buddyWho] : []).concat(heraldRin ? ["rin"] : [])
    property var headWas: []
    property var headX: ({})
    function farEnd() { return vertical ? card.y + card.height : card.x + card.width }
    function alongOf(it) { return vertical ? it.y : it.x }
    function headSeats() {
        // (measured from the bar's far end, which stays put while the bar changes width)
        const m = {}, r = farEnd()
        m[stage] = alongOf(mascot) - side * mainDx - r
        if (duo) m[buddyWho] = alongOf(buddy) - side * buddyDx - r
        if (heraldRin) m["rin"] = alongOf(herald) - heraldDx - r
        return m
    }
    onHeadChanged: {
        stopOwn() // (whoever was in a scene of her own may be leaving)
        for (const c of headWas) if (!head.includes(c)) launch(c, headX[c] !== undefined ? farEnd() + headX[c] : alongOf(mascot))
        for (const c of head) if (!headWas.includes(c)) launchIn(c, c === stage ? "main" : duo && c === buddyWho ? "buddy" : "herald")
        headWas = head
        benchWas = cast.filter(c => !head.includes(c)) // (not `benchAfter`: that binding may not have caught up yet)
        headX = headSeats()
    }
    Timer { interval: 0; running: true; onTriggered: { root.headWas = root.head; root.headX = root.headSeats(); root.benchWas = root.benchAfter } }

    // ---- Rin and the notifications --------------------------------------------------
    // Rin is the notifications'. While Windows holds one that has not been looked at she
    // stands at the head of the bar, after whoever is there already (second, or third
    // while two are at work), and waves a sign with the name of the program it came
    // from. The one on stage gets a partner for it as well (as while Claude works), so
    // there are three of them. The sign is held up out of the bar (above it, or below a bar on the top
    // edge), so the bar only makes room for Rin herself. None of them stands still: every
    // few seconds a little scene plays among the three (`noteScene`), between the scenes
    // the first two have of their own. A click on her or her sign counts as looking: it opens the
    // notification centre and she goes back to the bench.
    // (A new version of Kisel is hers to announce as well: the sign reads "Kisel 0.3.0".
    // A click on her then opens Settings at "Updates", and she does not bring that
    // version up again.)
    readonly property bool updateUp: Updates.available && Updates.state === "found" && Prefs.updateSeen !== Updates.latest
    readonly property bool notesOn: Prefs.rinNotes && Notes.available && Notes.pending
    readonly property bool noteAny: notesOn || updateUp
    readonly property var signApps: (updateUp ? ["Kisel " + Updates.latest] : []).concat(notesOn ? Notes.apps : [])
    readonly property var signCounts: (updateUp ? [1] : []).concat(notesOn ? Notes.counts : [])
    function openNote() {
        if (!updateUp) { Notes.open(); return }
        Prefs.updateSeen = Updates.latest
        view = "settings"
        autoOpened = false
        open()
        settingsView.showUpdates()
    }
    readonly property bool note: noteAny
        && !expanded && !floating && !mfree && !assembling && !greeting
    // (if Rin is at the head already, on stage or as the partner, the sign is simply hers)
    readonly property bool heraldRin: note && stage !== "rin" && !(duo && buddyWho === "rin")
    property real heraldSeat: heraldRin ? mini + 3 : 0 // (she is the size of the one on stage)
    Behavior on heraldSeat { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    property real heraldW: heraldRin ? mini + 3 : 0
    Behavior on heraldW { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    readonly property Item rinNow: stage === "rin" ? mascot : duo && buddyWho === "rin" ? buddy : herald
    property int lastNoteScene: -1
    property int lastNoteSkit: -1
    // the other two (or the one), nearest to Rin first
    function noteOthers() {
        const r = rinNow, all = duo ? [buddy, mascot] : [mascot]
        return all.filter(m => m !== r)
    }
    function noteScene() {
        if (skTrade.running || sweeping || noteWave.running || skGroove.running || skDisco.running || ownRunning()) return
        for (const k of skits) if (k.running) return
        for (const k of noteSkits) if (k.running) return
        if (Math.random() < 0.2 && playToy()) return
        if (Math.random() < 0.3 && playOwn()) return
        // Rin seated after the others: mostly the scenes with her in them bodily
        if (rinNow === herald && herald.pop > 0.9 && Math.random() < 0.75) {
            let n = Math.floor(Math.random() * noteSkits.length)
            if (n === lastNoteSkit) n = (n + 1) % noteSkits.length
            lastNoteSkit = n
            mainDx = 0; buddyDx = 0
            duoLook = true; duoLookOff.restart()
            noteSkits[n].restart()
            return
        }
        const r = rinNow, o = noteOthers(), a = o[0] || null, b = o[1] || null
        let i = Math.floor(Math.random() * 9)
        if (i === lastNoteScene) i = (i + 1) % 9
        lastNoteScene = i
        duoLook = true; duoLookOff.restart()
        if (i === 0) { r.jump(0.7, true); r.play("hype", 1200); for (const m of o) m.play("surprised", 900) }      // look, look
        else if (i === 1) { r.play("hello", 1300); if (a) a.play("hello", 1100); if (b) b.play("surprised", 900) } // over here
        else if (i === 2) noteWave.restart()                                                                       // a wave down the row and back
        else if (i === 3) { r.play("angry", 1100); if (a) a.play("unimpressed", 1300); if (b) b.play("flustered", 1100) } // will you look already
        else if (i === 4) { r.play("laugh", 1200); for (const m of o) m.play("laugh", 1200) }
        else if (i === 5) { r.st.sqv += 6; if (a) a.play("fond", 1100); if (b) b.st.sqv += 4 }
        else if (i === 6) { r.jump(0.6, true); for (const m of o) m.jump(0.5, true); r.play("hype", 1000) }        // all three at once
        else if (i === 7) { r.play("proud", 1300); for (const m of o) m.play("hype", 1000) }                       // they cheer her sign
        else { if (a) { a.play("love", 1200); a.jump(0.3, false) } r.play("flustered", 1200); if (b) b.play("laugh", 1100) } // one of them is too fond of her
    }
    // ...and the scenes the three have together, with Rin in them bodily (she is the
    // third in the row: `heraldDx` slides her, `heraldPop` ducks her; the sign goes
    // where she goes). These play when all three are seated; otherwise the faces above.
    property real heraldDx: 0
    property real heraldPop: 1
    readonly property real seatW: mini + 3
    readonly property var noteSkits: [nkBump, nkSwap, nkLeap, nkToss, nkHuddle, nkConga, nkPeek, nkChase]
    function stopNoteSkits() { for (const k of noteSkits) k.stop(); noteWave.stop(); stopDances(); heraldDx = 0; heraldPop = 1; nbDx = 0; farDx = 0; mainDx = 0; buddyDx = 0; tossA = 0 }
    // Rin is last in the row; `nb` is her neighbour (the partner, or with no partner the
    // one on stage) and `far` the one beyond (only while there are three). Their slides
    // go through `nbDx` and `farDx`, which pass them on to whoever that is.
    readonly property int rowN: duo ? 2 : 1 // Rin's place in the row, counted from the head
    function nb() { return !duo ? mascot : mikuLeft ? mascot : buddy }
    function far() { return !duo ? null : mikuLeft ? buddy : mascot }
    property real nbDx: 0
    property real farDx: 0
    onNbDxChanged: if (!duo) mainDx = nbDx; else if (mikuLeft) mainDx = -nbDx; else buddyDx = nbDx
    onFarDxChanged: if (duo) { if (mikuLeft) buddyDx = -farDx; else mainDx = farDx }
    // Rin barges into her neighbour, who bumps into the next: dominoes
    SequentialAnimation {
        id: nkBump
        NumberAnimation { target: root; property: "heraldDx"; to: -8; duration: 120; easing.type: Easing.InQuad }
        ScriptAction { script: { const n = root.nb(); n.st.sqv += 7; n.st.shake = 0.6; n.play("surprised", 800) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 280; easing.type: Easing.OutBack } NumberAnimation { target: root; property: "nbDx"; to: -6; duration: 120; easing.type: Easing.InQuad } }
        ScriptAction { script: { const f = root.far(); if (f) { f.st.sqv += 6; f.st.shake = 0.5; f.play("surprised", 800) } } }
        NumberAnimation { target: root; property: "nbDx"; to: 0; duration: 280; easing.type: Easing.OutBack }
        PauseAnimation { duration: 250 }
        ScriptAction { script: { herald.play("laugh", 1000); herald.jump(0.4, true) } }
    }
    // Rin and her neighbour jump over each other, and after a moment jump back
    SequentialAnimation {
        id: nkSwap
        ScriptAction { script: { herald.jump(1, true); root.nb().jump(0.8, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: -root.seatW; duration: 420; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "nbDx"; to: root.seatW; duration: 420; easing.type: Easing.InOutCubic } }
        ScriptAction { script: { herald.play("hype", 1000); root.nb().play("laugh", 1000); const f = root.far(); if (f) f.play("surprised", 800) } }
        PauseAnimation { duration: 1500 }
        ScriptAction { script: { herald.jump(1, true); root.nb().jump(0.8, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 420; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "nbDx"; to: 0; duration: 420; easing.type: Easing.InOutCubic } }
    }
    // Rin leaps to the head of the row and the others shuffle along; then back
    SequentialAnimation {
        id: nkLeap
        ScriptAction { script: { herald.jump(1.2, true); herald.play("hype", 1400) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: -root.rowN * root.seatW; duration: 480; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "nbDx"; to: root.seatW; duration: 480; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "farDx"; to: root.seatW; duration: 480; easing.type: Easing.InOutCubic } }
        ScriptAction { script: { mascot.play("unimpressed", 1200); if (root.duo) buddy.play("laugh", 1000); herald.st.sqv += 6 } }
        PauseAnimation { duration: 1600 }
        ScriptAction { script: { herald.jump(1.2, true); mascot.jump(0.4, true); if (root.duo) buddy.jump(0.4, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 480; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "nbDx"; to: 0; duration: 480; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "farDx"; to: 0; duration: 480; easing.type: Easing.InOutCubic } }
    }
    // a star from Rin down the row and all the way back
    SequentialAnimation {
        id: nkToss
        ScriptAction { script: { root.tossBySeat = true; root.tossU = root.rowN; root.tossA = 1; herald.st.sqv += 4 } }
        NumberAnimation { target: root; property: "tossU"; to: root.rowN - 1; duration: 380; easing.type: Easing.InOutSine }
        ScriptAction { script: { const n = root.nb(); n.jump(0.45, true); n.play("hype", 700) } }
        NumberAnimation { target: root; property: "tossU"; to: 0; duration: 380; easing.type: Easing.InOutSine }
        ScriptAction { script: { const h = root.far() || root.nb(); h.jump(0.45, true); h.play("laugh", 800) } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: { (root.far() || root.nb()).st.sqv += 5 } }
        NumberAnimation { target: root; property: "tossU"; to: root.rowN; duration: 620; easing.type: Easing.InOutSine }
        ScriptAction { script: { herald.jump(0.6, true); herald.play("proud", 1000) } }
        NumberAnimation { target: root; property: "tossA"; to: 0; duration: 180; easing.type: Easing.OutCubic }
    }
    // they all lean in, a star where they meet
    SequentialAnimation {
        id: nkHuddle
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 5; duration: 150; easing.type: Easing.OutQuad } NumberAnimation { target: root; property: "heraldDx"; to: -5; duration: 150; easing.type: Easing.OutQuad } }
        ScriptAction { script: { root.tossBySeat = true; root.tossU = root.rowN / 2; root.tossA = 1; for (const m of [mascot, buddy, herald]) { m.st.sqv += 6; m.play("laugh", 900) } } }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 260; easing.type: Easing.OutBack } NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 260; easing.type: Easing.OutBack } NumberAnimation { target: root; property: "tossA"; to: 0; duration: 460; easing.type: Easing.OutCubic } }
    }
    // a little line dance: they sway one after another and hop
    SequentialAnimation {
        id: nkConga
        ScriptAction { script: { for (const m of [mascot, buddy, herald]) { m.st.swing = 1; m.play("hum", 1900) } } }
        NumberAnimation { target: root; property: "heraldDx"; to: 4; duration: 200; easing.type: Easing.InOutSine }
        ScriptAction { script: { herald.jump(0.35, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 200; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "nbDx"; to: 4; duration: 200; easing.type: Easing.InOutSine } }
        ScriptAction { script: { root.nb().jump(0.35, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "nbDx"; to: 0; duration: 200; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "farDx"; to: 4; duration: 200; easing.type: Easing.InOutSine } }
        ScriptAction { script: { mascot.jump(0.35, true) } }
        NumberAnimation { target: root; property: "farDx"; to: 0; duration: 200; easing.type: Easing.InOutSine }
        ScriptAction { script: { for (const m of [mascot, buddy, herald]) m.jump(0.45, true) } }
        PauseAnimation { duration: 300 }
    }
    // Rin ducks out of sight; the others look for her; up she pops
    SequentialAnimation {
        id: nkPeek
        NumberAnimation { target: root; property: "heraldPop"; to: 0; duration: 200; easing.type: Easing.InBack }
        PauseAnimation { duration: 350 }
        ScriptAction { script: { buddy.play("surprised", 900); mascot.play("surprised", 900) } }
        PauseAnimation { duration: 650 }
        ScriptAction { script: { herald.jump(0.9, true); herald.play("hype", 1100) } }
        NumberAnimation { target: root; property: "heraldPop"; to: 1; duration: 300; easing.type: Easing.OutBack }
        ScriptAction { script: { const n = root.nb(); n.jump(0.5, true); n.st.shake = 0.5; const f = root.far(); if (f) f.jump(0.4, true) } }
    }
    // her neighbour goes after Rin, Rin dodges away and comes back laughing
    SequentialAnimation {
        id: nkChase
        ScriptAction { script: { root.nb().play("annoyed", 1300) } }
        NumberAnimation { target: root; property: "nbDx"; to: 7; duration: 160; easing.type: Easing.InQuad }
        ScriptAction { script: { herald.jump(0.6, true); herald.play("laugh", 1200) } }
        ParallelAnimation { NumberAnimation { target: root; property: "heraldDx"; to: 9; duration: 160; easing.type: Easing.OutQuad } NumberAnimation { target: root; property: "nbDx"; to: 0; duration: 300; easing.type: Easing.OutBack } }
        PauseAnimation { duration: 350 }
        NumberAnimation { target: root; property: "heraldDx"; to: 0; duration: 320; easing.type: Easing.OutBack }
        ScriptAction { script: { const f = root.far(); if (f) f.play("laugh", 900) } }
    }
    SequentialAnimation {
        id: noteWave
        ScriptAction { script: root.rinNow.jump(0.5, true) }
        PauseAnimation { duration: 150 }
        ScriptAction { script: { const o = root.noteOthers(); if (o[0]) o[0].jump(0.45, true) } }
        PauseAnimation { duration: 150 }
        ScriptAction { script: { const o = root.noteOthers(); if (o[1]) o[1].jump(0.45, true) } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: { const o = root.noteOthers(); if (o[0]) o[0].jump(0.35, true) } }
        PauseAnimation { duration: 150 }
        ScriptAction { script: { root.rinNow.jump(0.6, true); root.rinNow.play("laugh", 900) } }
    }
    onNoteChanged: { updateHit(); if (note) { rinNow.jump(0.8, true); if (stage !== "rin") mascot.play("surprised", 900) } else { stopNoteSkits(); mainDx = 0; buddyDx = 0; tossA = 0 } }
    Timer {
        interval: 9000
        repeat: true
        running: root.note && !Theme.reduced && !root.tucked
        onTriggered: { interval = 14000 + Math.random() * 12000; root.noteScene() }
    }

    // ---- two at work ----------------------------------------------------------------
    // While Claude works the bar holds two of them at its head, side by side (Miku is the
    // one working; the other keeps her company): whoever is
    // on stage and a partner (Miku, or if Miku is the one on stage, the one who rests or
    // the first on the bench). They do not just sit there: every few seconds a little
    // scene plays between them (see `skits`). The bar grows by the partner's width.
    // (A notification does not bring a partner: Miku sits there only while Claude works.
    // With Rin and her sign that makes two at rest and three at work.)
    readonly property bool noteUp: noteAny
    readonly property bool duo: claudeBusy && !expanded && !floating && !mfree && !assembling && !greeting
    readonly property string buddyWho: stage !== "miku" ? "miku" : rest !== "miku" ? rest : "rin"
    // Miku is the one working, and she works at the head of the bar: when somebody else
    // is on stage and Miku is the partner, Miku takes the first seat and the one on stage
    // the second (`mikuLeft`). Everything the two do between them is written for "the one
    // on stage on the left"; with the seats changed over it is simply mirrored (`side`).
    readonly property bool mikuLeft: duo && buddyWho === "miku"
    readonly property int side: mikuLeft ? -1 : 1
    // the star that is passed along: `tossU` counts from the one on stage to her partner
    // (the scenes for two), or along the seats from the head of the bar (`tossBySeat`: Rin's)
    property bool tossBySeat: false
    function tossX(u) { return tossBySeat || !mikuLeft ? u : 1 - u }
    property real duoW: duo ? mini + 3 : 0 // (the partner is the size of the one on stage)
    Behavior on duoW { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    property bool duoLook: false // they are looking at each other
    Timer { id: duoLookOff; interval: 2000; onTriggered: root.duoLook = false }
    // What they do between them. Each scene is a short sequence: emotes, hops and squashes
    // on either of them, the two sliding toward or past each other (`mainDx`, `buddyDx`),
    // the partner ducking (`buddyPop`), and a star that passes between them (`tossU`,
    // `tossA`). One plays every quarter to half a minute (they are company, not a show), never the same twice in a row.
    property real mainDx: 0
    property real buddyDx: 0
    property real buddyPop: 1
    property real tossU: 0 // the star: 0 at her, 1 at the partner
    property real tossA: 0
    property int lastSkit: -1
    readonly property var skits: [skWave, skNod, skStartle, skHum, skQuirk, skRoll, skBump, skSwap, skFive, skLove, skPeek, skSquabble, skToss, skDoze, skDance, skCheer]
    // ---- the scenes of their own ----------------------------------------------------------
    // Each of the five has one that is hers, with whoever sits next to her (`ownA` does it
    // to `ownB`). Teto is laughed at, takes her broom and raises it, and the other one
    // cowers. Miku conducts with her leek and the other sings along. Rin shouts and the
    // other is blown flat. Luka holds up her tuna, lets the other want it, and puts it
    // away. Zundamon shows off, is given a start, and panics. They move no one from her
    // seat, so they play the same in a pair, in a row of three, lying or standing.
    property Item ownA: null
    property Item ownB: null
    function seated(name) {
        return stage === name ? mascot : duo && buddyWho === name ? buddy : heraldRin && name === "rin" ? herald : null
    }
    readonly property var ownSkits: ({ teto: ownTeto, miku: ownMiku, rin: ownRin, luka: ownLuka, zunda: ownZunda })
    function ownRunning() { for (const k in ownSkits) if (ownSkits[k].running) return true; for (const k of toySkits) if (k.running) return true; return false }
    function stopOwn() { for (const k in ownSkits) ownSkits[k].stop(); for (const k of toySkits) k.stop() }
    // ...and Miku's with Claude's little one, while she has him (that is, while Claude
    // works). By herself, every so often, she squeezes him, lifts him up, throws him up
    // and catches him, or pats him. With a neighbour (`ownB`): she holds him out to show
    // and the neighbour is charmed; the neighbour reaches for him and Miku turns him away;
    // the neighbour gives him a poke, up he goes, and Miku catches him and holds him tight.
    // Miku plays no feeling of her own in these: one would take him out of her arms.
    readonly property var toySkits: [toyShow, toyGrab, toyPoke]
    readonly property var toyAlone: ["squeeze", "lift", "toss", "pat"]
    property int lastToy: -1
    function toyDir() { // which side of Miku the neighbour is on
        if (!ownA || !ownB) return 1
        return vertical ? inward : (ownB.x >= ownA.x ? 1 : -1)
    }
    function playToy() {
        const mk = seated("miku")
        if (!mk || !claudeBusy || mk.emote !== "" || arriving.includes("miku")) return false
        const others = head.filter(c => c !== "miku" && seated(c) !== null && !arriving.includes(c))
        if (others.length === 0) return false
        ownA = mk; ownB = seated(others[Math.floor(Math.random() * others.length)])
        let i = Math.floor(Math.random() * toySkits.length)
        if (i === lastToy) i = (i + 1) % toySkits.length
        lastToy = i
        duoLook = true; duoLookOff.restart()
        toySkits[i].restart()
        return true
    }
    Timer { // by herself
        interval: 12000
        repeat: true
        running: root.claudeBusy && !Theme.reduced && !root.tucked && root.seated("miku") !== null
        onTriggered: {
            interval = 18000 + Math.random() * 16000
            const mk = root.seated("miku")
            if (!mk || mk.emote !== "" || root.ownRunning() || (mk.st.palK || "") !== "") return
            const k = root.toyAlone[Math.floor(Math.random() * root.toyAlone.length)]
            mk.palDo(k, k === "toss" ? 900 : k === "lift" ? 2200 : 1500, 1)
            if (k === "toss") mk.st.sqv += 5
        }
    }
    SequentialAnimation {
        id: toyShow
        ScriptAction { script: { root.ownA.palDo("show", 2300, root.toyDir()) } }
        PauseAnimation { duration: 450 }
        ScriptAction { script: { root.ownB.play("love", 1600); root.ownB.jump(0.4, true) } }
        PauseAnimation { duration: 1900 }
        ScriptAction { script: { root.ownA.palDo("squeeze", 1200, 1) } }
    }
    SequentialAnimation {
        id: toyGrab
        ScriptAction { script: { root.ownB.play("hype", 900); root.ownB.jump(0.5, true) } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: { root.ownA.palDo("guard", 2000, root.toyDir()); root.ownA.st.sqv += 5 } }
        PauseAnimation { duration: 700 }
        ScriptAction { script: { root.ownB.play("upset", 1500) } }
        PauseAnimation { duration: 1400 }
        ScriptAction { script: { root.ownA.palDo("pat", 1400, 1) } }
    }
    SequentialAnimation {
        id: toyPoke
        ScriptAction { script: { root.ownB.jump(0.35, true); root.ownB.st.sqv += 4 } }
        PauseAnimation { duration: 220 }
        ScriptAction { script: { root.ownA.palDo("toss", 950, 1); root.ownA.st.shake = 0.5 } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: { root.ownB.play("laugh", 1300) } }
        PauseAnimation { duration: 700 }
        ScriptAction { script: { root.ownA.palDo("squeeze", 1500, 1) } }
    }
    property string lastOwn: ""
    function playOwn() {
        const there = head.filter(c => seated(c) !== null && !arriving.includes(c))
        if (there.length < 2) return false
        let who = there[Math.floor(Math.random() * there.length)]
        if (who === lastOwn) who = there[(there.indexOf(who) + 1) % there.length]
        const others = there.filter(c => c !== who)
        lastOwn = who
        ownA = seated(who); ownB = seated(others[Math.floor(Math.random() * others.length)])
        duoLook = true; duoLookOff.restart()
        ownSkits[who].restart()
        return true
    }
    SequentialAnimation {
        id: ownTeto
        ScriptAction { script: { root.ownB.play("laugh", 1300); root.ownB.jump(0.3, false) } }
        PauseAnimation { duration: 600 }
        ScriptAction { script: { root.ownA.play("tsun", 700) } }
        PauseAnimation { duration: 650 }
        ScriptAction { script: { root.ownA.play("threat", 1900); root.ownA.jump(0.5, true) } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: { root.ownB.play("scared", 1700); root.ownB.st.shake = 1; root.ownB.st.sqv += 7 } }
        PauseAnimation { duration: 700 }
        ScriptAction { script: { root.ownB.st.shake = 0.8 } }
        PauseAnimation { duration: 950 }
        ScriptAction { script: { root.ownA.play("smug", 1300); root.ownB.play("upset", 1200) } }
    }
    SequentialAnimation {
        id: ownMiku
        ScriptAction { script: { root.ownA.play("baton", 2600); root.ownA.jump(0.3, false) } }
        PauseAnimation { duration: 500 }
        ScriptAction { script: { root.ownB.play("sing", 2000); root.ownB.st.swing = 1 } }
        PauseAnimation { duration: 900 }
        ScriptAction { script: { root.ownB.jump(0.3, false); root.ownB.st.swing = 1 } }
        PauseAnimation { duration: 1200 }
        ScriptAction { script: { root.ownA.play("laugh", 1000); root.ownB.play("hype", 1000); root.ownB.jump(0.5, false) } }
    }
    SequentialAnimation {
        id: ownRin
        ScriptAction { script: { root.ownA.st.sqv += 6 } } // (a breath in)
        PauseAnimation { duration: 380 }
        ScriptAction { script: { root.ownA.play("shout", 1300); root.ownA.jump(0.4, true) } }
        PauseAnimation { duration: 140 }
        ScriptAction { script: { root.ownB.play("scared", 1300); root.ownB.st.shake = 1; root.ownB.st.sqv += 9 } }
        PauseAnimation { duration: 1250 }
        ScriptAction { script: { root.ownA.play("laugh", 1200); root.ownB.play(root.ownB.who.slap, 1500) } }
    }
    SequentialAnimation {
        id: ownLuka
        ScriptAction { script: { root.ownA.play("treat", 2300) } }
        PauseAnimation { duration: 450 }
        ScriptAction { script: { root.ownB.play("love", 1700); root.ownB.jump(0.5, true) } }
        PauseAnimation { duration: 700 }
        ScriptAction { script: { root.ownB.jump(0.6, true) } }
        PauseAnimation { duration: 1100 }
        ScriptAction { script: { root.ownA.play("cool", 1400); root.ownB.play("upset", 1500) } }
    }
    SequentialAnimation {
        id: ownZunda
        ScriptAction { script: { root.ownA.play("proud", 1300); root.ownA.roll(1, 800) } }
        PauseAnimation { duration: 900 }
        ScriptAction { script: { root.ownB.play(root.ownB.who.slap, 700) } }
        PauseAnimation { duration: 650 }
        ScriptAction { script: { root.ownB.play("hype", 700); root.ownB.jump(0.8, true) } }
        PauseAnimation { duration: 160 }
        ScriptAction { script: { root.ownA.play("scared", 1500); root.ownA.st.shake = 1; root.ownA.jump(0.6, true) } }
        PauseAnimation { duration: 1300 }
        ScriptAction { script: { root.ownB.play("laugh", 1200); root.ownA.play("flustered", 1200) } }
    }

    function playSkit() {
        if (skTrade.running || sweeping || skGroove.running || skDisco.running || ownRunning()) return // (nothing interrupts the sweeping, or a dance)
        for (const k of skits) if (k.running) return
        for (const k of noteSkits) if (k.running) return
        if (Math.random() < 0.25 && playToy()) return
        if (Math.random() < 0.35 && playOwn()) return
        let i = Math.floor(Math.random() * skits.length)
        if (i === lastSkit) i = (i + 1) % skits.length
        lastSkit = i
        duoLook = true; duoLookOff.restart()
        skits[i].restart()
    }
    onDuoChanged: { stopNoteSkits(); if (duo) return; skTrade.stop(); for (const k of skits) k.stop(); mainDx = 0; buddyDx = 0; buddyPop = 1; tossA = 0 }
    // The two trading places while they sit together (Miku's visit ends and the other
    // takes the lead, or the other way round). Neither vanishes and reappears: each is
    // drawn where she was a moment ago, in the other's seat, and they jump over to their
    // own. (That is why the two change character at once while they are a pair: `instant`.)
    readonly property string leftWho: mikuLeft ? buddyWho : stage
    property string leftWas: ""
    onLeftWhoChanged: {
        if (duo && leftWas !== "" && leftWho !== leftWas && !Theme.reduced) skTrade.restart()
        leftWas = leftWho
    }
    SequentialAnimation {
        id: skTrade
        ScriptAction { script: {
            for (const k of root.skits) k.stop()
            root.stopNoteSkits()
            root.buddyPop = 1; root.tossA = 0
            root.mainDx = 27; root.buddyDx = -27
            root.duoLook = true; duoLookOff.restart()
            mascot.jump(1, true); buddy.jump(0.8, true)
        } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 480; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "buddyDx"; to: 0; duration: 480; easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: { mascot.st.sqv += 5; buddy.st.sqv += 5 } }
    }
    Timer {
        id: duoTimer
        interval: 8000
        repeat: true
        running: root.duo && !Theme.reduced && !root.tucked
        onTriggered: { interval = 14000 + Math.random() * 12000; root.playSkit() }
    }
    // one hops, the other follows
    SequentialAnimation {
        id: skWave
        ScriptAction { script: { buddy.jump(0.4, false) } }
        PauseAnimation { duration: 170 }
        ScriptAction { script: { mascot.jump(0.4, false) } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: { buddy.jump(0.3, false) } }
    }
    // nodding in turn, like two at one keyboard
    SequentialAnimation {
        id: skNod
        ScriptAction { script: { buddy.st.sqv += 5 } }
        PauseAnimation { duration: 170 }
        ScriptAction { script: { mascot.st.sqv += 5 } }
        PauseAnimation { duration: 170 }
        ScriptAction { script: { buddy.st.sqv += 5 } }
        PauseAnimation { duration: 170 }
        ScriptAction { script: { mascot.st.sqv += 5 } }
    }
    // one startles, the other laughs
    SequentialAnimation {
        id: skStartle
        ScriptAction { script: { buddy.play("surprised", 900); buddy.jump(0.3, false) } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: { mascot.play("laugh", 1000) } }
    }
    // humming together, swaying
    SequentialAnimation {
        id: skHum
        ScriptAction { script: { buddy.play("hum", 1700); mascot.play("hum", 1700); buddy.st.swing = 1; mascot.st.swing = 1 } }
    }
    // the partner's own habit, and a glance at it
    SequentialAnimation {
        id: skQuirk
        ScriptAction { script: { buddy.play(buddy.who.quirk, 1500) } }
        PauseAnimation { duration: 500 }
        ScriptAction { script: { mascot.play("fond", 900) } }
    }
    // on a roll: one, then the other
    SequentialAnimation {
        id: skRoll
        ScriptAction { script: { mascot.play("hype", 900); mascot.roll(1, 700) } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: { buddy.play("laugh", 1000); buddy.roll(1, 700) } }
    }
    // the partner bumps into her
    SequentialAnimation {
        id: skBump
        NumberAnimation { target: root; property: "buddyDx"; to: -7; duration: 120; easing.type: Easing.InQuad }
        ScriptAction { script: { mascot.st.sqv += 7; mascot.st.shake = 0.6; mascot.play("surprised", 700) } }
        NumberAnimation { target: root; property: "buddyDx"; to: 0; duration: 280; easing.type: Easing.OutBack }
        PauseAnimation { duration: 300 }
        ScriptAction { script: { buddy.play("laugh", 900) } }
    }
    // they jump and change seats, and after a moment jump back
    SequentialAnimation {
        id: skSwap
        ScriptAction { script: { mascot.jump(0.9, true); buddy.jump(0.9, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 25; duration: 420; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "buddyDx"; to: -27; duration: 420; easing.type: Easing.InOutCubic } }
        ScriptAction { script: { mascot.play("laugh", 900); buddy.play("hype", 900) } }
        PauseAnimation { duration: 1500 }
        ScriptAction { script: { mascot.jump(0.9, true); buddy.jump(0.9, true) } }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 420; easing.type: Easing.InOutCubic } NumberAnimation { target: root; property: "buddyDx"; to: 0; duration: 420; easing.type: Easing.InOutCubic } }
    }
    // a high five, with a star where the hands meet
    SequentialAnimation {
        id: skFive
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 4; duration: 140; easing.type: Easing.OutQuad } NumberAnimation { target: root; property: "buddyDx"; to: -4; duration: 140; easing.type: Easing.OutQuad } }
        ScriptAction { script: { root.tossBySeat = false; root.tossU = 0.5; root.tossA = 1; mascot.st.sqv += 6; buddy.st.sqv += 6; mascot.play("laugh", 800); buddy.play("laugh", 800) } }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 240; easing.type: Easing.OutBack } NumberAnimation { target: root; property: "buddyDx"; to: 0; duration: 240; easing.type: Easing.OutBack } NumberAnimation { target: root; property: "tossA"; to: 0; duration: 420; easing.type: Easing.OutCubic } }
    }
    // one adores, the other cannot take it
    SequentialAnimation {
        id: skLove
        ScriptAction { script: { buddy.play("love", 1600) } }
        PauseAnimation { duration: 450 }
        ScriptAction { script: { mascot.play("flustered", 1300) } }
    }
    // the partner ducks out of sight and pops back up
    SequentialAnimation {
        id: skPeek
        NumberAnimation { target: root; property: "buddyPop"; to: 0; duration: 160; easing.type: Easing.InQuad }
        PauseAnimation { duration: 350 }
        ScriptAction { script: { mascot.play("surprised", 800) } }
        PauseAnimation { duration: 350 }
        NumberAnimation { target: root; property: "buddyPop"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
        ScriptAction { script: { buddy.play("laugh", 900); mascot.jump(0.35, false) } }
    }
    // a squabble over nothing, then they laugh
    SequentialAnimation {
        id: skSquabble
        ScriptAction { script: { mascot.st.shake = 1; buddy.st.shake = 1; mascot.play("annoyed", 900); buddy.play("angry", 900) } }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 2; duration: 90; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: -2; duration: 90; easing.type: Easing.InOutSine } }
        ParallelAnimation { NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 90; easing.type: Easing.InOutSine } NumberAnimation { target: root; property: "buddyDx"; to: 0; duration: 90; easing.type: Easing.InOutSine } }
        PauseAnimation { duration: 850 }
        ScriptAction { script: { mascot.play("laugh", 900); buddy.play("laugh", 900) } }
    }
    // a star tossed over and tossed back
    SequentialAnimation {
        id: skToss
        ScriptAction { script: { root.tossBySeat = false; root.tossU = 0; root.tossA = 1; mascot.st.sqv += 4 } }
        NumberAnimation { target: root; property: "tossU"; to: 1; duration: 420; easing.type: Easing.InOutSine }
        ScriptAction { script: { buddy.jump(0.45, false); buddy.play("hype", 700) } }
        PauseAnimation { duration: 350 }
        ScriptAction { script: { buddy.st.sqv += 4 } }
        NumberAnimation { target: root; property: "tossU"; to: 0; duration: 420; easing.type: Easing.InOutSine }
        ScriptAction { script: { mascot.jump(0.45, false); mascot.play("laugh", 700) } }
        NumberAnimation { target: root; property: "tossA"; to: 0; duration: 160; easing.type: Easing.OutCubic }
    }
    // the partner nods off and gets a nudge
    SequentialAnimation {
        id: skDoze
        ScriptAction { script: { buddy.play("cool", 1900) } }
        PauseAnimation { duration: 1000 }
        NumberAnimation { target: root; property: "mainDx"; to: 6; duration: 120; easing.type: Easing.InQuad }
        ScriptAction { script: { buddy.play("surprised", 900); buddy.jump(0.45, true); buddy.st.shake = 0.5 } }
        NumberAnimation { target: root; property: "mainDx"; to: 0; duration: 280; easing.type: Easing.OutBack }
        PauseAnimation { duration: 250 }
        ScriptAction { script: { mascot.play("smug", 1000) } }
    }
    // a little dance: hop, hop, hop
    SequentialAnimation {
        id: skDance
        ScriptAction { script: { mascot.st.swing = 1; buddy.st.swing = 1; mascot.play("hum", 1500); buddy.play("hum", 1500) } }
        ScriptAction { script: { mascot.jump(0.3, false) } }
        PauseAnimation { duration: 200 }
        ScriptAction { script: { buddy.jump(0.3, false) } }
        PauseAnimation { duration: 200 }
        ScriptAction { script: { mascot.jump(0.3, false) } }
        PauseAnimation { duration: 200 }
        ScriptAction { script: { buddy.jump(0.3, false) } }
        PauseAnimation { duration: 200 }
        ScriptAction { script: { mascot.jump(0.5, false); buddy.jump(0.5, false) } }
    }
    // the partner cheers her on
    SequentialAnimation {
        id: skCheer
        ScriptAction { script: { buddy.play("hype", 1100); buddy.jump(0.5, false) } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: { buddy.jump(0.4, false) } }
        PauseAnimation { duration: 200 }
        ScriptAction { script: { mascot.play("proud", 1200) } }
    }
    readonly property int castW: 50
    // Zundamon with Spotify playing: the bar names the track and she hums along
    readonly property bool tune: ownAct && Media.active && Media.playing
    readonly property bool awake: tune || (tetoAct && Sys.strain) || (lukaAct && Net.trouble)
    // ...and whenever the bar has nothing more pressing to say it is her mini player:
    // the track's name and the three buttons, without opening the card
    // (only while a tune is actually playing; and a finished task keeps the bar for its
    // "Done" for two and a half seconds first, counted from when the card has closed: `doneHold`)
    // While the memory is being cleaned Teto takes a broom to it, and is pleased with
    // herself when it is done.
    readonly property bool sweeping: Sys.cleaning
    onSweepingChanged: {
        if (stage !== "teto") return
        if (sweeping) mascot.play("sweep", 4300)
        else { mascot.play("smug", 1600); mascot.jump(0.6, true) }
    }
    // Teto on stage: the bar is her gauges, and she looks the way the computer feels
    readonly property bool tetoAct: opened && guest === "" && rest === "teto" && Prefs.tetoSystem && Sys.available
    readonly property bool miniGauges: tetoAct && Hub.pendingCount === 0 && !(doneHold && Hub.chip === "done")
    // Luka on stage: the bar is her readings of the connection
    readonly property bool lukaAct: opened && guest === "" && rest === "luka" && Prefs.lukaNet && Net.available
    readonly property bool miniNet: lukaAct && Hub.pendingCount === 0 && !(doneHold && Hub.chip === "done")
    // (she starts when the line goes, and is quietly pleased when it is back)
    // (...and is pleased with a download that has come in whole)
    readonly property bool fetchDone: Net.available && Net.justFetched && !Speed.busy
    onFetchDoneChanged: if (fetchDone && stage === "luka") { mascot.play("proud", 1500); mascot.jump(0.5, true) }
    // The speed test: the faster the line turns out to be, the happier she is while it
    // runs, and a slow one upsets her. A crawl has her drooping; a slow line gets a flat
    // look; a decent one a quiet smile; a fast one has her laughing and hopping; a very
    // fast one sends her up with hearts and sparks. When it is over she answers the
    // result the same way, once more and bigger.
    //   0 crawl (under 5 Mbit/s)  1 slow (under 25)  2 decent (under 75)  3 fast (under 200)  4 very fast
    function speedMood(v) { return v < 5 ? 0 : v < 25 ? 1 : v < 75 ? 2 : v < 200 ? 3 : 4 }
    Timer {
        interval: 650
        repeat: true
        running: (Speed.phase === "down" || Speed.phase === "up") && root.stage === "luka" && !Theme.reduced
        onTriggered: {
            const k = root.speedMood(Speed.phase === "down" ? Speed.down : Speed.up)
            mascot.play(["upset", "unimpressed", "fond", "laugh", "hype"][k], 900)
            if (k === 3) mascot.jump(0.35, false)
            if (k === 4) { mascot.jump(0.7, false); if (!mascot.celebrating) mascot.celebrate(0.7) }
        }
    }
    Connections {
        target: Speed
        function onFinished() {
            if (root.stage !== "luka") return
            const k = root.speedMood(Speed.down)
            if (k === 0) { mascot.play("upset", 3600); mascot.st.shake = 1; return }
            if (k === 1) { mascot.play("upset", 2400); return }
            if (k === 2) { mascot.play("proud", 1800); mascot.jump(0.5, true); return }
            mascot.play(k === 4 ? "love" : "laugh", 2400)
            mascot.celebrate(k === 4 ? 1.2 : 0.8)
            if (k === 4) mascot.roll(1, 900)
        }
    }
    readonly property bool lineDown: Net.available && !Net.online
    onLineDownChanged: if (stage === "luka") { if (lineDown) { mascot.play("surprised", 1100); mascot.jump(0.5, true) } else mascot.play("fond", 1600) }
    readonly property bool barOwn: miniPlayer || miniGauges || miniNet // the bar belongs to the one on stage, not to Claude's label
    readonly property bool miniPlayer: ownAct && Media.active && Media.playing && Hub.pendingCount === 0 && !(doneHold && Hub.chip === "done")
    property bool doneHold: false
    // "Done" is news, and news that has been looked at is over: once the card has been opened
    // by hand the bar's "Done" does not come back for that task.
    property bool doneSeen: false
    readonly property bool doneLooked: expanded && !autoOpened && Hub.chip === "done"
    onDoneLookedChanged: if (doneLooked) doneSeen = true
    readonly property string chipNow: Hub.chip
    onChipNowChanged: doneSeen = false
    Timer { id: doneHoldTimer; interval: 2500
        onTriggered: { root.doneHold = false; if (Hub.pendingCount === 0) { guestTimer.stop(); root.guest = "" } } } // "Done" is over: Miku goes, and the one who rests is back
    readonly property real pillContentW: labelX + pillRow.implicitWidth + 16
    readonly property real pillW: Math.max(pillMin, Math.min(pillMax, pillContentW))
    readonly property real closedW: floating ? 120 : (vertical ? pillT : pillW)
    readonly property real closedH: floating ? 120 : (vertical ? sideH + Math.round(duoW + heraldW) : pillT)
    readonly property real cardW: expanded ? 660 : closedW
    readonly property real cardH: expanded ? viewHeight : closedH
    // the radius grows from the bar's 14 to the card's 26 as it opens, never past half the short side
    readonly property real radius: Math.min(14 + 12 * openU, Math.min(animW, animH) / 2)
    // The card resizes first when it grows (content follows 120 ms behind); when it
    // shrinks the content fades first and the card follows 80 ms later. It opens on
    // Theme.springOpen and closes on Theme.easeClose; the mascot glides on the same curves.
    property real animW: closedW
    property real animH: closedH
    property bool shrinking: false
    property bool snapSize: false  // a dock changes the pill's shape at once; the card morphs instead
    readonly property int enterDelay: shrinking ? 200 : 120
    onCardHChanged: { shrinking = cardH < animH - 0.5; animH = cardH }
    onCardWChanged: animW = cardW
    Behavior on animW { enabled: !root.snapSize; SequentialAnimation { PauseAnimation { duration: root.shrinking ? 80 : 0 } NumberAnimation { duration: root.shrinking ? Theme.tClose : Theme.tOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: root.shrinking ? Theme.easeClose : Theme.springOpen } } }
    Behavior on animH { enabled: !root.snapSize; SequentialAnimation { PauseAnimation { duration: root.shrinking ? 80 : 0 } NumberAnimation { duration: root.shrinking ? Theme.tClose : Theme.tOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: root.shrinking ? Theme.easeClose : Theme.springOpen } } }

    // how far the card has opened, 0 (pill) .. 1 (card)
    readonly property real openU: Math.max(0, Math.min(1, (animW - closedW) / Math.max(1, 660 - closedW)))
    function mix(a, b, u) { return a + (b - a) * u }
    // The card's place inside the surface. Top and bottom: centred on the pill, settling to
    // the surface's centre as it opens; bottom grows upward. Left and right: flush with the
    // edge, centred on the pill along it, kept inside the surface as it opens.
    readonly property real cardX: floating ? (width - animW) / 2
        : edge === "left" ? -tuckA
        : edge === "right" ? width - animW + tuckA
        : mix(Math.max(0, Shell.pillAlong - animW / 2 - grownW / 2), (width - animW) / 2, openU)
    // (When the bar grows for a partner or for Rin it grows to the left: its right end
    // stays where it is. Only at the surface's left end does it grow rightward instead.)
    readonly property real grownW: duoW + heraldW
    readonly property real cardY: floating ? 8
        : edge === "top" ? -tuckA
        : edge === "bottom" ? height - animH + tuckA
        : mix(Shell.pillAlong - animH / 2, Math.max(8, Math.min(height - 8 - animH, Shell.pillAlong - animH / 2)), openU)
    // the dark surface runs `radius` past the flush side, so only the inner corners are round
    readonly property real shapeX: dockSide === "left" ? -radius : 0
    readonly property real shapeY: dockSide === "top" ? -radius : 0
    readonly property real shapeW: animW + (dockSide === "left" || dockSide === "right" ? radius : 0)
    readonly property real shapeH: animH + (dockSide === "top" || dockSide === "bottom" ? radius : 0)

    // ---- behaviour -------------------------------------------------------------
    readonly property bool typing: chatView.inputFocus || settingsView.inputFocus || sessionView.inputFocus
    readonly property bool holdOpen: Hub.pendingCount > 0 || dropActive || peek.running || typing || dragArea.dragging
    readonly property bool wantsKeys: expanded && (view === "chat" || view === "settings" || view === "permission" || view === "session")
    onWantsKeysChanged: Shell.setKeyboard(wantsKeys)
    onHoldOpenChanged: if (!holdOpen && !hover.hovered) closeIn(600)

    // ---- tucked into the edge ----------------------------------------------------
    // A minute with nothing to show (and no tune playing) and the bar slides out of sight, leaving a 240 x 6
    // strip on the edge that brings it back when the pointer touches it.
    property bool tucked: false
    // How finely the animations step (see Ticker.h): the open card, and anything that is
    // being moved across the screen, at 60 a second; the bar's small life at 40.
    Binding {
        target: Ticker; property: "rate"
        value: root.expanded || root.mfree || root.assembling || root.greeting || root.moving || dockAnim.running ? 60 : 40
    }

    // ---- moving the bar by hand: the Move key in the card's header ----
    // The card closes and the bar waits to be picked up (a lemon edge pulses round it, and
    // it bobs off its edge). Picked up, it comes away whole and goes wherever the pointer
    // goes, anywhere on the screen, a little behind it like jelly; those in it gasp and
    // lean into the wind, and stars fall off its tail. A lemon shadow on the nearest edge
    // shows where it would land, and the bar takes that edge's shape in the hand (lying
    // for the top and the bottom, standing for the sides). Let go and it flies to the
    // shadow, bumps into the edge, rings a ripple and throws a handful of stars. A click
    // keeps the place; so do fifteen seconds of nothing.
    property bool moving: false
    readonly property bool carried: moving && moveArea.pressed
    property real bob: 0
    SequentialAnimation on bob {
        running: root.moving && !root.carried && !Theme.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutSine }
    }
    onMovingChanged: if (!moving) bob = 0
    // how far the bar stands off its edge while it waits, and which way that is
    readonly property real lift: moving && !barFree ? 3 * bob : 0
    readonly property real liftX: edge === "left" ? lift : edge === "right" ? -lift : 0
    readonly property real liftY: edge === "top" ? lift : edge === "bottom" ? -lift : 0
    // In the hand the bar is placed by where it is on the output (`barSX`, `barSY`: its
    // top left), not by its dock: the surface covers the whole output meanwhile, as it
    // does while Kisel herself is carried. `barAir` is the time it is held; `barFree`
    // lasts until it has landed and the surface is small again.
    property bool barFree: false
    property bool barAir: false
    property real barSX: 0
    property real barSY: 0
    Behavior on barSX { enabled: root.barAir && !Theme.reduced; SpringAnimation { spring: 5; damping: 0.32; mass: 0.7 } }
    Behavior on barSY { enabled: root.barAir && !Theme.reduced; SpringAnimation { spring: 5; damping: 0.32; mass: 0.7 } }
    // where it would land: the dock it has now, on the output
    readonly property real landX: Shell.originX + cardX
    readonly property real landY: Shell.originY + cardY
    function pickUp() {
        landAnim.stop()
        barSX = isoX + card.x; barSY = isoY + card.y
        barFree = true
        snapSize = true
        Shell.beginGrab()
        barAir = true
    }
    // (cx, cy: where the bar's middle should be, on the output)
    function carryTo(cx, cy) {
        const d = { top: cy, bottom: screenH - cy, left: cx, right: screenW - cx }
        let e = Shell.edge
        for (const k of ["top", "bottom", "left", "right"]) if (d[k] < d[e] - 40) e = k
        const hop = e !== Shell.edge
        Shell.setDock(e, e === "left" || e === "right" ? cy : cx)
        if (hop) { Sfx.play("hover"); if (!Theme.reduced) { cardMorph.restart(); mascot.jump(0.5, true) } }
        const tx = Math.max(0, Math.min(screenW - closedW, cx - closedW / 2))
        const ty = Math.max(0, Math.min(screenH - closedH, cy - closedH / 2))
        blown(tx - barSX, ty - barSY)
        barSX = tx; barSY = ty
        updateHit()
    }
    function letGo() {
        if (!barFree) { endMove(); return }
        barAir = false
        swayRest.stop(); sway = 0
        landAnim.restart()
    }
    ParallelAnimation {
        id: landAnim
        NumberAnimation { target: root; property: "barSX"; to: root.landX; duration: Theme.reduced ? 0 : 300; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        NumberAnimation { target: root; property: "barSY"; to: root.landY; duration: Theme.reduced ? 0 : 300; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        onFinished: { root.putDown(); Shell.endGrab(); root.barLanded() }
    }
    function barLanded() {
        if (!barFree || barAir || landAnim.running || Shell.viewWide) return
        barFree = false
        snapSize = false
        endMove()
    }
    // the lean of those in it, in degrees: into the wind while it is carried
    property real sway: 0
    Behavior on sway { SpringAnimation { spring: 4; damping: 0.22 } }
    Timer { id: swayRest; interval: 70; onTriggered: { root.sway = 0; root.dentX = 0; root.dentY = 0 } }
    function blown(vx, vy) { // (how far it is about to go)
        if (Theme.reduced) return
        sway = Math.max(-20, Math.min(20, (Math.abs(vx) > Math.abs(vy) ? vx : vy) * 0.9))
        swayRest.restart()
        const v = Math.hypot(vx, vy)
        trailRun += v
        if (trailRun < 26 || v < 0.5) return
        trailRun = 0
        // a star off the tail
        const ux = vx / v, uy = vy / v
        puff(card.x + card.width / 2 - ux * card.width / 2 + (Math.random() - 0.5) * 14 * Math.abs(uy),
             card.y + card.height / 2 - uy * card.height / 2 + (Math.random() - 0.5) * 14 * Math.abs(ux), -ux, -uy)
    }
    property real trailRun: 0
    property int trailI: 0
    function puff(x, y, dx, dy) { const t = trail.itemAt(trailI++ % trail.count); if (t) t.shoot(x, y, dx, dy) }
    function putDown() {
        mascot.land()
        if (Theme.reduced) return
        // (into the edge and back: the dent's own spring does the wobble)
        dentX = edge === "left" ? -5 : edge === "right" ? 5 : 0
        dentY = edge === "top" ? -5 : edge === "bottom" ? 5 : 0
        swayRest.restart()
        landRipple.go(card.x + card.width / 2, card.y + card.height / 2)
        for (let i = 0; i < 8; ++i) {
            const a = Math.PI * 2 * i / 8 + Math.random() * 0.5
            puff(card.x + card.width / 2 + Math.cos(a) * card.width * 0.3, card.y + card.height / 2 + Math.sin(a) * card.height * 0.3, Math.cos(a), Math.sin(a))
        }
        mascot.play("proud", 1000)
        if (duo) buddy.jump(0.5, true)
        if (heraldRin) herald.jump(0.5, true)
    }
    function startMove() {
        if (floating) return
        collapseNow()
        tucked = false
        moving = true
    }
    function endMove() {
        if (!moving) return
        moving = false
        if (barFree) { landAnim.stop(); barAir = false; barFree = false; snapSize = false; Shell.endGrab() } // (never left in the air)
        Prefs.setDock(Displays.current, Shell.edge, Shell.along / Shell.edgeLength(Shell.edge))
        updateHit()
    }
    Timer { interval: 15000; running: root.moving && !moveArea.pressed; onTriggered: root.endMove() }

    readonly property bool canTuck: !floating && !expanded && !mfree && !assembling && !dragArea.pressed && !moving
        && !hover.hovered && !wake.hovered && Hub.pendingCount === 0 && Hub.chip === ""
        && (Hub.mood === "idle" || Hub.mood === "sleep") && !tune
        && !noteAny // (Rin has something to show)
        && !(lukaAct && (Net.trouble || Net.justBack || Net.downloading || Net.justFetched || Speed.running || Speed.justDone)) // (...or Luka has)
    onCanTuckChanged: if (!canTuck) tucked = false
    onTuckedChanged: updateHit()
    // At rest (a while after starting, after the card has closed, on tucking away) Kisel
    // gives back the memory it is not using (Shell.rest).
    Timer { id: restSoon; interval: 12000; running: true; onTriggered: if (!root.expanded) Shell.rest() }
    Connections {
        target: root
        function onTuckedChanged() { if (root.tucked) restSoon.restart() }
        function onExpandedChanged() { if (!root.expanded) restSoon.restart() }
    }
    Timer { interval: 60000; running: root.canTuck && !root.tucked; onTriggered: { if (root.zundaLive) root.idleTune = true; else root.tucked = true } } // (a tune playing: the player instead)
    // the bar and its shadow clear the edge
    property real tuckA: tucked ? pillT + 14 : 0
    Behavior on tuckA { NumberAnimation { duration: Theme.reduced ? 0 : 340; easing.type: Easing.InOutCubic } }
    readonly property rect wakeRect: edge === "left" ? Qt.rect(0, Shell.pillAlong - 120, 6, 240)
        : edge === "right" ? Qt.rect(width - 6, Shell.pillAlong - 120, 6, 240)
        : edge === "bottom" ? Qt.rect(Shell.pillAlong - 120, height - 6, 240, 6)
        : Qt.rect(Shell.pillAlong - 120, 0, 240, 6)

    function openIsland(v) {
        view = v || "home"
        autoOpened = false
        open()
    }
    function open() {
        closeTimer.stop()
        stopWander()
        if (!expanded) {
            if (floating) mascot.jump(0.35) // the card is pushed out from under its feet
            expanded = true
            Sfx.play("open")
        }
    }
    // closes if nothing holds it open (the timer, the hover rules)
    function collapse() {
        if (!expanded || holdOpen)
            return
        collapseNow()
    }
    // an explicit close: the close icon, a click on the floating mascot, Escape
    function collapseNow() {
        if (!expanded)
            return
        expanded = false
        view = Hub.pendingCount > 0 ? "permission" : "home"
        Sfx.play("close")
    }
    function afterAnswer() {
        if (Hub.pendingCount === 0) {
            view = "home"
            if (!hover.hovered || floating)
                closeIn(600)
        }
    }
    function toggleView(v) { view = view === v ? "home" : v }

    // Prefs.closeDelay after the pointer leaves; 600 ms once an answer or a peek is over
    function closeIn(ms) { closeTimer.interval = ms; closeTimer.restart() }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: {
            // floating: only an island that opened by itself closes by itself
            if (root.floating) { if (root.autoOpened) root.collapse() }
            else if (!hover.hovered) root.collapse()
        }
    }
    Timer { id: peekDelay; interval: 300; onTriggered: { root.open(); peek.restart() } } // peek for 4.5 s, then close unless the pointer is on it
    Timer { id: peek; interval: 4500; onTriggered: if (!hover.hovered || root.floating) root.collapse() }
    Timer { id: dropHappyTimer; interval: 1500; onTriggered: root.dropHappy = false }

    Connections {
        target: Hub
        function onPermissionArrived() {
            root.stepIn()
            Sfx.play("alert")
            root.autoOpened = !root.expanded
            root.view = "permission"
            root.open()
        }
        function onPermissionAnswered(decision) {
            if (decision === "allow" || decision === "always") Sfx.play("click")
            else if (decision === "deny") Sfx.play("deny")
            root.afterAnswer()
        }
        function onPermissionCleared() { root.afterAnswer() }
        function onTaskFinished() {
            root.stepIn()
            root.doneHold = true // (the five seconds start when the card, which opens for a look, closes again)
            doneHoldTimer.stop()
            Sfx.play("done")
            const inPill = !root.expanded && !root.floating
            if (inPill) // the burst starts from the pill's "Done" chip...
                burst.fire(card.x + (root.vertical ? root.pillT / 2 : root.pillW / 2), card.y + (root.vertical ? 34 : root.pillT / 2), root.mini)
            else
                burst.fire(mascot.x + mascot.width / 2, mascot.y + mascot.height * 0.55, mascot.width)
            if (!root.expanded) {
                // ...and the peek opens at the burst's peak, so the pieces seem to push the card open
                root.view = "session"
                root.autoOpened = true
                peekDelay.restart()
            }
        }
        function onToolFailed() { Sfx.play("deny") }
        function onActivity() { root.stopWander() }
    }

    // ---- moved to another monitor: arrive with a hop ---------------------------
    Connections {
        target: Displays
        function onMoved() { arriveTimer.restart() }
    }
    Timer {
        id: arriveTimer
        interval: 350
        onTriggered: { mascot.jump(1.0); Sfx.play("done"); root.updateHit() }
    }

    // ---- first launch: the assembly (motion.md, "The assembly") ----------------
    // The cover drops in, becomes the island pill and the mint disc becomes its
    // leaf spot; the island then opens while the other shapes fly to their places
    // and become Kisel's body and gloss, the hook card, its button and the tiles.
    // Everything is driven by Assembly's clock; here we only react to its beats.
    readonly property bool assembling: assembly.running
    onAssemblingChanged: updateHit()
    function runIntro() {
        if (assembling) return
        closeTimer.stop()
        expanded = false
        view = "home"
        if (Theme.reduced) {
            // "Reduce motion": no flight, no morph; Home fades in with every element in place
            autoOpened = true
            open()
            peek.interval = 3000
            peek.restart()
            return
        }
        // Where everything lands, from the real layout (Home is 660 x 200, hung at the top centre)
        const cardX = (root.width - 660) / 2
        const ox = cardX + 150, oy = 48 // Home's content origin
        const pw = pillMin // the pill at rest
        assembly.pill = Qt.rect((root.width - pw) / 2, 0, pw, pillT)
        assembly.leaf = Qt.point((root.width - pw) / 2 + miniLead + 27 * mini / 44, miniPad + 5 * mini / 44)
        assembly.slot = Qt.rect(cardX + 14 + (132 - 110) / 2, 48, 110, 110)
        const hr = homeView.hookRect, br = homeView.buttonRect
        assembly.card = Qt.rect(ox + hr.x, oy + hr.y, hr.width, hr.height)
        assembly.button = Qt.rect(ox + br.x, oy + br.y, br.width, br.height)
        const tr = homeView.tileRects
        assembly.tiles = [
            { x: ox + tr[0].x, y: oy + tr[0].y, w: tr[0].width, h: tr[0].height, color: Theme.kisel },
            { x: ox + tr[1].x, y: oy + tr[1].y, w: tr[1].width, h: tr[1].height, color: Theme.amber }
        ]
        mascot.eyesShut = true
        mascot.leafScale = 0
        assembly.play()
    }
    Assembly {
        id: assembly
        onLanded: Sfx.play("open")
        onBorn: { // the island is ready: the mini Kisel appears with one blink; the pill bounces 4 %
            mascot.leafScale = 1
            mascot.eyesShut = false
            mascot.blinkNow()
            pillBounce.restart()
        }
        onUnfold: { // the island opens; the flying shapes become Kisel, the card, the button and the tiles
            root.view = "home"
            root.autoOpened = true
            root.open()
            mascot.leafScale = 0
            mascot.eyesShut = true
        }
        onSettled: { // Kisel opens its eyes with one blink, the leaf grows, and it jumps (power 0.6)
            mascot.eyesShut = false
            mascot.blinkNow()
            leafGrow.restart()
            mascot.jump(0.6)
            Sfx.play("done")
        }
        onPulse: homeView.pulseConnect()
        onCloseIsland: if (!hover.hovered && !root.holdOpen) root.collapseNow()
    }
    SequentialAnimation {
        id: pillBounce
        NumberAnimation { target: card; property: "scale"; to: 1.04; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 200; easing.type: Easing.OutBack }
    }
    NumberAnimation { id: leafGrow; target: mascot; property: "leafScale"; from: 0; to: 1; duration: 240; easing.type: Easing.OutBack }
    // a click skips the sequence: every shape snaps to its final form in 120 ms
    MouseArea { anchors.fill: parent; z: 30; enabled: root.assembling; onClicked: assembly.skip() }

    Component.onCompleted: {
        if (!Prefs.firstRunDone) {
            Prefs.firstRunDone = true
            runIntro()
        }
        if (Prefs.floating && !assembling)
            Shell.restoreFloat(Prefs.floatX, Prefs.floatY)
        updateHit()
        if (!Prefs.floating && !assembling)
            greetSoon.restart()
    }

    // ---- hello: every start she comes up from the bottom of the screen, waves, and flies
    // into the bar. It is the drag's machinery run by a clock instead of a pointer: the
    // surface covers the output, she is "free" at an exact place on it, and the docking
    // arc takes her home. Only her own box takes clicks meanwhile.
    property bool greeting: false
    Timer { id: greetSoon; interval: 500; onTriggered: root.greet() }
    function greet() {
        if (greeting || floating || assembling || expanded || mfree || Theme.reduced) return
        greeting = true
        freeSize = 120
        freeCX = screenW / 2
        freeCY = screenH + 80
        mfree = true
        Shell.beginGrab()
        greetWide.restart()
    }
    // the surface needs a moment to become the size of the output
    Timer { id: greetWide; interval: 60; repeat: true
        onTriggered: if (Shell.viewWide) { stop(); root.freeCX = root.screenW / 2; root.freeCY = root.screenH + 80; greetRise.restart() } }
    NumberAnimation { id: greetRise; target: root; property: "freeCY"; to: root.screenH - 92; duration: 620
        easing.type: Easing.OutBack; easing.overshoot: 1.4
        onFinished: { mascot.wavedAt = Date.now(); mascot.play("hello", 1900); Sfx.play("open"); greetHold.restart() } }
    Timer { id: greetHold; interval: 2000
        onTriggered: { mascot.jump(0.5, true); root.arcDone = false; dockAnim.duration = 760; root.startDockArc() } }

    function updateHit() {
        if (tucked) { Shell.setHitRect(root.x + wakeRect.x, root.y + wakeRect.y, wakeRect.width, wakeRect.height); return }
        // while the assembly plays, the whole top of the surface takes the click that skips it
        if (assembling) { Shell.setHitRect(0, 0, root.width, 300); return }
        // the card and the mascot (which can overhang it), in the surface's coordinates
        let x0 = Math.min(card.x, mascot.x), y0 = Math.min(card.y, mascot.y)
        let x1 = Math.max(card.x + card.width, mascot.x + mascot.width)
        let y1 = Math.max(card.y + card.height, mascot.y + mascot.height)
        if (note) { // (Rin's sign stands out of the bar and takes clicks too)
            y0 = Math.min(y0, sign.y); y1 = Math.max(y1, sign.y + sign.height)
            x0 = Math.min(x0, sign.x); x1 = Math.max(x1, sign.x + sign.width)
        }
        if (signOpen.on) { // (...and out of the open card)
            y0 = Math.min(y0, signOpen.y); y1 = Math.max(y1, signOpen.y + signOpen.height)
            x1 = Math.max(x1, signOpen.x + signOpen.width)
        }
        if (mfree) Shell.setHitRect(root.x + mascot.x, root.y + mascot.y, mascot.width, mascot.height)
        else Shell.setHitRect(root.x + x0, root.y + body.y + y0, x1 - x0, y1 - y0)
    }
    // the island moved inside a full-output surface, or the surface shrank back
    onXChanged: updateHit()
    onYChanged: updateHit()
    Connections { target: Shell; function onViewWideChanged() { root.updateHit(); root.wideChanged2() } }
    Connections { target: Shell; function onPlacementChanged() { root.updateHit() } }

    // ---- floating: where the surface sits ---------------------------------------
    property point homePos: Qt.point(0, 0)
    ParallelAnimation {
        id: fitAnim
        property real toX: 0
        property real toY: 0
        NumberAnimation { target: Shell; property: "floatX"; to: fitAnim.toX; duration: Theme.tBase; easing.type: Easing.OutCubic }
        NumberAnimation { target: Shell; property: "floatY"; to: fitAnim.toY; duration: Theme.tBase; easing.type: Easing.OutCubic }
    }
    onExpandedChanged: {
        if (!expanded) { mikuAsked = false; askedWho = "" }
        // (A card that opens as Miku's stays Miku's until it closes. Without this, with a
        // tune playing, she was only visiting the bar: three seconds later the stage went
        // back to Zundamon and the open card turned into the player under the pointer.)
        else if (stage === "miku") mikuAsked = true
        if (expanded) groundAll()
        if (!expanded && doneHold) doneHoldTimer.restart()
        if (!expanded) mikuPinned = false
        if (Shell.debugOn) Shell.log(Date.now() % 100000 + " expanded=" + expanded + " card=" + Math.round(card.x) + "," + Math.round(card.y) + " " + Math.round(card.width) + "x" + Math.round(card.height) + " mascot=" + Math.round(mascot.x) + "," + Math.round(mascot.y) + " size " + Math.round(mascot.width))
        if (Theme.reduced) slotFade.restart()
        if (!floating) return
        if (expanded) { // slide so the whole card stays on screen
            homePos = Qt.point(Shell.floatX, Shell.floatY)
            const p = Shell.fitOpen()
            fitAnim.toX = p.x; fitAnim.toY = p.y
            fitAnim.restart()
        } else { // and slide back to where the mascot was left
            fitAnim.toX = homePos.x; fitAnim.toY = homePos.y
            fitAnim.restart()
        }
    }
    onFloatingChanged: {
        if (Theme.reduced) slotFade.restart()
        Prefs.floating = floating
        if (floating) { closeTimer.stop(); wanderTimer.restart() } else stopWander()
    }

    // "Reduce motion": the mascot does not glide between slots, it fades between them
    property real slotDip: 1
    NumberAnimation { id: slotFade; target: root; property: "slotDip"; from: 0; to: 1; duration: Theme.tFast }
    onViewChanged: if (Theme.reduced) slotFade.restart()

    // ---- carrying Kisel (motion.md, "Dragging, edges and monitors") ------------------------
    // The mascot is drawn in one of two ways: in its slot on the card (the normal case), or
    // "free": at an exact place on the output (freeCX, freeCY, freeSize), while it is being
    // carried, arcing into a dock, or settling after a drop. Everything here is in output
    // coordinates; `isoX/isoY` turns them into the island's own.
    property bool mfree: false
    property real freeCX: 0
    property real freeCY: 0
    property real freeSize: mini
    property bool growing: false      // freeSize animates (mini -> 120 after the neck snaps)
    Behavior on freeSize { enabled: root.growing && !Theme.reduced; NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
    property bool ghost: false        // the pill has been left behind: it fades out
    property bool settling: false     // let go; waiting for the surface to shrink back
    property string zoneEdge: ""      // the edge a drop would dock to ("" = none)
    property real zoneAlong: 0
    property real zoneDist: 999
    property bool leaning: false      // within 20 px of the wall, still held
    property string crossTarget: ""   // the monitor a drop would move Kisel to
    property bool straddling: false   // the mascot touches another monitor
    property real hopOnLand: 0
    // the bounding box of every monitor, in desktop coordinates
    function desktopRect() {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const s of Displays.screens) { x0 = Math.min(x0, s.x); y0 = Math.min(y0, s.y); x1 = Math.max(x1, s.x + s.w); y1 = Math.max(y1, s.y + s.h) }
        return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
    }
    // (read again whenever the placement changes: the work area can change under us)
    readonly property real screenW: { Shell.originX; return Shell.screenWidth() }
    readonly property real screenH: { Shell.originY; return Shell.screenHeight() }

    // where the mascot's slot is on the final collapsed pill, in output coordinates
    function slotCenterFinal() {
        const e = Shell.edge
        const vert = e === "left" || e === "right"
        const cw = vert ? pillT : pillW, ch = vert ? sideH : pillT
        const cx = e === "left" ? 0 : e === "right" ? width - cw : Shell.pillAlong - cw / 2
        const cy = e === "top" ? 0 : e === "bottom" ? height - ch : Shell.pillAlong - ch / 2
        const sx = vert ? miniPad : miniLead
        const sy = vert ? miniLead : miniPad
        return Qt.point(Shell.originX + cx + sx + mini / 2, Shell.originY + cy + sy + mini / 2)
    }
    function freeBox() { return Qt.point(freeCX - freeSize / 2, freeCY - freeSize / 2) }

    // ---- docking: along an arc (320 ms InOutCubic) into the new pill's slot, shrinking to `mini`
    property real dockT: 0
    property point dockFrom: Qt.point(0, 0)
    property point dockTo: Qt.point(0, 0)
    function startDockArc() {
        dockFrom = Qt.point(freeCX, freeCY)
        dockTo = slotCenterFinal()
        growing = false
        if (Theme.reduced) { dockT = 1; finishDockArc(); return }
        dockAnim.restart()
    }
    NumberAnimation { id: dockAnim; target: root; property: "dockT"; from: 0; to: 1; duration: 320; easing.type: Easing.InOutCubic
        onFinished: root.finishDockArc() }
    onDockTChanged: {
        if (!dockAnim.running) return
        // along a quadratic arc whose control point sits 40 px above the straight line
        const a = dockFrom, b = dockTo, t = dockT
        const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2 - 40, k = 1 - t
        freeCX = k * k * a.x + 2 * k * t * cx + t * t * b.x
        freeCY = k * k * a.y + 2 * k * t * cy + t * t * b.y
        freeSize = 120 + (mini - 120) * t   // shrinks to `mini` with `detail` falling
    }
    function finishDockArc() {
        // landing: a ripple (ring, 24 to 56 px over 280 ms) and the "click" sound
        landRipple.go(slotCenterFinal().x - isoX, slotCenterFinal().y - isoY)
        Sfx.play("click")
        arcDone = true
        if (greeting) { greeting = false; dockAnim.duration = 320; Shell.endGrab() } // home: the surface shrinks back
        tryFinishFree()
    }
    property bool arcDone: true
    // the free state ends once the surface is small again and no arc is running
    function tryFinishFree() {
        if (!mfree || dragArea.picked) return
        if (Shell.viewWide || dockAnim.running) return
        mfree = false; settling = false; ghost = false; growing = false
        snapSize = false
        mascot.land()
        if (hopOnLand > 0) { mascot.jump(hopOnLand); hopOnLand = 0 }
    }
    function wideChanged2() { if (!Shell.viewWide) { tryFinishFree(); barLanded() } }

    // ---- the dock zone and the wall -----------------------------------------------------
    // Measured from Kisel's own side, not from the pointer: holding it by the foot must not
    // make the top edge harder to reach than holding it by the leaf. Docking is allowed on
    // all four edges of the monitor; the pill keeps 120 px from the corners; within 24 px of
    // an edge's centre it snaps to the centre with a tick.
    property bool tickBrighter: false
    Timer { id: tickOff; interval: 120; onTriggered: root.tickBrighter = false }
    function updateZone() {
        const Px = freeCX, Py = freeCY, half = freeSize / 2
        const d = { top: Py - half, bottom: screenH - Py - half, left: Px - half, right: screenW - Px - half }
        let best = "", bd = 96
        for (const e of ["top", "bottom", "left", "right"])
            if (d[e] < bd) { bd = d[e]; best = e }
        if (best === "") { zoneEdge = ""; zoneDist = 999; leaning = false; return }
        const len = Shell.edgeLength(best)
        let along = Shell.clampAlong(best, (best === "top" || best === "bottom") ? Px : Py)
        if (Math.abs(along - len / 2) < 24) {          // the centre magnet
            if (along !== len / 2 || zoneEdge !== best) { tickBrighter = true; tickOff.restart() }
            along = len / 2
        }
        const wasLeaning = leaning
        zoneEdge = best; zoneDist = bd; zoneAlong = along
        leaning = bd < 20
        if (leaning && !wasLeaning) {                   // the magnet ring pulses at the dock spot
            const horiz = best === "top" || best === "bottom"
            magnetRipple.color = Theme.kisel
            magnetRipple.go((horiz ? along : (best === "left" ? 22 : screenW - 22)) - isoX,
                            (horiz ? (best === "top" ? 22 : screenH - 22) : along) - isoY)
        }
    }
    // pressing into a wall: squash perpendicular to it, up to 18 percent at 40 px of over-drag
    function setWall(overX, overY) {
        let wx = 0, wy = 0
        if (overX !== 0) wx = Math.min(0.18, Math.abs(overX) / 40 * 0.18)
        if (overY !== 0) wy = Math.min(0.18, Math.abs(overY) / 40 * 0.18)
        if (leaning && zoneEdge !== "") {                // leaning on the wall: 10 percent
            if (zoneEdge === "left" || zoneEdge === "right") wx = Math.max(wx, 0.10)
            else wy = Math.max(wy, 0.10)
        }
        mascot.wallX = Theme.reduced ? 0 : wx
        mascot.wallY = Theme.reduced ? 0 : wy
        mascot.gazeOn = leaning
        if (leaning) mascot.gaze = Qt.point(zoneEdge === "left" ? 1 : zoneEdge === "right" ? -1 : 0,
                                            zoneEdge === "top" ? 1 : zoneEdge === "bottom" ? -1 : 0)
    }
    function clearWall() { mascot.wallX = 0; mascot.wallY = 0; mascot.gazeOn = false }

    // ---- wandering --------------------------------------------------------------
    property bool walking: false
    property int walkDir: 1
    function stopWander() {
        if (!walking) return
        wanderAnim.stop()
        walking = false
    }
    function startWander() {
        if (!floating || expanded || dragArea.dragging || Hub.mood !== "idle")
            return
        const want = Shell.floatX + (Math.random() * 2 - 1) * 260
        const target = Shell.clampMascot(want, Shell.floatY)
        const dx = target.x - Shell.floatX
        if (Math.abs(dx) < 30)
            return
        walkDir = dx > 0 ? 1 : -1
        wanderAnim.from = Shell.floatX
        wanderAnim.to = target.x
        wanderAnim.duration = Math.abs(dx) * 9 // 9 ms per pixel
        walking = true
        wanderAnim.start()
    }
    NumberAnimation {
        id: wanderAnim
        target: Shell
        property: "floatX"
        easing.type: Easing.InOutSine
        onFinished: { root.walking = false; Prefs.floatX = Shell.floatX }
    }
    Timer {
        id: wanderTimer
        interval: 18000 + Math.random() * 30000
        running: root.floating && !root.expanded && !Theme.reduced
        repeat: true
        onTriggered: { interval = 18000 + Math.random() * 30000; root.startWander() }
    }

    // the pill is dented toward the mascot while it is drawn out
    property real dentX: 0
    property real dentY: 0
    Behavior on dentX { NumberAnimation { duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45 } }
    Behavior on dentY { NumberAnimation { duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45 } }

    // ---- everything below hangs from `body` ------------------------------------
    Item {
        id: body
        width: root.width
        height: root.height
        y: 0

        // an amber tab hangs under the card (above it when docked at the bottom) while a request waits
        AttentionTab {
            anchorX: mascot.x + mascot.width / 2
            cardBottom: root.atBottom ? card.y : card.y + card.height
            dir: root.atBottom ? -1 : 1
            waiting: root.floating || root.vertical || root.ghost ? 0 : Hub.pendingCount
            merged: root.expanded
        }

        // ---- the card ---------------------------------------------------------
        Item {
            id: card
            x: root.barFree ? root.barSX - root.isoX + root.dentX : root.cardX + root.dentX + root.liftX
            y: root.barFree ? root.barSY - root.isoY + root.dentY : root.cardY + root.dentY + root.liftY
            width: root.animW
            height: root.animH
            clip: true // the flush side sits past the screen edge: only the inner corners are round
            // during the assembly the real card appears when the flattened half-round hands over to it;
            // after a drag the new pill morphs in (scale and fade, 240 ms OutBack)
            opacity: (root.assembling && assembly.t < assembly.tBorn) || root.ghost ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: root.ghost ? 150 : 200 } }
            transformOrigin: root.dockSide === "bottom" ? Item.Bottom : root.dockSide === "left" ? Item.Left
                           : root.dockSide === "right" ? Item.Right : Item.Top
            property real morph: 1
            scale: morph
            NumberAnimation { id: cardMorph; target: card; property: "morph"; from: 0.7; to: 1; duration: 240; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack }
            onXChanged: root.updateHit()
            onYChanged: root.updateHit()
            onWidthChanged: root.updateHit()
            onHeightChanged: root.updateHit()

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (Shell.debugOn) Shell.log(Date.now() % 100000 + " hover " + hovered + " at output " + Math.round(root.isoX + card.x + point.position.x) + "," + Math.round(root.isoY + card.y + point.position.y))
                    Hub.poke()
                    if (root.floating || root.mfree) return // floating opens and closes by click
                    // the pointer alone never opens the card: the top of a screen is where
                    // tabs and title bars live. It only keeps an open card open.
                    if (hovered) closeTimer.stop()
                    // "at once" still waits a blink: a hover can drop out for a few
                    // milliseconds while the card changes shape under a still pointer
                    else root.closeIn(Math.max(150, Prefs.closeDelay * 1000))
                }
            }
            // a click anywhere on the bar opens it (on the mascot: see dragArea)
            TapHandler {
                enabled: !root.expanded && !root.floating && !root.mfree && !root.assembling
                onTapped: { Hub.poke(); root.autoOpened = false; root.open() }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: (drag) => {
                    root.dropActive = true
                    root.view = "chat"
                    root.open()
                }
                onExited: root.dropActive = false
                onDropped: (drop) => {
                    root.dropActive = false
                    if (drop.hasUrls && Chat.attach(drop.urls[0])) {
                        root.dropHappy = true
                        dropHappyTimer.restart()
                        Sfx.play("click")
                    }
                }
            }

            // the surface: surface-0 with a 1 px line on every side but the flush one
            Rectangle {
                x: root.shapeX; y: root.shapeY
                width: root.shapeW; height: root.shapeH
                radius: root.radius
                color: Theme.surface0
                opacity: root.floating && !root.expanded ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                border.width: 1
                border.color: Theme.line
            }

            // Luka's speed test: the bar fills with pink like a glass being filled. Along a
            // lying bar the liquid runs in from the left, its front leaning forward along the
            // floor and rippling; a standing bar fills from the bottom with a level surface.
            // The front is on a spring, so it surges and settles when the test moves on in
            // steps, and the ripples are bigger the faster it runs; bubbles rise behind it.
            // When the test is done the bar is full for a moment and the liquid fades.
            // (Teto's bar fills the same way, in her red, while she cleans the memory: that
            // has no measure of its own, so it fills over the time her sweeping takes.)
            Item {
                id: testFill
                // (How far it has got does not depend on whether the bar is in view: open the card
                // and close it again mid-way and the liquid is where the work is, not at the start.)
                // (only while the bar is the bar: gone at once when the card starts to open, and back
                // when it has closed all the way, so the liquid is never stretched over the card)
                readonly property bool shown: !root.expanded && !root.floating && !root.mfree && root.openU < 0.03
                readonly property bool net: root.miniNet && Speed.running
                readonly property bool mem: root.miniGauges && Sys.cleaning
                readonly property bool run: net || mem
                // Done: it tops up, stands full for a moment, and then runs out: the level
                // sinks to the floor (`drain`), still rippling. Stopped half-way, what there
                // is of it runs out the same way. (`tail`: from the end of the work until it is gone.)
                property bool tail: false
                property real drain: 0
                property real held: 0 // where the front stays meanwhile
                onRunChanged: {
                    if (run) { drainAway.stop(); tail = false; drain = 0; return }
                    held = (red ? Sys.justCleaned : Speed.justDone) ? 1 : u
                    // (Someone else took the bar while the work goes on: nothing has run out, it is
                    // simply not this bar's to show. It is back where the work is when she returns.)
                    if (red ? Sys.cleaning : Speed.running) return
                    tail = true
                    drainAway.restart()
                }
                // whose liquid it is has the bar
                readonly property bool hers: red ? root.miniGauges : root.miniNet
                SequentialAnimation {
                    id: drainAway
                    PauseAnimation { duration: 520 }
                    NumberAnimation { target: testFill; property: "drain"; from: 0; to: 1; duration: Theme.reduced ? 0 : 1100; easing.type: Easing.InQuad }
                    ScriptAction { script: testFill.tail = false }
                }
                // (It stays run out until it is out of sight: put back to the start while still
                // fading, the liquid would show again, full, and slide away to the left.)
                onOpacityChanged: if (opacity === 0 && !run && !tail) { held = 0; drain = 0 }
                readonly property bool on: shown && hers && (run || tail)
                property bool red: false // (kept while it fades)
                onMemChanged: if (mem) red = true
                // (the sweep's fill runs with the sweeping itself, whoever has the bar meanwhile)
                readonly property bool sweeping: Sys.cleaning
                onSweepingChanged: { if (sweeping) sweepFill.restart(); else sweepFill.stop() }
                onNetChanged: if (net) red = false
                property real swept: 0
                NumberAnimation { id: sweepFill; target: testFill; property: "swept"; from: 0; to: 0.96; duration: 4200; easing.type: Easing.InOutSine }
                property real u: net ? Speed.progress : mem ? swept : held
                // (the sweep's own run is smooth already: a spring would only trail behind it; and the last bit to full is quick)
                Behavior on u { enabled: !Theme.reduced && !testFill.mem; SpringAnimation { spring: testFill.run ? 1.5 : 7; damping: testFill.run ? 0.26 : 0.7; epsilon: 0.0005 } }
                x: root.shapeX + 1; y: root.shapeY + 1
                width: root.shapeW - 2; height: root.shapeH - 2
                opacity: on ? 1 : 0
                visible: shown && hers && opacity > 0.01 // (`shown` here too: gone at once under an opening card, not after a fade)
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutSine } }
                Timer { interval: 33; repeat: true; running: testFill.visible; onTriggered: pool.requestPaint() }
                Canvas {
                    id: pool
                    anchors.fill: parent
                    property real was: 0   // where the front was a frame ago
                    property real rush: 0  // how fast it is going, smoothed
                    onPaint: {
                        const g = getContext("2d"), w = width, h = height, r = Math.max(0, root.radius - 1)
                        const t = Date.now() / 1000, up = root.vertical, dr = testFill.drain
                        const u = Math.max(0, Math.min(1.02, testFill.u)) * (up ? 1 - dr : 1) // (a standing one just sinks)
                        rush += (Math.min(1, Math.abs(u - was) * 60) - rush) * 0.2; was = u
                        const amp = Theme.reduced ? 0 : 1 + rush * 3.5
                        const ca = testFill.red ? "224,64,90" : "245,163,192", cb = testFill.red ? "255,120,140" : "255,183,208"
                        g.reset()
                        // (inside the bar's own outline)
                        g.beginPath(); g.moveTo(r, 0); g.lineTo(w - r, 0); g.quadraticCurveTo(w, 0, w, r); g.lineTo(w, h - r); g.quadraticCurveTo(w, h, w - r, h)
                        g.lineTo(r, h); g.quadraticCurveTo(0, h, 0, h - r); g.lineTo(0, r); g.quadraticCurveTo(0, 0, r, 0); g.closePath(); g.clip()
                        let top = null // (running out of a lying bar: only what is under the sinking level is left)
                        if (!up && dr > 0) {
                            top = []
                            for (let x = 0; x <= w; x += 3) top.push([x, h * dr + Math.sin(x * 0.2 + t * 5) * 1.4 * (1 - dr) + Math.sin(x * 0.37 - t * 7) * 0.7 * (1 - dr)])
                            g.beginPath(); g.moveTo(0, h); for (const q of top) g.lineTo(q[0], q[1]); g.lineTo(w, h); g.closePath(); g.clip()
                        }
                        const edge = []
                        if (up) { // a level surface, rising
                            const level = h * (1 - u)
                            for (let x = 0; x <= w; x += 2) edge.push([x, level + Math.sin(x * 0.22 + t * 5) * amp * 0.7 + Math.sin(x * 0.4 - t * 7.5) * amp * 0.3])
                            g.beginPath(); g.moveTo(0, h); for (const q of edge) g.lineTo(q[0], q[1]); g.lineTo(w, h); g.closePath()
                            const gr = g.createLinearGradient(0, h, 0, level); gr.addColorStop(0, "rgba(" + ca + ",0.25)"); gr.addColorStop(1, "rgba(" + cb + ",0.6)")
                            g.fillStyle = gr; g.fill()
                        } else { // a front running along the floor: the bottom of it leads
                            const front = w * u, lean = 9 + rush * 10
                            for (let y = 0; y <= h; y += 2) {
                                const k = y / h
                                edge.push([front + (k * k - 0.45) * lean + Math.sin(y * 0.16 + t * 5) * amp + Math.sin(y * 0.3 - t * 7.5) * amp * 0.4, y])
                            }
                            g.beginPath(); g.moveTo(0, 0); for (const q of edge) g.lineTo(q[0], q[1]); g.lineTo(0, h); g.closePath()
                            const gr = g.createLinearGradient(0, 0, Math.max(1, front), 0); gr.addColorStop(0, "rgba(" + ca + ",0.22)"); gr.addColorStop(0.75, "rgba(" + ca + ",0.4)"); gr.addColorStop(1, "rgba(" + cb + ",0.7)")
                            g.fillStyle = gr; g.fill()
                        }
                        // the light on its surface
                        g.beginPath(); edge.forEach((q, n) => n ? g.lineTo(q[0], q[1]) : g.moveTo(q[0], q[1]))
                        g.strokeStyle = "rgba(255,255,255,0.55)"; g.lineWidth = 1.5; g.lineJoin = "round"; g.stroke()
                        if (top) { g.beginPath(); top.forEach((q, n) => n ? g.lineTo(q[0], q[1]) : g.moveTo(q[0], q[1])); g.stroke() }
                        // bubbles rising behind the front
                        if (!Theme.reduced) for (let n = 0; n < 6; n++) {
                            const life = (t * (0.5 + n * 0.07) + n * 0.37) % 1
                            const bx = up ? (n * 0.19 % 1) * w * 0.8 + w * 0.1 : w * u * (0.25 + (n * 0.137 % 0.7))
                            const by = up ? h - (h * u) * life : h - 3 - (h - 8) * life
                            g.beginPath(); g.arc(bx + Math.sin(t * 3 + n) * 1.5, by, 1 + (n % 3) * 0.5, 0, Math.PI * 2, false)
                            g.fillStyle = "rgba(255,255,255," + (0.35 * (1 - life)) + ")"; g.fill()
                        }
                    }
                }
            }

            // behind everything: quiet drifting shapes, or the night sky
            HomeBackdrop {
                anchors.fill: parent
                show: root.expanded && root.view === "home"
                quiet: !Hub.session.id && Hub.mood !== "sleep"
                asleep: Hub.mood === "sleep"
            }

            // collapsed, on top or bottom: the label and the state chip, right of the mini mascot.
            // On open the text slides 8 px left and fades out in 100 ms; on close it
            // slides back in from the right for the last 120 ms.
            Row {
                id: pillRow
                x: root.labelX + (root.expanded ? -8 : 0)
                Behavior on x { NumberAnimation { duration: root.expanded ? 100 : 120; easing.type: Easing.OutCubic } }
                y: (root.pillT - height) / 2
                height: 24
                spacing: 10
                opacity: root.expanded || root.floating || root.vertical ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: root.expanded ? 100 : 120 } }

                readonly property string label: root.barOwn ? ""
                    : Hub.chip !== "" ? ""
                    : Hub.mood === "work" ? Tr.d(Hub.statusLine)
                    : Hub.mood === "think" ? Tr.t("Thinking")
                    : (Hub.mood === "alert" || Hub.mood === "happy" || Hub.mood === "sad") ? ""
                    : mascot.displayName
                Text {
                    visible: pillRow.label !== ""
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: pillRow.label
                    // the label never pushes the pill past its widest
                    width: Math.min(implicitWidth, root.pillMax - root.labelX - 16 - root.castW - (Hub.mood === "work" ? 34 : 0))
                    elide: Text.ElideRight
                    color: Hub.mood === "sleep" ? Theme.inkFaint : Theme.ink
                    Behavior on color { ColorAnimation { duration: 160 } }
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                }
                PillBars { visible: Hub.mood === "work" && Hub.chip === "" && !root.barOwn; running: visible; anchors.verticalCenter: parent.verticalCenter }
                PillDots { visible: Hub.mood === "think" && Hub.chip === "" && !root.barOwn; running: visible; anchors.verticalCenter: parent.verticalCenter }
                PillChip { id: pillChip; kind: root.barOwn || Hub.chip === "done" ? "" : Hub.chip } // ("Done" has a chip of its own, below)
                BarPlayer {
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.miniPlayer
                    still: root.tucked
                    room: root.pillMax - root.labelX - 16 - root.castW
                }
                BarGauges {
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.miniGauges
                    room: root.pillMax - root.labelX - 16 - root.castW + 10 // (the gauges take the gap before the bench as well)
                }
                BarNet {
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.miniNet
                    room: root.pillMax - root.labelX - 16 - root.castW
                }
            }

            // Luka's Test key, at the far end before the bench: it stays put while her readings change
            BarNet.TestKey {
                x: root.pillW - 8 - 40 - 6 - width
                y: (root.pillT - height) / 2
                opacity: root.miniNet && !root.expanded && !root.floating && !root.vertical && !root.mfree ? (Net.online || Speed.running ? 1 : 0.4) : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            // "Done", in the middle of the bar, glowing and throwing stars
            DoneChip {
                x: (root.pillW - width) / 2
                y: (root.pillT - height) / 2
                on: Hub.chip === "done" && !root.doneSeen && !root.barOwn && !root.expanded && !root.floating && !root.vertical && !root.mfree
            }

            // the tune's progress: a hairline along the side of the bar that lies on the
            // screen's edge (that side is square, so it runs the bar's whole width), with a star for a head
            // (Where the player allows it the line is a handle too: press or drag along the
            // bar's edge and the track goes there. The line grows thicker under the pointer
            // to say so; `scrub` holds the star meanwhile, as on the open player.)
            Item {
                id: tuneLine
                x: 0
                y: root.dockSide === "bottom" ? root.pillT - height : 0
                width: root.pillW
                height: tuneScrub.containsMouse || tuneScrub.pressed ? 4 : 2
                Behavior on height { NumberAnimation { duration: 120 } }
                opacity: root.miniPlayer && !root.expanded && !root.floating && !root.vertical && !root.mfree && !root.barAir ? 1 : 0 // (in the hand the bar is round all over: the line would stick out of its corners)
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                property real scrub: -1
                readonly property real shown: scrub >= 0 ? scrub : Media.progress
                Timer { id: tuneHold; interval: 1200; onTriggered: tuneLine.scrub = -1 }
                MouseArea {
                    id: tuneScrub
                    x: 0
                    y: root.dockSide === "bottom" ? parent.height - 5 : 0
                    width: parent.width; height: 5
                    hoverEnabled: true
                    enabled: Media.canSeek && Media.duration > 0
                    cursorShape: Qt.PointingHandCursor
                    function at(m) { return Math.max(0, Math.min(1, m.x / width)) }
                    onPressed: (m) => { tuneHold.stop(); tuneLine.scrub = at(m) }
                    onPositionChanged: (m) => { if (pressed) tuneLine.scrub = at(m) }
                    onReleased: { Media.seek(tuneLine.scrub); Sfx.play("click"); tuneHold.restart() }
                    onCanceled: tuneLine.scrub = -1
                }
                Rectangle { anchors.fill: parent; radius: 1; color: Theme.ink; opacity: 0.1 }
                Rectangle {
                    id: tuneFill
                    height: parent.height; radius: 1
                    width: parent.width * tuneLine.shown
                    Behavior on width { enabled: !tuneScrub.pressed; NumberAnimation { duration: 500 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#FF9EBB" }
                        GradientStop { position: 0.6; color: "#FFE08A" }
                        GradientStop { position: 1; color: "#B9DC6B" }
                    }
                }
                Spark { // the head: a star that turns while the tune plays
                    size: 9
                    x: tuneFill.width - size / 2
                    y: parent.height / 2 - size / 2 // (its middle on the line; the half past the bar's edge is cut off with it)
                    scale: tuneScrub.pressed ? 1.5 : 1
                    Behavior on scale { NumberAnimation { duration: 160 } }
                    tint: "#FFFFFF"
                    opacity: Media.playing ? 1 : 0.5
                    RotationAnimation on rotation { running: root.miniPlayer && Media.playing && !Theme.reduced && !root.tucked; from: 0; to: 90; duration: 2400; loops: Animation.Infinite }
                }
            }

            // collapsed, on top or bottom: the four who are not on stage, at the bar's far end
            Grid {
                id: benchGrid
                columns: 2
                columnSpacing: 2
                rowSpacing: 0
                x: root.pillW - width - 8
                y: (root.pillT - height) / 2
                opacity: root.expanded || root.floating || root.vertical || root.mfree ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Repeater {
                    model: root.bench
                    Item {
                        id: seat
                        required property string modelData
                        width: 19; height: 15 // (they are wider than tall: two rows fit the bar)
                        // whoever has just sat down here pops in
                        NumberAnimation on scale { from: 0.2; to: 1; duration: 340; easing.type: Easing.OutBack; running: !Theme.reduced }
                        Mascot {
                            anchors.centerIn: parent
                            size: 18
                            bench: true
                            paused: root.tucked
                            character: seat.modelData
                            scale: seatArea.containsMouse ? 1.15 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: seatArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Hub.poke(); Sfx.play("click"); root.choose(seat.modelData) }
                        }
                    }
                }
            }

            // collapsed, on a side: under those at the head, what the lying bar says
            // (SideStack); at the bottom the bench, one under another; and the tune's line
            // down the side that lies on the screen's edge.
            SideStack {
                y: root.miniLead + root.mini + 8 + Math.round(root.duoW + root.heraldW)
                height: root.sideH - (root.miniLead + root.mini + 8) - root.sideBenchH - 6
                on: root.vertical && !root.expanded
                chip: Hub.chip !== "" && !(Hub.chip === "done" && root.doneSeen) ? Hub.chip : Hub.mood === "work" ? "work" : Hub.mood === "think" ? "think" : ""
                label: pillRow.label
                faint: Hub.mood === "sleep"
                player: root.miniPlayer
                gauges: root.miniGauges
                net: root.miniNet
                still: root.tucked
            }
            Column {
                id: sideBench
                x: 0
                y: card.height - height - 10
                opacity: root.vertical && !root.expanded ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Repeater {
                    model: root.vertical ? root.bench : []
                    Item {
                        id: stool
                        required property string modelData
                        width: root.pillT; height: 16
                        NumberAnimation on scale { from: 0.2; to: 1; duration: 340; easing.type: Easing.OutBack; running: !Theme.reduced }
                        Mascot {
                            anchors.centerIn: parent
                            size: 18
                            bench: true
                            paused: root.tucked
                            character: stool.modelData
                            scale: stoolArea.containsMouse ? 1.15 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: stoolArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Hub.poke(); Sfx.play("click"); root.choose(stool.modelData) }
                        }
                    }
                }
            }
            Item {
                id: tuneSide
                x: root.dockSide === "right" ? root.pillT - width : 0
                y: 0
                width: sideScrub.containsMouse || sideScrub.pressed ? 4 : 2
                height: card.height
                Behavior on width { NumberAnimation { duration: 120 } }
                opacity: root.miniPlayer && root.vertical && !root.expanded && !root.barAir ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                property real scrub: -1
                readonly property real shown: scrub >= 0 ? scrub : Media.progress
                Timer { id: sideHold; interval: 1200; onTriggered: tuneSide.scrub = -1 }
                MouseArea {
                    id: sideScrub
                    x: root.dockSide === "right" ? parent.width - 5 : 0
                    y: 0
                    width: 5; height: parent.height
                    hoverEnabled: true
                    enabled: Media.canSeek && Media.duration > 0
                    cursorShape: Qt.PointingHandCursor
                    function at(m) { return Math.max(0, Math.min(1, m.y / height)) }
                    onPressed: (m) => { sideHold.stop(); tuneSide.scrub = at(m) }
                    onPositionChanged: (m) => { if (pressed) tuneSide.scrub = at(m) }
                    onReleased: { Media.seek(tuneSide.scrub); Sfx.play("click"); sideHold.restart() }
                    onCanceled: tuneSide.scrub = -1
                }
                Rectangle { anchors.fill: parent; radius: 1; color: Theme.ink; opacity: 0.1 }
                Rectangle {
                    id: sideFill
                    width: parent.width; radius: 1
                    height: parent.height * tuneSide.shown
                    Behavior on height { enabled: !sideScrub.pressed; NumberAnimation { duration: 500 } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#FF9EBB" }
                        GradientStop { position: 0.6; color: "#FFE08A" }
                        GradientStop { position: 1; color: "#B9DC6B" }
                    }
                }
                Spark {
                    size: 9
                    x: parent.width / 2 - size / 2
                    y: sideFill.height - size / 2
                    scale: sideScrub.pressed ? 1.5 : 1
                    Behavior on scale { NumberAnimation { duration: 160 } }
                    tint: "#FFFFFF"
                    opacity: Media.playing ? 1 : 0.5
                    RotationAnimation on rotation { running: root.miniPlayer && root.vertical && Media.playing && !Theme.reduced && !root.tucked; from: 0; to: 90; duration: 2400; loops: Animation.Infinite }
                }
            }

            // In the chat, over her head: the account's limits as the session reports them
            // (through the kisel-prompts mod: see PromptRelay). The five-hour window, the
            // week, and how full the context is; under them, when the first one resets.
            Column {
                id: limitRings
                readonly property string sid: Hub.session.id || ""
                property var rows: []
                property string model: ""
                function reread() { rows = sid !== "" ? Relay.limits(sid) : []; model = sid !== "" ? Relay.model(sid) : "" }
                onSidChanged: reread()
                Component.onCompleted: reread()
                Connections { target: Relay; function onChanged() { limitRings.reread() } }
                function label(kind) { return kind === "five_hour" ? Tr.t("5 hours") : kind === "seven_day" ? Tr.t("Week") : kind === "context" ? Tr.t("Context") : kind === "spend_limit" ? Tr.t("Spend") : kind }
                // when it starts over: the hour for one that does today, the day for a later one
                function resets(r) {
                    if (!r.resetsAt) return ""
                    const d = new Date(r.resetsAt)
                    if (isNaN(d.getTime())) return ""
                    const soon = d.getTime() - Date.now() < 20 * 3600 * 1000
                    return Tr.t("until ") + (soon ? Qt.formatTime(d, "hh:mm") : Qt.formatDate(d, "d MMM"))
                }
                x: 16; y: 62
                width: 126
                spacing: 8
                opacity: root.expanded && root.view === "chat" && (rows.length > 0 || model !== "") ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 200 } }
                // the model the session runs on: here, out of the way of the talk
                Rectangle {
                    visible: limitRings.model !== ""
                    width: Math.min(parent.width, modelText.implicitWidth + 14); height: 18; radius: 9
                    color: Qt.rgba(1, 1, 1, 0.07)
                    Text {
                        id: modelText
                        anchors.verticalCenter: parent.verticalCenter
                        x: 7
                        width: parent.width - 14
                        elide: Text.ElideRight
                        text: limitRings.model
                        color: Theme.inkMuted
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                }
                Repeater {
                    model: limitRings.rows.slice(0, 4)
                    Row {
                        id: limitRow
                        required property var modelData
                        spacing: 8
                        LimitRing { used: limitRow.modelData.used }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: limitRings.label(limitRow.modelData.kind)
                                color: Theme.ink
                                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
                            }
                            Text {
                                visible: text !== ""
                                text: limitRings.resets(limitRow.modelData)
                                color: Theme.inkFaint
                                font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            // header: wordmark, title, icon buttons
            Item {
                id: header
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: root.expanded ? 220 : 120; easing.type: Easing.OutCubic } }
                width: parent.width
                height: 48

                Row {
                    x: 14; y: 12
                    spacing: Theme.space2
                    Mascot { size: 24; still: true; character: root.stage }
                    Text {
                        text: mascot.displayName
                        // (only on Home: on any other view the title stands where a long name would run into it)
                        opacity: root.view === "home" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        color: Theme.ink
                        font.family: Theme.display
                        font.weight: Font.Bold
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    TapHandler { onTapped: root.view = "home" }
                }
                Text {
                    x: 150; y: 12
                    width: 270
                    height: 24
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    text: root.view === "session" ? (Hub.session.name || Tr.t("Session"))
                        : root.view === "permission" ? (Hub.permission.kind === "question" ? Tr.t("Question") : Tr.t("Permission"))
                        : root.view === "chat" ? Tr.t("Chat")
                        : root.view === "github" ? "GitHub"
                        : root.view === "settings" ? Tr.t("Settings") : ""
                    color: Theme.ink
                    font.family: Theme.display
                    font.weight: Font.DemiBold
                    font.pixelSize: 20
                }
                // the bench again, on the open card: a click swaps her in
                Row {
                    id: headerBench
                    anchors.right: headerBtns.left
                    anchors.rightMargin: 10
                    y: 11
                    spacing: 4
                    Repeater {
                        model: root.bench
                        Item {
                            id: chair
                            required property string modelData
                            width: 26; height: 26
                            NumberAnimation on scale { from: 0.2; to: 1; duration: 340; easing.type: Easing.OutBack; running: !Theme.reduced }
                            Mascot {
                                anchors.centerIn: parent
                                size: 24
                                bench: true
                                character: chair.modelData
                                scale: chairArea.containsMouse ? 1.2 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                id: chairArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // (Rin with a notification waiting: the click goes to it, not to choosing her)
                                onClicked: { Sfx.play("click"); if (root.noteUp && chair.modelData === "rin") root.openNote(); else root.choose(chair.modelData) }
                            }
                        }
                    }
                }
                Row {
                    id: headerBtns
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    y: 8
                    spacing: 2
                    IconBtn { icon: Prefs.soundOn ? "sound" : "mute"; label: Prefs.soundOn ? Tr.t("Mute sounds") : Tr.t("Unmute sounds"); onClicked: Prefs.soundOn = !Prefs.soundOn }
                    IconBtn { icon: "chat"; label: Tr.t("Chat"); active: root.view === "chat"; onClicked: root.toggleView("chat") }
                    IconBtn { visible: !root.floating; icon: "move"; label: Tr.t("Move the bar"); onClicked: { Sfx.play("click"); root.startMove() } }
                    IconBtn { icon: "gear"; label: Tr.t("Settings"); active: root.view === "settings"; onClicked: root.toggleView("settings") }
                    IconBtn { visible: root.floating; icon: "up"; label: Tr.t("Close"); onClicked: root.collapseNow() }
                }
            }

            // views cross-fade in 140 ms, no sliding
            Item {
                x: 150; y: 48
                width: 494
                height: root.viewHeight - 62

                ViewHost {
                    id: hostHome
                    active: root.expanded && root.view === "home"
                    enterDelay: root.enterDelay
                    HomeView {
                        id: homeView
                        // (whose Home it is goes by who is on stage, not by who was chosen: while Miku
                        // is there, for Claude's work or a visit, the card is hers and shows the session)
                        own: root.stage === "zunda" && Prefs.zundaSpotify && Media.available ? "zunda"
                           : root.stage === "teto" && Prefs.tetoSystem && Sys.available ? "teto"
                           : root.stage === "luka" && Prefs.lukaNet && Net.available ? "luka" : ""
                        age: hostHome.age
                        revealCard: assembly.revealCard
                        revealButton: assembly.revealButton
                        revealTiles: [assembly.revealTile(0), assembly.revealTile(1), 1, 1]
                        active: root.expanded && root.view === "home"
                        height: 200 - 62
                        onGo: (v) => root.view = v
                    }
                }
                ViewHost {
                    id: hostSession
                    active: root.expanded && root.view === "session"
                    enterDelay: root.enterDelay
                    SessionView { id: sessionView; age: hostSession.age; active: hostSession.active; height: 300 - 62 }
                }
                ViewHost {
                    id: hostPermission
                    active: root.expanded && root.view === "permission"
                    enterDelay: root.enterDelay
                    PermissionView { age: hostPermission.age; active: hostPermission.active; height: root.viewHeight - 62 }
                }
                ViewHost {
                    id: hostGitHub
                    active: root.expanded && root.view === "github"
                    enterDelay: root.enterDelay
                    GitHubView { age: hostGitHub.age; active: hostGitHub.active; height: 276 - 62 }
                }
                ViewHost {
                    id: hostChat
                    active: root.expanded && root.view === "chat"
                    enterDelay: root.enterDelay
                    rises: false
                    ChatView {
                        id: chatView
                        who: root.stage
                        active: hostChat.active
                        dropActive: root.dropActive
                        height: 412 - 62
                    }
                }
                ViewHost {
                    id: hostSettings
                    active: root.expanded && root.view === "settings"
                    enterDelay: root.enterDelay
                    rises: false
                    SettingsView {
                        id: settingsView
                        active: hostSettings.active
                        height: 440 - 62
                        onToast: (text) => root.showToast(text)
                    }
                }
            }
        }

        // Notices appear beside the island, away from the screen's edge, and never on top of
        // the pill's label.
        Toast {
            id: toast
            x: root.vertical ? (root.edge === "left" ? card.x : card.x + card.width - width)
                             : card.x + (card.width - width) / 2
            baseY: root.atBottom ? card.y - 28 - (root.expanded ? 16 : 12 + 6)
                 : card.y + card.height + (root.expanded ? 16 : (root.floating ? 12 : (root.vertical ? 12 : 12 + 6 + 22)))
            z: 5
        }

        // the zone preview, while Kisel is carried near an edge (drawn in output coordinates)
        DockZone {
            x: -root.isoX; y: -root.isoY
            edge: root.zoneEdge !== "" ? root.zoneEdge : "top"
            along: root.zoneAlong
            distance: root.zoneDist
            tick: root.tickBrighter
            screenW: root.screenW; screenH: root.screenH
            active: dragArea.dragging && dragArea.snapped && root.zoneEdge !== "" && root.crossTarget === ""
        }

        // tucked away: the strip on the edge that brings the bar back
        Item {
            x: root.wakeRect.x; y: root.wakeRect.y
            width: root.wakeRect.width; height: root.wakeRect.height
            visible: root.tucked
            HoverHandler { id: wake }
        }

        // the jelly neck between the pill and the mascot while it is drawn out
        Neck {
            id: neck
            z: 1
            active: dragArea.picked && dragArea.haveOff && !dragArea.snapped
            maxDist: 36
        }

        // ---- the one mascot: it glides between slots, it is never swapped -----------
        Mascot {
            id: mascot
            z: 2
            readonly property int slot: !root.expanded ? (root.floating ? 120 : root.mini)
                : ({ home: 110, session: 88, permission: 88, github: 88, chat: 96, settings: 64 })[root.view]
            // collapsed: inside the bar, centred across it and `miniLead` from its leading end
            property real slotX: root.expanded ? 14 + (132 - slot) / 2
                : root.floating ? 0 : root.vertical ? root.miniPad : root.miniLead + (root.mikuLeft ? root.seatW : 0)
            property real slotY: root.expanded ? 48
                : root.floating ? 0 : root.vertical ? root.miniLead + (root.mikuLeft ? root.seatW : 0) : root.miniPad
            // Docked at the bottom the card grows upward, so there she is placed from the
            // card's bottom edge: one steady glide. (Placed from the top, her slot and the
            // card's height would animate against each other and she would leap up and drop.)
            property real slotB: root.expanded ? 12 : root.miniPad
            readonly property bool gliding: !root.mfree && !Theme.reduced
            size: root.mfree ? root.freeSize : slot
            x: root.mfree ? root.freeCX - root.freeSize / 2 - root.isoX : card.x + slotX + (root.vertical ? 0 : root.side * root.mainDx)
            y: root.mfree ? root.freeCY - root.freeSize / 2 - root.isoY
               : root.atBottom ? card.y + card.height - height - slotB : card.y + slotY + (root.vertical ? root.side * root.mainDx : 0)
            // "Reduce motion": the mascot does not glide, it fades between slots
            Behavior on size { enabled: mascot.gliding; NumberAnimation { duration: root.shrinking ? Theme.tClose : Theme.tOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: root.shrinking ? Theme.easeClose : Theme.easeGlide } }
            Behavior on slotX { enabled: mascot.gliding; NumberAnimation { duration: root.shrinking ? Theme.tClose : Theme.tOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: root.shrinking ? Theme.easeClose : Theme.easeGlide } }
            Behavior on slotY { enabled: mascot.gliding; NumberAnimation { duration: root.shrinking ? Theme.tClose : Theme.tOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: root.shrinking ? Theme.easeClose : Theme.easeGlide } }
            Behavior on slotB { enabled: mascot.gliding; NumberAnimation { duration: root.shrinking ? Theme.tClose : Theme.tOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: root.shrinking ? Theme.easeClose : Theme.easeGlide } }
            // docked on a side it leans 8 degrees toward the screen
            inwardTilt: (root.vertical && !root.expanded ? (root.edge === "left" ? 8 : -8) : 0) + root.sway
            Behavior on inwardTilt { NumberAnimation { duration: 200 } }
            // during the assembly the mini shows only between "born" and the unfold, and the
            // real mascot takes over from the flying body when the sequence settles
            opacity: (root.assembling ? ((assembly.t >= assembly.tBorn && assembly.t < assembly.tOpen + 60) || assembly.t >= assembly.tSettle ? 1 : 0) : 1) * root.slotDip
                     * (root.arriving.includes(root.stage) ? 0 : 1) // (still on her way from the bench)
            Behavior on opacity { NumberAnimation { duration: 120 } }
            skin: root.expanded && root.view === "github" ? "github" : ""
            holdPal: root.inChat
            walkDir: root.walkDir
            character: root.stage
            rotation: root.lean
            instant: root.duo
            music: root.tune
            // Claude's working and thinking are Miku's to act out. Anyone else on stage is
            // herself while Claude works: at ease, or (Teto) the way the computer feels.
            // (Sleep is Claude's too, and not for one who is busy with her own: Zundamon
            // does not doze off over a playing tune, nor Teto over a computer in trouble.)
            readonly property string own: (root.tetoAct && Sys.strain) || (root.lukaAct && Net.trouble) ? "sad" : "idle"
            mood: root.dropActive || root.carried ? "wow" : root.dropHappy ? "happy" : root.walking ? "walk"
                : root.stage !== "miku" && (root.claudeBusy || Hub.mood === "idle" || (Hub.mood === "sleep" && root.awake)) ? own : Hub.mood
            gazeOn: root.duo && root.duoLook
            gaze: root.vertical ? Qt.point(0, 0.9 * root.side) : Qt.point(0.9 * root.side, 0)
            paused: root.tucked && root.tuckA > root.pillT
            // She watches the pointer all over the screen where the platform says where it
            // is (Shell.pointerKnown), in the bar as well; elsewhere only while it is on the island.
            hovered: hover.hovered
            looking: Shell.pointerKnown || hover.hovered
            lookAt: Shell.pointerKnown ? Qt.point(Shell.pointerX - root.isoX - mascot.x, Shell.pointerY - root.isoY - mascot.y)
                                       : mascot.mapFromItem(card, hover.point.position.x, hover.point.position.y)
        }

        // the partner at work, beside her at the head of the bar (see "two at work")
        Mascot {
            id: buddy
            z: 2
            size: root.mini
            readonly property real along: root.miniLead + (root.mikuLeft ? 0 : root.seatW) + root.side * root.buddyDx
            x: root.vertical ? card.x + root.miniPad : card.x + along
            y: root.vertical ? card.y + along : (root.atBottom ? card.y + card.height - root.pillT : card.y) + (root.pillT - height) / 2
            character: root.buddyWho
            rotation: -root.lean
            inwardTilt: root.sway
            instant: true
            mood: root.buddyWho === "miku" && root.claudeBusy ? (Hub.mood === "think" ? "think" : "work") : "idle" // (only Miku does Claude's work)
            property real pop: root.duo ? 1 : 0
            Behavior on pop { NumberAnimation { duration: 320; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
            scale: pop * root.buddyPop
            visible: pop > 0.01 && !(!root.duo && root.flying.length > 0) // (not shrinking away under her own flight)
                     && !root.arriving.includes(root.buddyWho)             // (nor there before she has landed)
            paused: !visible || root.tucked
            gazeOn: true
            gaze: root.duoLook ? (root.vertical ? Qt.point(0, -0.9 * root.side) : Qt.point(-0.9 * root.side, 0)) : Qt.point(0, 0.25)
        }
        // a click on the partner opens the card, and if she is Miku it opens Miku's
        MouseArea {
            z: 4
            visible: buddy.visible
            x: buddy.x; y: buddy.y
            width: buddy.width; height: buddy.height
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Hub.poke()
                if (root.note && root.buddyWho === "rin") { Sfx.play("click"); root.openNote(); return } // (Rin with her sign)
                if (root.buddyWho === "miku") root.mikuAsked = true
                // (her card, if she has one of her own; Rin has none, nor has one whose service is off: Miku's then)
                const partner = root.buddyWho !== "miku" && root.hasCard(root.buddyWho) ? root.buddyWho : ""
                root.autoOpened = false; root.open()
                if (partner !== "") root.askedWho = partner // (once the card is opening: nobody flies off the bar for it)
            }
        }

        // Rin with a notification, after whoever is at the head (see "Rin and the notifications")
        Mascot {
            id: herald
            z: 2
            size: root.mini
            readonly property real along: root.miniLead + root.mini + 3 + root.duoW + root.heraldDx
            x: root.vertical ? card.x + root.miniPad : card.x + along
            y: root.vertical ? card.y + along : (root.atBottom ? card.y + card.height - root.pillT : card.y) + (root.pillT - height) / 2
            character: "rin"
            rotation: root.duo ? root.lean : -root.lean
            inwardTilt: root.sway
            instant: true
            mood: "idle"
            property real pop: root.heraldRin ? 1 : 0
            Behavior on pop { NumberAnimation { duration: 320; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
            scale: pop * root.heraldPop
            visible: pop > 0.01 && !root.flying.includes("rin") && !root.arriving.includes("rin")
            paused: !visible || root.tucked
            gazeOn: true
            gaze: root.duoLook ? (root.vertical ? Qt.point(0, -0.9) : Qt.point(-0.9, 0))
                : root.vertical ? Qt.point(0.6 * root.inward, -0.1) : Qt.point(0.5, -0.3) // (at the others, or at her sign)
        }
        // those on their way back to the bench (see "back to the bench")
        Repeater {
            id: flyers
            model: root.cast
            Mascot {
                id: fl
                required property string modelData
                readonly property string who: modelData
                property bool coming: false   // from the bench to the head, not the other way
                property string role: "main"  // (coming) whose place she is going to
                property int seatIn: 0        // (coming) the seat she leaves
                property real fromX: 0        // (going) where she sat at the head
                property real u: 0            // 0..1 along the way
                readonly property bool up: root.flying.includes(who) || root.arriving.includes(who)
                readonly property int seat: coming ? seatIn : root.benchAfter.indexOf(who)
                readonly property real barTop: root.atBottom ? card.y + card.height - root.pillT : card.y
                // her seat on the bench (it is two wide)
                // (on a standing bar the bench is one wide, at the bottom)
                readonly property int benchN: coming ? root.benchWas.length : root.benchAfter.length
                readonly property real benchX: root.vertical ? card.x + (root.pillT - 18) / 2
                    : card.x + card.width - 8 - 40 + (seat % 2) * 21
                readonly property real benchY: root.vertical ? card.y + card.height - 10 - (benchN - seat) * 16 - 1
                    : barTop + 1 + Math.floor(seat / 2) * 15 - 1.5
                // her place at the head
                readonly property Item place: role === "buddy" ? buddy : role === "herald" ? herald : mascot
                readonly property real headX: root.vertical ? card.x + root.miniPad : coming ? place.x : fromX
                readonly property real headY: root.vertical ? (coming ? place.y : fromX) : barTop + (root.pillT - root.mini) / 2
                readonly property real k: coming ? 1 - u : u // 0 at the head, 1 on the bench
                function go(x) { coming = false; fromX = x; u = 0; flight.restart(); play("hype", 900) }
                function come(s, r) { coming = true; seatIn = s; role = r; u = 0; flight.restart(); play("hello", 900) }
                function stop() { flight.stop(); u = 0 }
                z: 5
                size: root.mini - (root.mini - 18) * k
                // (the arc goes over the bar where there is room for it, and under it on the top edge;
                // from a standing bar it goes out into the screen)
                x: headX + (benchX - headX) * k + (root.vertical ? root.inward * Math.sin(Math.PI * u) * 24 : 0)
                y: headY + (benchY - headY) * k + (root.vertical ? 0 : (root.atBottom ? -1 : 1) * Math.sin(Math.PI * u) * 24)
                rotation: (coming ? -1 : 1) * u * 360
                character: who
                instant: true
                mood: "idle"
                visible: up && seat >= 0
                paused: !visible
                NumberAnimation { id: flight; target: fl; property: "u"; from: 0; to: 1; duration: 620; easing.type: Easing.InOutSine; onFinished: root.landed(fl.who) }
            }
        }
        NoteSign {
            id: sign
            z: 3
            flip: !root.atBottom && !root.vertical
            x: root.vertical ? (root.inward > 0 ? card.x + root.pillT - 6 : card.x - fullW + 6) : root.rinNow.x + root.rinNow.width - 9
            y: root.vertical ? root.rinNow.y - 8
                : (root.atBottom ? card.y + card.height - root.pillT - 19 : card.y + root.pillT - 11)
            on: root.note
            still: root.tucked
            app: root.signApps.length ? root.signApps[0] : ""
            count: root.signCounts.length ? root.signCounts[0] : 1
            apps: root.signApps
            counts: root.signCounts
            onXChanged: root.updateHit()
            onWidthChanged: root.updateHit()
        }
        // On the open card the sign stands over Rin's seat in the header (or over the
        // header's own mascot when Rin is the one on stage), out past the card's edge
        // like the bar's; under a card docked on top it hangs below the header instead.
        NoteSign {
            id: signOpen
            z: 3
            readonly property int seat: root.bench.indexOf("rin")
            flip: !root.atBottom
            x: card.x + (seat >= 0 ? headerBench.x + seat * (26 + headerBench.spacing) + 18 : 14 + 16)
            y: root.atBottom ? card.y - 19 : card.y + 36
            on: root.noteUp && root.expanded && !root.floating && !root.mfree && !root.assembling
            still: root.tucked
            app: root.signApps.length ? root.signApps[0] : ""
            count: root.signCounts.length ? root.signCounts[0] : 1
            apps: root.signApps
            counts: root.signCounts
            onOnChanged: root.updateHit()
            onYChanged: root.updateHit()
        }
        MouseArea {
            z: 4
            visible: signOpen.on
            x: signOpen.x; y: signOpen.flip ? signOpen.y + 10 : signOpen.y
            width: signOpen.fullW; height: 20
            cursorShape: Qt.PointingHandCursor
            onClicked: { Hub.poke(); Sfx.play("click"); root.openNote() }
        }
        // looked at: a click on Rin, or on her sign
        MouseArea {
            z: 4
            visible: root.note
            x: root.vertical ? card.x : root.rinNow.x
            y: root.vertical ? root.rinNow.y : (root.atBottom ? card.y + card.height - root.pillT : card.y)
            width: root.vertical ? root.pillT : root.rinNow.width; height: root.vertical ? root.rinNow.height : root.pillT
            cursorShape: Qt.PointingHandCursor
            onClicked: { Hub.poke(); Sfx.play("click"); root.openNote() }
        }
        MouseArea {
            z: 4
            visible: root.note
            x: sign.x; y: sign.flip ? sign.y + 10 : sign.y
            width: sign.fullW; height: 20
            cursorShape: Qt.PointingHandCursor
            onClicked: { Hub.poke(); Sfx.play("click"); root.openNote() }
        }

        // the notes that rise over their heads while they dance (see `skDisco`)
        Repeater {
            model: 7
            PlayGlyph { // (drawn, not a letter: the font has no notes)
                id: tune
                required property int index
                readonly property int who: index % root.row().length
                readonly property real barTop: root.atBottom ? card.y + card.height - root.pillT : card.y
                property real u: 0 // 0..1 on its way up
                z: 6
                kind: "note"
                size: 9 + (index % 3)
                tint: ["#FF9EBB", "#FFE08A", "#B9DC6B", "#FFFFFF"][index % 4]
                readonly property real along: root.miniLead + root.mini / 2 + who * root.seatW + Math.sin(u * 6 + index) * 5 + (index % 3 - 1) * 5
                x: root.vertical ? (root.inward > 0 ? card.x + root.pillT - 3 + u * 36 : card.x + 3 - width - u * 36) : card.x + along - width / 2
                // (up out of the bar; down out of one docked on the top edge; out into the screen from a standing one)
                y: root.vertical ? card.y + along - height / 2 : root.atBottom ? barTop + 3 - height - u * 36 : barTop + root.pillT - 3 + u * 36
                opacity: root.discoOn ? Math.sin(Math.PI * u) : 0
                visible: opacity > 0.01
                scale: 0.7 + 0.5 * Math.sin(Math.PI * u)
                rotation: Math.sin(u * 5 + index) * 18
                SequentialAnimation on u {
                    running: root.discoOn
                    loops: Animation.Infinite
                    PauseAnimation { duration: tune.index * 230 }
                    NumberAnimation { from: 0; to: 1; duration: 1500; easing.type: Easing.OutSine }
                    PauseAnimation { duration: 1380 - tune.index * 230 }
                }
            }
        }

        // the star that passes between the two
        Spark {
            z: 3
            size: 9
            tint: "#FFE08A"
            opacity: root.tossA
            visible: opacity > 0.01
            readonly property real along: root.miniLead + root.mini / 2 + root.tossX(root.tossU) * root.seatW
            readonly property real arc: 3 + Math.abs(Math.sin(Math.PI * root.tossU)) * 9
            x: root.vertical ? card.x + root.pillT / 2 + root.inward * arc - size / 2 : card.x + along - size / 2
            y: root.vertical ? card.y + along - size / 2
                : (root.atBottom ? card.y + card.height - root.pillT : card.y) + root.pillT / 2 - arc - size / 2
            rotation: root.tossU * 180
            scale: 0.8 + root.tossA * 0.5
        }

        // the hold ring around the mascot, and the ripples (output coordinates, island offset)
        HoldRing {
            id: ring
            size: mascot.width + 10
            x: mascot.x - 5; y: mascot.y - 5
            z: 3
            progress: dragArea.hold
        }
        Ripple { id: landRipple; anchors.fill: parent; z: 6 }
        Ripple { id: magnetRipple; anchors.fill: parent; z: 6 }
        Ripple { id: contactRipple; anchors.fill: parent; z: 6 }

        // Drag the mascot. A click shorter than 350 ms opens or closes the card; holding for
        // 350 ms picks Kisel up (a ring fills, then it is drawn out of the pill on a jelly
        // neck). Carry it anywhere; near an edge a zone appears and letting go docks it there.
        //
        // While the pointer is down the surface covers the whole output and stays still
        // (Shell.beginGrab); the mascot moves inside it by the pointer's exact position, so
        // there is no lag, no overshoot and no way to leave the screen.
        MouseArea {
            id: dragArea
            z: 4
            x: mascot.x; y: mascot.y
            width: mascot.width; height: mascot.height
            cursorShape: picked ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            enabled: !root.greeting
            property real hold: 0                 // the ring's progress, 0..1
            property bool picked: false           // the 350 ms are up and Kisel is in the hand
            property bool haveOff: false          // the first output-sized event has arrived
            property bool snapped: true           // the neck has snapped (or there never was one)
            property bool moved: false
            property point offC: Qt.point(0, 0)   // pointer minus the mascot's centre, output coordinates
            property point pressOff: Qt.point(0, 0) // the same, as it was when the button went down
            property real catchUp: 1              // 0..1: Kisel eases onto the pointer after a late pick-up
            property point pressPt: Qt.point(0, 0)
            property point lastC: Qt.point(0, 0)
            property double lastT: 0
            property real vx: 0
            property real vy: 0
            property point tC: Qt.point(0, 0)     // where the pointer wants the centre (unclamped)
            readonly property bool dragging: picked && haveOff

            function rootPoint(m) { return mapToItem(root, m.x, m.y) }
            function scenePoint(m) { return mapToItem(null, m.x, m.y) }
            function geom(name) {
                for (const s of Displays.screens) if (s.name === name) return s
                return { x: 0, y: 0, w: root.screenW, h: root.screenH }
            }

            NumberAnimation { id: holdAnim; target: dragArea; property: "hold"; from: 0; to: 1; duration: 350; easing.type: Easing.OutQuad
                onFinished: if (dragArea.pressed) dragArea.pickUp() }
            Timer { id: stillTimer; interval: 90; onTriggered: { mascot.dragVx = 0; mascot.dragVy = 0; dragArea.vx = 0; dragArea.vy = 0 } }
            Timer { id: settleGuard; interval: 700; onTriggered: root.tryFinishFree() }

            function pickUp() {
                picked = true; haveOff = false
                snapped = root.floating // from a pill the neck must snap first
                ring.popped = true
                mascot.dragging = true
                if (root.expanded) root.collapseNow() // the card, if open, closes (200 ms)
                Shell.beginGrab()
            }

            // the first pointer event on the output-sized surface: from here Kisel is free
            function beginFree(P) {
                const bc = Qt.point(mascot.x + mascot.width / 2 + root.isoX, mascot.y + mascot.height / 2 + root.isoY)
                // Kisel is held by the spot where the button went down, not by wherever the
                // pointer has got to during the 350 ms: if it moved, Kisel catches up
                offC = pressOff
                catchUp = Theme.reduced ? 1 : 0
                catchAnim.restart()
                bcStart = bc
                root.freeCX = bc.x; root.freeCY = bc.y; root.freeSize = mascot.size
                root.mfree = true
                haveOff = true
                lastC = bc; lastT = Date.now()
                root.crossTarget = ""
                if (root.floating) root.snapSize = false
                neck.from = Qt.point(bc.x - root.isoX, bc.y - root.isoY)
                neck.to = neck.from
            }

            property point bcStart: Qt.point(0, 0)
            NumberAnimation { id: catchAnim; target: dragArea; property: "catchUp"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }

            function carry(P) {
                if (!haveOff) { beginFree(P); return }
                const now = Date.now()
                let tcx = P.x - offC.x, tcy = P.y - offC.y
                tC = Qt.point(tcx, tcy)
                if (catchUp < 1) { // ease from where Kisel stood onto the pointer
                    tcx = bcStart.x + (tcx - bcStart.x) * catchUp
                    tcy = bcStart.y + (tcy - bcStart.y) * catchUp
                }
                if (Shell.debugOn) Shell.log("carry P=" + Math.round(P.x) + "," + Math.round(P.y) + " snapped=" + snapped)
                const dt = Math.max(1, now - lastT)
                vx = 0.55 * vx + 0.45 * (tcx - lastC.x) / dt * 1000
                vy = 0.55 * vy + 0.45 * (tcy - lastC.y) / dt * 1000
                mascot.dragVx = vx; mascot.dragVy = vy
                lastC = Qt.point(tcx, tcy); lastT = now
                stillTimer.restart()

                if (!snapped) {
                    // being drawn out of the pill: the neck stretches, the pill dents 4 px toward Kisel
                    const sc = Qt.point(neck.from.x + root.isoX, neck.from.y + root.isoY)
                    const dx = tcx - sc.x, dy = tcy - sc.y
                    const d = Math.hypot(dx, dy)
                    root.freeCX = tcx; root.freeCY = tcy
                    neck.to = Qt.point(tcx - root.isoX, tcy - root.isoY)
                    const k = d > 0 ? Math.min(1, d / 36) * 4 / d : 0
                    root.dentX = Theme.reduced ? 0 : dx * k; root.dentY = Theme.reduced ? 0 : dy * k
                    if (d >= 36) {                      // the neck snaps: two droplets fall, the pill recovers
                        snapped = true
                        neck.snap(Qt.point(sc.x - root.isoX, sc.y - root.isoY))
                        root.dentX = 0; root.dentY = 0
                        root.ghost = true               // the pill fades away behind Kisel
                        root.growing = true
                        root.freeSize = 120             // grows from `mini` to 120 along the drag
                        mascot.land()
                    }
                    return
                }

                // carried: the centre follows the pointer. Where another monitor touches this one
                // the mascot goes on across the seam (drawn on both monitors, clipped at the
                // seam); everywhere else the edge of the desktop is a wall.
                const half = root.freeSize / 2
                const g = geom(Displays.current)
                const gcx = g.x + tcx, gcy = g.y + tcy             // the centre on the whole desktop
                const here = Displays.screenAt(gcx, gcy)           // the monitor under the centre ("" in a gap)
                let Cx, Cy
                if (here !== "") {
                    const U = root.desktopRect()
                    Cx = Math.max(U.x + half, Math.min(U.x + U.w - half, gcx)) - g.x
                    Cy = Math.max(U.y + half, Math.min(U.y + U.h - half, gcy)) - g.y
                } else {
                    Cx = Math.max(half, Math.min(root.screenW - half, tcx))
                    Cy = Math.max(half, Math.min(root.screenH - half, tcy))
                }
                root.freeCX = Cx; root.freeCY = Cy
                const overX = tcx - Cx, overY = tcy - Cy

                // draw the mascot on every other monitor its box touches
                let straddling = false
                for (const s of Displays.screens) {
                    if (s.name === Displays.current) continue
                    const gx = g.x + Cx, gy = g.y + Cy
                    const touches = gx + half > s.x && gx - half < s.x + s.w && gy + half > s.y && gy - half < s.y + s.h
                    if (touches) {
                        straddling = true
                        Seams.show(s.name, gx - s.x, gy - s.y, root.freeSize, vx, vy, Hub.mood)
                    } else {
                        Seams.hideScreen(s.name)
                    }
                }
                const crossing = here !== "" && here !== Displays.current
                if (Shell.debugOn) Shell.log("carry C=" + Math.round(Cx) + "," + Math.round(Cy) + " here=" + here + " straddling=" + straddling + " cross=" + crossing)
                if (straddling && !root.straddling) contactRipple.go(Cx - root.isoX, Cy - root.isoY) // contact: a ripple
                root.straddling = straddling
                root.crossTarget = crossing ? here : ""

                if (straddling) { root.zoneEdge = ""; root.zoneDist = 999; root.leaning = false }
                else root.updateZone()
                root.setWall(overX, overY)
            }

            function springBack() {
                // let go before the neck snapped: Kisel springs back into the pill
                springFrom = Qt.point(root.freeCX, root.freeCY)
                springTo = Qt.point(neck.from.x + root.isoX, neck.from.y + root.isoY)
                springAnim.restart()
                root.dentX = 0; root.dentY = 0
            }

            function release() {
                Seams.hideAll()
                root.straddling = false
                if (Shell.debugOn) Shell.log("release picked=" + picked + " haveOff=" + haveOff + " snapped=" + snapped + " cross=" + root.crossTarget + " zone=" + root.zoneEdge)
                const had = haveOff
                mascot.dragging = false
                mascot.dragVx = 0; mascot.dragVy = 0; vx = 0; vy = 0; stillTimer.stop()
                root.clearWall()
                root.leaning = false
                if (!had) {                         // held and let go in place
                    picked = false
                    Shell.endGrab()
                    mascot.land()
                    return
                }
                if (!snapped) { picked = false; springBack(); return }

                const wasZone = root.zoneEdge !== "" && root.zoneDist < 20 && root.crossTarget === ""
                if (root.crossTarget !== "") {
                    // across the seam: float on the other monitor, where the pointer is
                    const g = geom(Displays.current), tg = geom(root.crossTarget)
                    const cx = g.x + tC.x - tg.x, cy = g.y + tC.y - tg.y
                    root.snapSize = true
                    root.settling = true
                    picked = false
                    Displays.crossTo(root.crossTarget, cx - 60, cy - 60)
                    root.hopOnLand = 0.25                   // it settles on the new monitor with a small hop
                    Prefs.floating = true; Prefs.floatX = Shell.floatX; Prefs.floatY = Shell.floatY
                    root.crossTarget = ""
                    settleGuard.restart()
                } else if (wasZone) {
                    const used = Shell.setDock(root.zoneEdge, root.zoneAlong)
                    Prefs.floating = false
                    Prefs.setDock(Displays.current, root.zoneEdge, used / Shell.edgeLength(root.zoneEdge))
                    root.snapSize = true
                    root.settling = true
                    root.arcDone = false
                    picked = false
                    Shell.endGrab()
                    root.startDockArc()
                    settleGuard.restart()
                } else {
                    // dropped in the open: it lands where it is
                    root.snapSize = true
                    root.settling = true
                    Shell.restoreFloat(root.freeCX - 60 - 294, root.freeCY - 60 - 8)
                    Prefs.floating = true; Prefs.floatX = Shell.floatX; Prefs.floatY = Shell.floatY
                    picked = false
                    Shell.endGrab()
                    settleGuard.restart()
                }
                root.zoneEdge = ""; root.zoneDist = 999
            }

            // the spring back into the pill (380 ms OutElastic)
            property real springT: 0
            property point springFrom: Qt.point(0, 0)
            property point springTo: Qt.point(0, 0)
            NumberAnimation { id: springAnim; target: dragArea; property: "springT"; from: 0; to: 1; duration: 380
                easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45
                onFinished: { Shell.endGrab(); root.tryFinishFree() } }
            onSpringTChanged: {
                if (!springAnim.running) return
                root.freeCX = springFrom.x + (springTo.x - springFrom.x) * springT
                root.freeCY = springFrom.y + (springTo.y - springFrom.y) * springT
                root.freeSize = root.mini
            }

            onPressed: (m) => {
                if (Shell.debugOn) Shell.log(Date.now() % 100000 + " press at " + Math.round(m.x) + "," + Math.round(m.y))
                if (root.walking) mascot.hang() // picked up mid-walk: the body hangs and sways
                root.stopWander()
                if (root.dockT > 0 && dockAnim.running) return
                pressPt = rootPoint(m)
                pressOff = Qt.point(m.x - width / 2, m.y - height / 2)
                picked = false; haveOff = false; moved = false
                ring.popped = false
                hold = 0
                if (root.expanded || root.floating) mascot.compress() // press compression; none on the click that opens
                if (root.canPickUp) holdAnim.restart()
            }
            onPositionChanged: (m) => {
                if (!pressed) return
                if (!picked) {
                    const c = rootPoint(m)
                    if (Math.hypot(c.x - pressPt.x, c.y - pressPt.y) > 8) moved = true
                    return
                }
                if (!Shell.viewWide) return         // wait for the compositor to give us the whole output
                carry(scenePoint(m))
            }
            function finishPress(clicked) {
                holdAnim.stop()
                if (picked) { release(); return }
                const progressed = hold
                hold = 0
                if (clicked && !moved && !dockAnim.running) { // (not `dockT === 0`: it rests at 1 once she has landed)
                    // a click opens the card quietly; on the open card it is a slap
                    // (she sulks, and three in a row make her dizzy)
                    Hub.poke()
                    if (root.floating) {
                        if (root.expanded) root.collapseNow()
                        else { root.autoOpened = false; root.open() }
                    } else if (!root.expanded && root.note && root.stage === "rin") {
                        Sfx.play("click"); root.openNote()                  // (Rin with her sign: the notifications, not the card)
                    } else if (!root.expanded) {
                        if (root.stage === "miku") root.mikuAsked = true // (Miku clicked: her card)
                        root.open()
                    } else {
                        mascot.poke()
                    }
                } else if (progressed > 0.1) {
                    mascot.land()                  // a hold let go early: a small recoil
                }
            }
            onReleased: finishPress(true)
            onCanceled: finishPress(false)
        }

        // where the bar would land, while it is in the hand
        Rectangle {
            z: 1
            x: root.landX - root.isoX; y: root.landY - root.isoY
            width: root.closedW; height: root.closedH
            radius: 14
            color: "#FFE08A"
            border.width: 2; border.color: "#FFFFFF"
            property real show: root.barAir ? 1 : 0
            Behavior on show { NumberAnimation { duration: 160 } }
            visible: show > 0.01
            Behavior on x { enabled: root.barAir && !Theme.reduced; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: root.barAir && !Theme.reduced; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: root.barAir && !Theme.reduced; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: root.barAir && !Theme.reduced; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            property real breath: 0.3
            opacity: show * breath
            SequentialAnimation on breath {
                running: root.barAir && !Theme.reduced
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 460; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.2; duration: 460; easing.type: Easing.InOutSine }
            }
        }
        // the bar, waiting to be dragged (see `moving`)
        Rectangle {
            visible: root.moving
            z: 5
            // (the bar's own outline, 3 px out: its flush side runs off the screen with the bar's)
            x: card.x + root.shapeX - 3; y: card.y + root.shapeY - 3
            width: root.shapeW + 6; height: root.shapeH + 6
            radius: root.radius + 3
            color: "transparent"
            border.width: root.carried ? 3 : 2
            border.color: root.carried ? "#FFFFFF" : "#FFE08A"
            Behavior on border.color { ColorAnimation { duration: 160 } }
            SequentialAnimation on opacity {
                running: root.moving && !root.carried && !Theme.reduced
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.35; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1; duration: 500; easing.type: Easing.InOutSine }
            }
        }
        MouseArea {
            id: moveArea
            visible: root.moving
            z: 6
            x: Math.min(card.x, mascot.x); y: Math.min(card.y, mascot.y)
            width: Math.max(card.x + card.width, mascot.x + mascot.width) - x
            height: Math.max(card.y + card.height, mascot.y + mascot.height) - y
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point off: Qt.point(0, 0) // the pointer minus the bar's middle
            property bool dragged: false
            // the pointer on the output
            function where(m) { const q = mapToItem(root, m.x, m.y); return Qt.point(q.x + root.isoX, q.y + root.isoY) }
            onPressed: (m) => {
                dragged = false
                const P = where(m)
                off = Qt.point(P.x - (root.isoX + card.x + card.width / 2), P.y - (root.isoY + card.y + card.height / 2))
                root.pickUp()
                mascot.compress(); Sfx.play("hover")
                if (!Theme.reduced) { if (root.duo) buddy.jump(0.4, true); if (root.heraldRin) herald.jump(0.4, true) }
            }
            onPositionChanged: (m) => {
                if (!pressed || !root.barAir) return
                const P = where(m)
                dragged = true
                root.carryTo(P.x - off.x, P.y - off.y)
            }
            onReleased: { if (dragged) Sfx.play("click"); root.letGo() }
            onCanceled: root.letGo()
        }

        // the stars that fall off the bar as it is carried
        Repeater {
            id: trail
            model: 14
            Spark {
                id: mote
                required property int index
                property real px: 0
                property real py: 0
                property real dx: 0
                property real dy: 0
                property real ox: 0
                property real oy: 0
                property real u: 1
                function shoot(x, y, vx, vy) { px = x; py = y; dx = vx; dy = vy; ox = root.isoX; oy = root.isoY; life.restart() }
                z: 4
                size: 7 + (index % 3) * 2
                tint: ["#FFE08A", "#FF9EBB", "#B9DC6B", "#FFFFFF"][index % 4]
                x: px + ox - root.isoX + dx * 22 * u - size / 2
                y: py + oy - root.isoY + dy * 22 * u + 10 * u * u - size / 2
                opacity: u < 1 ? 1 - u * u : 0
                visible: opacity > 0.01
                scale: 0.5 + Math.sin(Math.PI * Math.min(1, u * 1.4)) * 0.9
                rotation: u * 200 + index * 40
                NumberAnimation { id: life; target: mote; property: "u"; from: 0; to: 1; duration: 620 + mote.index % 4 * 60; easing.type: Easing.OutCubic }
            }
        }

        DoneBurst { id: burst; anchors.fill: parent; z: 10 }
    }

    // ---- development helpers (kisel --drag-test, --dock-edge) ---------------------------
    function devState() {
        return "edge=" + Shell.edge + " floating=" + floating + " wide=" + Shell.viewWide + " mfree=" + mfree
             + " picked=" + dragArea.picked + " snapped=" + dragArea.snapped + " zone=" + zoneEdge
             + " dist=" + Math.round(zoneDist) + " cross=" + crossTarget
             + " origin=" + Math.round(Shell.originX) + "," + Math.round(Shell.originY)
    }
    function devCenter() { return Qt.point(mascot.x + mascot.width / 2, mascot.y + mascot.height / 2) }
    function devDock(edge, frac) { Shell.setDock(edge, frac * Shell.edgeLength(edge)); updateHit() }

    Keys.onEscapePressed: { closeTimer.stop(); root.collapseNow() }

    component IconBtn: FocusScope {
        id: btn
        property string icon: ""
        property string label: ""
        property bool active: false
        signal clicked()
        width: 32; height: 32
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: tap.pressed || btn.active || bh.hovered ? Theme.surface3 : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            border.width: btn.activeFocus ? 2 : 0
            border.color: Theme.kisel
            scale: tap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
            Icon {
                anchors.centerIn: parent
                size: 20
                name: btn.icon
                color: bh.hovered || btn.active ? Theme.ink : Theme.inkMuted
            }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
