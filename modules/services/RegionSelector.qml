pragma Singleton

import QtQuick

import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    property bool active: false
    property string purpose: ""

    property string _pendingPurpose: ""
    property string _pendingGeometry: ""

    signal selected(string purpose, string geometry)
    signal cancelled(string purpose)

    function select(purpose) {
        if (active)
            return;

        root.purpose = purpose;
        root.active = true;
    }

    function cancel() {
        if (!active)
            return;

        var currentPurpose = root.purpose;

        root.active = false;
        root.purpose = "";

        root.cancelled(currentPurpose);
    }

    function complete(screen, x, y, width, height) {
        if (!active)
            return;

        var globalX = Math.round(screen.x + x);
        var globalY = Math.round(screen.y + y);

        var w = Math.round(width);
        var h = Math.round(height);

        if (w < 2 || h < 2) {
            cancel();
            return;
        }

        _pendingPurpose = purpose;
        _pendingGeometry =
            globalX + "," + globalY + " " + w + "x" + h;

        root.active = false;
        root.purpose = "";

        finishTimer.restart();
    }

    Timer {
        id: finishTimer

        interval: 75
        repeat: false

        onTriggered: {
            var pendingPurpose = root._pendingPurpose;
            var pendingGeometry = root._pendingGeometry;

            root._pendingPurpose = "";
            root._pendingGeometry = "";

            root.selected(
                pendingPurpose,
                pendingGeometry
            );
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: selectorWindow

            property var modelData

            property real startX: 0
            property real startY: 0
            property real currentX: 0
            property real currentY: 0
            property bool selecting: false

            screen: modelData

            visible: root.active

            color: "transparent"

            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-region-selector"

            Rectangle {
                anchors.fill: parent

                color: "#30000000"

                MouseArea {
                    id: mouseArea

                    anchors.fill: parent

                    hoverEnabled: true
                    cursorShape: Qt.CrossCursor

                    acceptedButtons:
                        Qt.LeftButton | Qt.RightButton

                    onPressed: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            root.cancel();
                            return;
                        }

                        selectorWindow.startX = mouse.x;
                        selectorWindow.startY = mouse.y;
                        selectorWindow.currentX = mouse.x;
                        selectorWindow.currentY = mouse.y;
                        selectorWindow.selecting = true;
                    }

                    onPositionChanged: mouse => {
                        if (!selectorWindow.selecting)
                            return;

                        selectorWindow.currentX = mouse.x;
                        selectorWindow.currentY = mouse.y;
                    }

                    onReleased: mouse => {
                        if (mouse.button !== Qt.LeftButton)
                            return;

                        if (!selectorWindow.selecting)
                            return;

                        selectorWindow.currentX = mouse.x;
                        selectorWindow.currentY = mouse.y;
                        selectorWindow.selecting = false;

                        var x = Math.min(
                            selectorWindow.startX,
                            selectorWindow.currentX
                        );

                        var y = Math.min(
                            selectorWindow.startY,
                            selectorWindow.currentY
                        );

                        var width = Math.abs(
                            selectorWindow.currentX
                            - selectorWindow.startX
                        );

                        var height = Math.abs(
                            selectorWindow.currentY
                            - selectorWindow.startY
                        );

                        root.complete(
                            selectorWindow.screen,
                            x,
                            y,
                            width,
                            height
                        );
                    }
                }

                Rectangle {
                    id: selectionRect

                    visible: selectorWindow.selecting

                    x: Math.min(
                        selectorWindow.startX,
                        selectorWindow.currentX
                    )

                    y: Math.min(
                        selectorWindow.startY,
                        selectorWindow.currentY
                    )

                    width: Math.abs(
                        selectorWindow.currentX
                        - selectorWindow.startX
                    )

                    height: Math.abs(
                        selectorWindow.currentY
                        - selectorWindow.startY
                    )

                    color: "transparent"

                    border.width: 2
                    border.color: "white"
                }
            }
        }
    }
}
