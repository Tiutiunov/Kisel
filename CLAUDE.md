# Kisel: guide for coding agents

Desktop companion for KDE Plasma (Qt 6 / QML / C++20). Read `docs/ARCHITECTURE.md` first.

## Source of truth
The **Kisel design system** (claude.ai artifact 4796a68c-b55b-4b5d-877a-bd69e22bfc10: `README.md`, `tokens.json`, `motion.md`) decides look and motion. Colours go into the design system first, then `qml/Theme.qml`. `motion.md` tags each behaviour Built or Spec; `docs/ROADMAP.md` tracks which Spec parts are built here.

## Build and test
```
cmake -S . -B build && cmake --build build -j && ctest --test-dir build --output-on-failure
```
UI check without touching the screen: `QT_QPA_PLATFORM=offscreen KISEL_LAYER_SHELL=0 ./build/kisel --grab out.png --open <view>` (add `XDG_CONFIG_HOME`/`XDG_DATA_HOME` pointing at a scratch dir so the real config is untouched).

## Rules
- Never block Claude Code: `kisel-hook` has hard deadlines and prints nothing when in doubt.
- Never approve a permission without an explicit click. "Always" rules are per pattern (`AgentHub::ruleKey`) and clearable.
- Never overwrite `~/.claude/settings.json` blindly: preview diff, dated backup, atomic write (`HookInstaller`).
- Secrets only in KWallet. No telemetry. Model output is plain text.
- Platform-specific code stays in `IslandWindow`, `Tray`, `Secrets`, `Paths`. QML never knows the platform.
- `socketPath()` exists twice (`Paths.h`, `hook/main.cpp`): change both.
- Copy is English, sentence case, one verb per button, no emoji.
