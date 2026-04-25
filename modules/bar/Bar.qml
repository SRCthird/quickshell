import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.config

PanelWindow {
    id: panel

    property alias barPosition: barContent.barPosition
    property alias orientation: barContent.orientation
    property alias pinned: barContent.pinned
    property alias hoverActive: barContent.hoverActive
    readonly property alias isMouseOverBar: barContent.isMouseOverBar
    readonly property alias reveal: barContent.reveal

    anchors {
        top: barPosition !== "bottom"
        bottom: barPosition !== "top"
        left: barPosition !== "right"
        right: barPosition !== "left"
    }

    color: "transparent"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.layer: WlrLayer.Overlay

    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    implicitHeight: orientation === "horizontal" ? 200 : Screen.height

    mask: Region {
        item: barContent.barHitbox
    }

    Component.onCompleted: {
        Visibilities.registerBar(screen.name, barContent);
        Visibilities.registerBarPanel(screen.name, panel);
    }

    Component.onDestruction: {
        Visibilities.unregisterBar(screen.name);
        Visibilities.unregisterBarPanel(screen.name);
    }

    BarContent {
        id: barContent
        anchors.fill: parent
        screen: panel.screen
    }
}
