pragma Singleton
// Mirrors the design system's tokens.json (dark + light). Add new colours to
// the design system first, then here.
import QtQuick
import Kisel.Core

QtObject {
    id: t

    readonly property bool dark: Prefs.theme === "dark" || (Prefs.theme !== "light" && Qt.styleHints.colorScheme !== Qt.ColorScheme.Light)
    function pick(d, l) { return dark ? d : l }

    // surfaces and lines
    readonly property color surface0: pick("#0e0b0d", "#fbf6f1")
    readonly property color surface1: pick("#171214", "#f4ece5")
    readonly property color surface2: pick("#211a1d", "#ffffff")
    readonly property color surface3: pick("#2d2428", "#efe3da")
    readonly property color line:     pick("#4a3d42", "#d9c9bf")

    // text
    readonly property color ink:      pick("#f7efe9", "#2b1d21")
    readonly property color inkMuted: pick("#b8a8a2", "#6b5a5f")
    readonly property color inkFaint: pick("#9a8a85", "#6b5a5f")

    // brand
    readonly property color kisel:     pick("#ff7a93", "#c42a52")
    readonly property color kiselDeep: pick("#d93f66", "#a81f44")
    readonly property color kiselSoft: "#ffd0c4"
    readonly property color onKisel:   pick("#2a0f18", "#ffffff")

    // status: always travels with an icon or a word
    readonly property color mint:   pick("#7fe3b0", "#0e7a4a")
    readonly property color amber:  pick("#ffc060", "#8a5a00")
    readonly property color danger: pick("#ff8a80", "#b3261e")
    readonly property color info:   pick("#7cc0ff", "#0b62b5")

    readonly property color diffAddBg: pick("#12301f", "#dff5e8")
    readonly property color diffDelBg: pick("#3a1519", "#fbe0dd")

    // The mascot is drawn from fixed colours in every theme (same as the logo).
    readonly property color mascotEye: "#2a0f18"
    readonly property color mascotTop: "#ffd0c4"
    readonly property color mascotMid: "#ff7a93"
    readonly property color mascotBottom: "#d93f66"
    readonly property color mascotLeaf: "#7fe3b0"
    readonly property color mascotLeaf2: "#6cd09c"
    // status colours on the always-dark mascot badge
    readonly property color badgeInfo: "#7cc0ff"
    readonly property color badgeAmber: "#ffc060"
    readonly property color badgeMint: "#7fe3b0"
    readonly property color badgeDanger: "#ff8a80"

    // spacing and radii
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space6: 24
    readonly property int radiusSm: 8
    readonly property int radiusMd: 14
    readonly property int radiusLg: 24
    readonly property int radiusPill: 999

    // type
    readonly property string display: fredoka.status === FontLoader.Ready ? "Fredoka" : "Nunito"
    readonly property string sans: "Nunito"
    readonly property string mono: "JetBrains Mono"

    // motion (ms), from motion.md
    readonly property bool reduced: Prefs.reduceMotion
    readonly property int tInstant: 70
    readonly property int tPress: 80
    readonly property int tHover: 100
    readonly property int tFast: 140
    readonly property int tBase: reduced ? 140 : 280
    readonly property int tSettle: 520

    readonly property FontLoader fredoka6: FontLoader { source: "resources/fonts/fredoka-latin-600-normal.ttf" }
    readonly property FontLoader fredoka: FontLoader { source: "resources/fonts/fredoka-latin-700-normal.ttf" }
    readonly property FontLoader nunito4: FontLoader { source: "resources/fonts/nunito-latin-400-normal.ttf" }
    readonly property FontLoader nunito6: FontLoader { source: "resources/fonts/nunito-latin-600-normal.ttf" }
    readonly property FontLoader nunito8: FontLoader { source: "resources/fonts/nunito-latin-800-normal.ttf" }
    readonly property FontLoader jbMono: FontLoader { source: "resources/fonts/jetbrains-mono-latin-400-normal.ttf" }
}
