// Line icons on a 24 px grid, 1.6 px stroke, round caps and joins.
// Drawn in code so they take any token colour. When the app runs under the
// Breeze icon theme, each name maps to a Breeze one: check=dialog-ok,
// cross=dialog-cancel, bell=notifications, gear=configure, chat=dialog-messages,
// send=mail-send, sound=audio-volume-high, mute=audio-volume-muted,
// back=go-previous, clip=mail-attachment, terminal=utilities-terminal, folder=folder, refresh=view-refresh.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string name: "check"
    property color color: "white"
    property int size: 20

    width: size
    height: size

    readonly property var paths: ({
        check: "M5 12.5l4.5 4.5L19 7.5",
        cross: "M6 6l12 12M18 6L6 18",
        bell: "M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0",
        gear: "M12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6zM12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1",
        chat: "M5 6h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-7l-4 3.5V16H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1z",
        send: "M20 4L4 11l6 2.5L12.5 20zM20 4l-10 9.5",
        sound: "M4 10v4h3.5L12 18V6L7.5 10zM15.5 9a4 4 0 0 1 0 6M18 6.5a8 8 0 0 1 0 11",
        mute: "M4 10v4h3.5L12 18V6L7.5 10zM16 9.5l5 5M21 9.5l-5 5",
        back: "M14 6l-6 6 6 6",
        clip: "M17 11l-6 6a3.5 3.5 0 0 1-5-5l7-7a2.3 2.3 0 0 1 3.3 3.3l-7 7a1.2 1.2 0 0 1-1.7-1.7l6-6",
        terminal: "M4 6h16v12H4zM7 10l3 2-3 2M12 15h5",
        plus: "M12 5v14M5 12h14",
        folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
        refresh: "M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5",
        up: "M6 14l6-6 6 6"
    })

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true // renders into its own texture, clipped to the 24 px box
        layer.smooth: true
        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.paths[root.name] || "" }
        }
    }
}
