# Kisel

A desktop companion for KDE Plasma. A small raspberry-jelly creature lives in a dark island at the top of your screen, watches Claude Code, asks permission on its behalf and chats with Claude. Look, tokens and motion follow the Kisel design system; see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/ROADMAP.md](docs/ROADMAP.md).

Qt 6 · QML · C++20 · Wayland layer-shell · KWallet.

## Build (Gentoo, Plasma 6)

Needs `dev-qt/qtbase`, `qtdeclarative`, `qtsvg`, `qtwayland`, `kde-plasma/layer-shell-qt`, `kde-frameworks/kwallet`, `kde-frameworks/kstatusnotifieritem`, `cmake`.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
ctest --test-dir build --output-on-failure
```

```bash
./build/kisel
```

First launch plays the cover-assembly intro and opens the island for a few seconds. Drag the mascot out of the island to let it roam the desktop; drag it back to the top edge to dock it. Settings has a monitor picker, a GitHub token field (Home → GitHub) and the hook installer. Open **Settings → Connect Claude Code** to see the exact diff of what will change in `~/.claude/settings.json`; nothing is written until you click, and a dated backup is taken first.

## Develop without Claude Code

```bash
./build/kisel --demo                      # replays a fake session and a permission request
./build/kisel --demo --open permission    # open a view directly
KISEL_DEBUG=1 ./build/kisel               # print every hook event it receives
KISEL_DEMO_ASK=1 ./build/kisel --demo     # demo with a question card instead of a command
KISEL_LAYER_SHELL=0 ./build/kisel         # plain window instead of layer-shell
QT_QPA_PLATFORM=offscreen ./build/kisel --grab out.png --open home   # render one frame to a PNG
```

Regenerate the sounds with `python3 scripts/gen_sounds.py`.

## Where things are

| Path | What |
| --- | --- |
| `src/core` | Hub, hook socket, installer, chat, secrets, preferences (no UI dependency, unit-tested) |
| `src/app` | Window (layer-shell), tray, `main.cpp` |
| `hook/main.cpp` | `kisel-hook`, the relay Claude Code runs on every event |
| `qml/` | Theme (tokens), Mascot, Island, views |
| `resources/` | Fonts (Latin subsets), logo, generated sounds |
| `tests/` | Core tests, including the socket protocol |

Files: config `~/.config/kisel/kisel.conf`, relay copy `~/.local/share/kisel/bin/kisel-hook`, socket `$XDG_RUNTIME_DIR/kisel.sock`.

## Rules

Never block Claude Code. Never approve without an explicit click. Never overwrite `settings.json` blindly. Keys only in KWallet. No telemetry.
