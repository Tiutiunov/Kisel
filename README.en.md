# Kisel

[Русская версия](README.md)

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

First launch plays the cover-assembly intro and opens the island for a few seconds. Hold the mascot for a moment (a ring fills) to pick it up: pull it out of the pill to let it roam the desktop, or carry it to any edge of any monitor and let go there to dock it. Settings has a monitor picker, a GitHub token field (Home → GitHub) and the hook installer. Open **Settings → Connect Claude Code** to see the exact diff of what will change in `~/.claude/settings.json`; nothing is written until you click, and a dated backup is taken first.

## Build (Windows 10/11)

Needs Visual Studio 2022 (or its Build Tools) with "Desktop development with C++", CMake, Ninja and Qt 6.5+ for MSVC (`qtbase`, `qtdeclarative`, `qtsvg`). From an "x64 Native Tools" prompt:

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:\Qt\6.10.3\msvc2022_64
cmake --build build
cmake --install build --prefix dist
```

```powershell
dist\bin\kisel.exe
```

`dist\bin` is self-contained (Qt libraries, plugins and QML imports next to `kisel.exe`). To run or test straight from `build`, put Qt's `bin` on `PATH` first. There is no taskbar button and no console: the island and the tray icon are the whole app.

### Installer and updates (Windows)

The Windows releases are the ones tagged `win-v<version>` on GitHub; each carries `KiselSetup-<version>.exe`. It installs for the current user only (no administrator rights; by default into `%LOCALAPPDATA%\Programs\Kisel`), adds a Start menu shortcut and an entry under "Installed apps", and starts Kisel. `KiselSetup.exe /SILENT /DIR=<folder>` asks nothing.

**Settings → Updates → Check for updates** asks GitHub for a newer release; **Update and restart** downloads its installer, checks it against the size and SHA-256 GitHub gives, and runs it. Kisel never asks by itself. The releases are those of `Tiutiunov/Kisel`.

To make a release: bump `VERSION` in `CMakeLists.txt`, then

```powershell
cmake --build build --target installer
gh release create win-v<version> build\KiselSetup-<version>.exe --target windows --title "Kisel <version> for Windows"
```

The installer is the small program in `packaging/windows/setup.cpp` with the installed tree appended to it as a zip; it unpacks with the `tar.exe` Windows 10 (1803 and later) ships with. It is not code-signed, so SmartScreen warns the first time it is run by hand.

What differs from Plasma: the island is a topmost frameless window; hooks go through the named pipe `\\.\pipe\kisel-<your SID>` and `%LOCALAPPDATA%\kisel\bin\kisel-hook.exe`; keys live in the Windows Credential Manager; sounds play one at a time. Files: `%LOCALAPPDATA%\kisel\kisel.conf`.

## Develop without Claude Code

```bash
./build/kisel --demo                      # replays a fake session and a permission request
./build/kisel --demo --open permission    # open a view directly
./build/kisel --intro                     # play the first-launch animation
./build/kisel --dock-edge left:0.3        # start docked on an edge (top, bottom, left, right) at 30 % along it
./build/kisel --drag-test bottom          # synthetic pointer: hold, carry to the edge, let go (prints the state)
./build/kisel --grab-test                 # check the full-output drag surface works on your compositor
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
