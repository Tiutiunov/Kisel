# Roadmap

Status of every behaviour in the design system (`README.md`, `motion.md`, `components/`). **Done** = in this repo; **Untested** = built but not exercised against the real thing; **Next** = specified or planned, not built.

## Done

**Shell and views**
* Island: collapsed black pill (status dot + word) ⇄ Home / Session / Permission / Chat / GitHub / Settings at the spec sizes, 280 ms OutCubic, hover open, 600 ms close timer, hold-open rules, peek on task done, three-layer soft shadow, 140 ms view cross-fade, one mascot gliding between slots.
* Floating mascot: drag > 36 px out of the island to float, drag around the desktop (jelly-trailing), within 20 px of the top edge to dock, click to open the card in place (it slides to stay on screen), close icon, position remembered, wandering every 18-48 s with the `walk` mood.
* Monitor picker: a mini-map of your outputs in Settings, remembered by output name, falls back to the primary and returns when the monitor is plugged back in; arrives with a hop.

**Mascot**: idle, think, work, alert, wow, happy, sad, sleep, dizzy, walk; blink, breathing, leaf, spring eyes, click squash, jump, badge, sparkles, "z", dizzy orbit with brand shapes, GitHub skin (graphite, white sparkles), wake-up blink, reduce-motion switches.

**Components** (from `components/`): buttons (primary / secondary / ghost / danger, 3 px focus ring, 40 % disabled), status pills (dot + word), launch tiles 104×84 (Claude, Terminal → Konsole, GitHub, Files → Dolphin), chat bubbles (squared corner, inline code, timestamp), permission card (command, diff, question), island states.

**Brand-shape motion** (`motion.md`, "Brand shapes in motion"): first-launch cover assembly and the full first-launch timeline, task-done ring + confetti burst, amber attention tab (with extra-request dots), jelly-trio loader, dot wave (listening) and 6×3 drop-hint grid, success move (pill → disc → check draws itself → "Connected"/"Saved"), quiet-screen drift, night sky while asleep, toasts, step check that draws itself, diff-line stagger, amber "modified" dot, reduced-motion fallbacks.

**Integrations**: Claude Code hooks (install/remove with diff + backup), permissions, **AskUserQuestion answered from the island** (up to four questions, single or multi-select), chat with Claude, **GitHub widget** (open PRs with CI state, reviews waiting, read-only token in KWallet, 5-minute refresh), sounds through PipeWire.

**Quality**: 18 unit tests (hub, rule keys, hook merge, diff, SSE, GitHub parsing, question answer line, socket round trip), relay verified against a fake server.

## Untested (built, needs a real run)
* **Dragging the floating mascot** with a real pointer. The logic is there (layer-shell margins, 0.6 gain to absorb compositor lag) and the window re-anchors without protocol errors on KWin, but nobody has dragged it yet. Negative margins are used near screen edges.
* **AskUserQuestion**: the answer goes back as `hookSpecificOutput.decision.updatedInput` with an `answers` map. The relay and format are tested; whether a given Claude Code version accepts it is not.
* **GitHub widget** against live GitHub (parsing is tested with a recorded-shape response).
* **Multi-monitor moves** (only one output on the dev machine).

## Next
1. **Eyes follow the pointer everywhere** – impossible on Wayland (no global cursor); only inside the island. Optional KWin script/DBus bridge.
2. **Other agents** – the relay already tags `--agent <name>` (`^[a-z0-9-]{1,24}$`); add per-agent pills on Home and agent-specific hook installers.
3. **Service widgets beyond GitHub**, **Claude plan usage pill**, **drag a window as context** (KWin DBus), **jump to the exact Konsole tab** (`KONSOLE_DBUS_SERVICE` is already forwarded by the relay).
4. **Packaging** – Gentoo ebuild (overlay), `kisel` icon theme entry, autostart `.desktop`.
5. **Translations** – design copy is English; a Russian pass needs Cyrillic subsets of Fredoka/Nunito/JetBrains Mono (the shipped fonts are Latin subsets).
6. **Windows** – see "Porting" in `ARCHITECTURE.md`.

## Known limitations
* `settings.json` is rewritten by Qt's JSON writer, which sorts object keys alphabetically; the diff shown before writing is exact, but the first connect may reorder the user's keys. Replace with an order-preserving writer.
* `PostToolUse` does not forward `tool_response` (the relay drops it on purpose), so a failed tool is detected only through `PostToolUseFailure`.
* Icons are drawn in code from Breeze-shaped paths, not loaded from the icon theme, so they do not follow a custom Breeze variant.
