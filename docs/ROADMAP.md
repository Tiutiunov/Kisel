# Roadmap

Status of every behaviour in the design system (`README.md`, `motion.md`, `components/`). **Done** = in this repo; **Untested** = built but not exercised against the real thing; **Next** = specified or planned, not built.

## Done

**Shell and views**
* Island: collapsed black pill (status dot + word) ⇄ Home / Session / Permission / Chat / GitHub / Settings at the spec sizes, 280 ms OutCubic, hover open, 600 ms close timer, hold-open rules, peek on task done, three-layer soft shadow, 140 ms view cross-fade, one mascot gliding between slots.
* Floating mascot: drag > 36 px out of the island to float, drag around the desktop (jelly-trailing), within 20 px of the top edge to dock, click to open the card in place (it slides to stay on screen), close icon, position remembered, wandering every 18-48 s with the `walk` mood.
* Monitor picker: a mini-map of your outputs in Settings, remembered by output name, falls back to the primary and returns when the monitor is plugged back in; arrives with a hop.

**Mascot**: idle, think, work, alert, wow, happy, sad, sleep, dizzy, walk; blink, breathing, leaf, spring eyes, click squash, jump, badge, sparkles, "z", dizzy orbit with brand shapes, GitHub skin (graphite, white sparkles), wake-up blink, reduce-motion switches.

**Components** (from `components/`): buttons (primary / secondary / ghost / danger, 3 px focus ring, 40 % disabled), status pills (dot + word), launch tiles 104×84 (Claude, GitHub), chat bubbles (squared corner, inline code, timestamp), permission card (command, diff, question), island states.

**Brand-shape motion** (`motion.md`, "Brand shapes in motion"): first-launch cover assembly and the full first-launch timeline, task-done ring + confetti burst, amber attention tab (with extra-request dots), jelly-trio loader, dot wave (listening) and 6×3 drop-hint grid, success move (pill → disc → check draws itself → "Connected"/"Saved"), quiet-screen drift, night sky while asleep, toasts, step check that draws itself, diff-line stagger, amber "modified" dot, reduced-motion fallbacks.

**Integrations**: Claude Code hooks (install/remove with diff + backup), permissions, **AskUserQuestion answered from the island** (up to four questions, single or multi-select), chat with Claude, **GitHub widget** (open PRs with CI state, reviews waiting, read-only token in KWallet, 5-minute refresh), sounds through PipeWire.

**Quality**: 18 unit tests (hub, rule keys, hook merge, diff, SSE, GitHub parsing, question answer line, socket round trip), relay verified against a fake server.

## Done in the "collapsed v2 and motion" pass
* **Collapsed island v2**: 44 px pill (176 to 280 px, widening to its status) with a 1 px line, the flat mini Kisel hanging 6 px below it, label, state chips (Needs you, Done for 25 s, Failed), working bars and thinking dots; `kisel-mini.svg` for the header and tray.
* **Level of detail**: one mascot body at every size; `detail = clamp((size - 44) / 66, 0, 1)` fades in gradient, gloss, cheeks, eye highlights, ground shadow and badge, and fades out the outline ring, so the pill's mini turns into the full mascot continuously as the island opens.
* **First launch, the assembly**: the cover drops in and holds, the half-round flattens into the pill, the mint disc flies into the leaf spot, the island opens and the shapes become Kisel's body (outline interpolated pill to pudding), its gloss, the hook card, the button and the tiles. A pure function of one clock, skippable by a click, and played as a plain fade with reduce motion. `kisel --intro` replays it.
* **Mood to mood**: moods are split into body, face, badge and leaf parts that follow with their own delays, plus pre-actions: startle, nod (small and big), breath-out, deep breath, shake-off, dizzy slow-down, wake-up blink, lean, skid, pendulum.
* **Island size to size**: the card leads on the way in (content follows 60 ms behind), the content leads on the way out; blocks rise 8 px, staggered 30 ms; the permission queue slides 24 px with a rolling "1 of N"; lists animate adds and moves.
* **Detach, dock, walk**: landing squash on release, magnet ring at 20 px, an arc into the pill's slot (320 ms) with the mascot shrinking, hop before the card opens, pendulum when picked up mid-walk, lean and 70 % first hop when a walk starts, skid when it ends.
* **Shapes in events**: the burst starts from the pill's chip and the peek opens at its peak; the attention tab merges into the card when it opens; the jelly trio merges into a check (or a shaking danger pill); drift and sky cross-fade.
* **Reduce motion**: every transition becomes a 140 ms cross-fade, bridges keep only their order (body, face, badge), no flights, the mascot fades between slots.

