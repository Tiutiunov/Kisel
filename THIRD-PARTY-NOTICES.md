# Third-party notices

Kisel's own code is under the MIT licence (see `LICENSE`). This file lists what Kisel depicts, is built on, and ships with that belongs to somebody else.

## Characters

Kisel is a non-commercial fan work. It is not affiliated with, sponsored by or endorsed by any of the rights holders below. The characters are drawn by Kisel's own code in a simplified style of its own; nobody's artwork, voice or music is included.

| Character | Rights holder | Terms Kisel relies on |
| --- | --- | --- |
| Hatsune Miku, Kagamine Rin, Megurine Luka | © Crypton Future Media, INC. www.piapro.net | [Piapro Character License](https://piapro.jp/license/pcl/summary) (non-commercial derivative works) |
| Kasane Teto | © TWINDRILL (character design: Sen; voice: Mayo Oyamano) | [Character usage terms](https://kasaneteto.jp/guidelines/character.html) (individual, non-commercial use needs no permission) |
| Zundamon | © SSS LLC. (Tohoku Zunko / Zundamon project) | [Character usage guidelines](https://zunko.jp/guideline.html) (non-commercial use by creators) |

Notice required by the Piapro Character License:

> この作品はピアプロ・キャラクター・ライセンスに基づいてクリプトン・フューチャー・メディア株式会社のキャラクター「初音ミク」「鏡音リン」「巡音ルカ」を描いたものです。
>
> This work depicts the characters "Hatsune Miku", "Kagamine Rin" and "Megurine Luka" of Crypton Future Media, INC. under the Piapro Character License.

These terms allow free, non-commercial fan works only. Anything commercial (a paid version, advertising, donations tied to the characters) needs the rights holders' separate permission first.

## Claude and Anthropic

Kisel is an unofficial third-party project. It is not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic, PBC.

## Qt

Kisel uses the Qt framework, version 6, © The Qt Company Ltd and other contributors, under the **GNU Lesser General Public License version 3** (`licenses/LGPL-3.0.txt`, which supplements the GNU General Public License version 3 in `licenses/GPL-3.0.txt`).

- Qt is linked dynamically: the Windows package carries Qt's own unmodified libraries (`Qt6*.dll`, the plugins and the QML imports) next to `kisel.exe`, and they can be replaced with another build of the same Qt version.
- Modules used: Qt Core, Gui, Network, Widgets, Test, Qml, Quick, Quick Controls 2, Quick Shapes, Svg. All of them are available under the LGPL v3.
- Qt's source code: <https://download.qt.io/official_releases/qt/> and <https://code.qt.io/>. Qt's own third-party components and their licences: <https://doc.qt.io/qt-6/licenses-used-in-qt.html>.

## Shipped with the Windows package

| Component | Files | Owner and licence |
| --- | --- | --- |
| Microsoft Visual C++ runtime | `msvcp140*.dll`, `vcruntime140*.dll`, `concrt140.dll` | © Microsoft Corporation. Redistributed under the Visual Studio redistributable terms |
| Direct3D shader compilers | `d3dcompiler_47.dll`, `dxcompiler.dll`, `dxil.dll` | © Microsoft Corporation. Redistributable; the DirectX Shader Compiler is under the University of Illinois/NCSA licence |
| ICU | `icuuc.dll` | © Unicode, Inc. and others. Unicode licence |

## Fonts

Bundled as Latin subsets in `resources/fonts`, all under the **SIL Open Font License 1.1** (<https://openfontlicense.org>):

- **Fredoka** © The Fredoka Project Authors
- **Nunito** © The Nunito Project Authors
- **JetBrains Mono** © The JetBrains Mono Project Authors

## Other

- **Sounds** (`resources/sounds`): synthesised by Kisel's own script `scripts/gen_sounds.py`. Nothing sampled; they are part of Kisel.
- **The mascots' shape** follows the "Mochi" mascot of Coucou as an idea only; no code or artwork of it is used.
- On KDE Plasma the Linux build links to LayerShellQt and the KDE Frameworks KWallet and KStatusNotifierItem (LGPL), which come from the system and are not shipped.