## Done in the "dragging, edges and monitors" pass (motion.md, "Dragging, edges and monitors")
* **Picking up**: a click under 350 ms opens the card; holding draws a 2 px kisel ring clockwise (350 ms, OutQuad), the ring pops, and from a pill Kisel is drawn out on a jelly neck (16 px down to 3 px, the pill dents 4 px); at 36 px the neck snaps, two droplets fall and the mascot grows from 44 to 120 px. Let go before the snap and it springs back (OutElastic).
* **Carrying**: leans by `clamp(vx / 40, -14, 14)` degrees, stretches up to 8 percent along the velocity, the tilt overshoots when it stops, no drop shadow while held.
* **Edge zones and docking to any side**: a kisel-soft half-round zone (200 x 40) fades in within 96 px of any of the four edges of the monitor and brightens as the edge pulls; within 20 px Kisel leans on the wall (10 percent squash, eyes toward the screen's centre) and a ring pulses; the centre of an edge snaps with a tick; corners keep 120 px clear. Letting go there docks: the pill morphs in (240 ms OutBack) while Kisel arcs into its slot (320 ms InOutCubic) shrinking to 44 px, with a landing ripple and the click sound.
* **Four docks**: top (hanging), bottom (standing on the edge, the card grows upward, the mascot at its bottom left), left and right (44 x 176 pill flush with the edge, mini mascot leaning 8 degrees inward, the state as an icon-only disc, the card grows toward the screen). Edge and position along it are remembered per monitor.
* **Walls and seams**: dragging into a wall with no neighbour presses into it (resistance, up to 18 percent squash at 40 px, springs back); where a monitor has a neighbour Kisel goes on across the seam, drawn on both monitors at once (a transparent input-less layer surface per output it touches, `SeamWindows`), with a contact ripple. Letting go settles it on the monitor that holds its centre, with a 0.25 hop.
* **Drag mechanics**: the surface is made as big as the output while the pointer is down and stays still, so the mascot follows the pointer exactly (see ARCHITECTURE.md).

## Done in the "Windows and Coucou's manners" pass
* **Windows port**: see "Windows" in `ARCHITECTURE.md`. Built with MSVC 2022 and Qt 6.10; the 18 core tests pass, a permission request sent through `kisel-hook.exe` was answered with a real click on the island.
* **The bar, after Coucou's island** (this replaces the 176 to 280 x 44 pill and "hover open" above): Coucou's compact bar exactly, 288 x 32 with 14 px corners, the mini Kisel 24 px and wholly inside it. The card opens on a soft spring (480 ms, a little past its size and back) and closes on a plain ease (340 ms); content follows 120 ms behind. A click opens the card, the pointer alone never does; an open card closes 3 s after the pointer leaves (Settings: at once to 10 s; 600 ms after an answer), and a click on Kisel puts it away. After a minute with nothing to show the bar slides into the edge and leaves a 240 x 6 strip that brings it back at a touch; any activity brings it back too.
* Not taken from Coucou: its 640 px card width and 160 px view heights (Kisel's views are laid out for 660 and are taller), global shortcuts.

## Done in the "Miku" pass
* **The mascot is Miku**: `Mascot.qml` is rewritten on a Canvas with the same interface; the wordmark, the bar's label and the tray icon follow. Interactive prototype with every state and emote: `design/miku-mochi.html`.
* **Hello at every start**: she comes up from the bottom centre of the screen, waves, and flies along the docking arc into the bar (`Island.greet`). Skipped when floating, with reduce motion, or when the card is already open.
* Left as it was: the first-launch assembly still builds the old silhouette before she appears; the leek, the microphone and the petting from the prototype are not in the app.

## Done in the "cast" pass
* **Five singers, one engine** (`Mascot.qml`, `character`): Miku (twin tails), Rin (bow and hair clips), Luka (long hair, gold band), Zundamon (an edamame pod at each ear), Teto (twin drills), each with her own colours, outfit and headset.
* **In character**: they share the moods and differ in pace and bounce (Rin fast and high, Luka slow and low) and in the emotes of their own. Idle habit: Miku hums, Rin hypes herself up, Luka closes her eyes and stands cool, Zundamon stands proud, Teto looks smug while her drills spin. A slap: Miku sulks, Rin blows up, Luka is unimpressed, Zundamon panics, Teto looks away blushing. The pointer resting on her: hearts, except Luka's quiet smile and Teto's fluster. A finished task throws her favourite thing among the sparks: leek, orange, tuna, zunda mochi, baguette.
* **The bench**: the four who are not on stage sit two by two at the bar's far end, as Coucou keeps its other agents; a click swaps one in. Settings has the same choice. Remembered in `kisel.conf` (`character`).
* **Zundamon and Spotify**, the first tie between a character and a service: with her chosen Home *is* the player (`PlayerView`: cover, title, artist, progress, previous / play or pause / next) and dissolves in the moment she is picked; she hums along while it plays. Home belongs to whoever is chosen: Miku's is Claude Code's, and the ones with no service yet show Claude's. Read from Windows' own media session (`Media`), so no sign-in and no key. Settings can turn it off. Reading the track is checked against a running Spotify; the three buttons are wired but were not pressed in testing.
* **The bar as Zundamon's mini player**: with her on stage and Spotify holding a track, the collapsed bar shows the track's name and previous / play or pause / next; the buttons work without opening the card, and the bar does not tuck away while a tune plays.
* **Miku is Claude Code's**: whoever is chosen, Miku steps onto the stage for three seconds when Claude starts on something or finishes, and stays while a request waits for an answer; then the chosen one returns. With Miku chosen nobody changes places. Zundamon with Spotify does not mirror Claude's working: that is Miku's news.
* **Changing places**: the one on stage spins away and shrinks (200 ms), the new one springs up with a ring of sparks in her colour and waves if the card is open; "reduce motion" simply swaps.
* Next: ties for the other four. The tray icon is still Miku whoever is on stage.

## Not applied from the pass
* **Tab indicator**: the design describes a tab row; Kisel's header uses icon buttons, so there is no tab to stretch.
* **"Bump" sound** at the wall, and the optional follow-the-active-window leap to another monitor (there is no such setting yet).
* **Attention tab** is not drawn on the left and right docks (the disc and the card say it instead).
* **Mirrored card on the right edge**: the card grows toward the screen but its content keeps the same left-to-right order.
* **Sound ducking**: sounds are played by `paplay`, one process each, so an older sound cannot be faded when a new one starts.
* **The docking "magnet"** is a ring around the mascot rather than in the pill's slot: the pill is not on screen while the mascot floats.

## Untested (built, needs a real run)
* **Dragging with a real pointer.** The whole flow (hold, neck, snap, zones, docking on all four edges, a free drop) runs through synthetic pointer events (`kisel --drag-test left|right|top|bottom|float`) on both the offscreen platform and the live KWin session, where the compositor really resizes the surface to the output and back. A virtual mouse made with uinput (absolute positions read back from KWin) has been dragged across the eDP-1/DP-1 and eDP-1/HDMI-A-1 seams on the live session, and the island follows to the other monitor; a physical mouse has not been used.
* **(older note)** Dragging the floating mascot with a real pointer. The logic is there (layer-shell margins, 0.6 gain to absorb compositor lag) and the window re-anchors without protocol errors on KWin, but nobody has dragged it yet. Negative margins are used near screen edges.
* **AskUserQuestion**: the answer goes back as `hookSpecificOutput.decision.updatedInput` with an `answers` map. The relay and format are tested; whether a given Claude Code version accepts it is not.
* **GitHub widget** against live GitHub (parsing is tested with a recorded-shape response).
* **Multi-monitor moves** (only one output on the dev machine).

## Next
1. **Eyes follow the pointer everywhere** – impossible on Wayland (no global cursor); only inside the island. Optional KWin script/DBus bridge.
2. **Other agents** – the relay already tags `--agent <name>` (`^[a-z0-9-]{1,24}$`); add per-agent pills on Home and agent-specific hook installers.
3. **Service widgets beyond GitHub**, **Claude plan usage pill**, **drag a window as context** (KWin DBus), **jump to the exact Konsole tab** (`KONSOLE_DBUS_SERVICE` is already forwarded by the relay).
4. **Packaging** – Gentoo ebuild (overlay), `kisel` icon theme entry, autostart `.desktop`.
5. **Translations** – design copy is English; a Russian pass needs Cyrillic subsets of Fredoka/Nunito/JetBrains Mono (the shipped fonts are Latin subsets).
6. **Windows, the rest** – the port is in (see "Windows" in `ARCHITECTURE.md`). Still missing: an installer, start with Windows, an `.ico` for the executable, sounds that overlap.

## Known limitations
* `settings.json` is rewritten by Qt's JSON writer, which sorts object keys alphabetically; the diff shown before writing is exact, but the first connect may reorder the user's keys. Replace with an order-preserving writer.
* `PostToolUse` does not forward `tool_response` (the relay drops it on purpose), so a failed tool is detected only through `PostToolUseFailure`.
* Icons are drawn in code from Breeze-shaped paths, not loaded from the icon theme, so they do not follow a custom Breeze variant.
