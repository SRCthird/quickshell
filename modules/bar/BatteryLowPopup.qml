import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.config
import qs.modules.globals

PopupWindow {
    id: root

    required property var panel

    color: "transparent"
    visible: GlobalStates.batteryLowVisible
         && panel.barEnabled
         && panel.targetScreen.name === Quickshell.screens[0].name
    grabFocus: false

    width: 260
    height: 84

    anchor.window: panel

    anchor.rect.x: {
        switch (panel.barPosition) {
        case "left":
            return panel.barTargetWidth + panel.barOuterMargin + 12;
        case "right":
            return panel.width - width - panel.barTargetWidth - panel.barOuterMargin - 12;
        default:
            return Math.round((panel.width - width) / 2);
        }
    }

    anchor.rect.y: {
        switch (panel.barPosition) {
        case "top":
            return panel.barTargetHeight + panel.barOuterMargin + 12;
        case "bottom":
            return panel.height - height - panel.barTargetHeight - panel.barOuterMargin - 12;
        default:
            return Math.round((panel.height - height) / 2);
        }
    }

    property int lowThreshold: 10
    property int resetThreshold: 15
    property bool lowStateLatched: false


    readonly property real normalizedBattery: Math.max(0, Math.min(1, Battery.percentage / 100))

    readonly property string titleText: Battery.isPluggedIn ? "Charging" : "Battery low"

    readonly property string detailText: {
        const pct = Math.round(Battery.percentage) + "%";

        if (!Battery.available)
            return "Battery unavailable";

        if (Battery.isPluggedIn && Battery.timeToFull !== "")
            return pct + " • full in " + Battery.timeToFull;

        if (!Battery.isPluggedIn && Battery.timeToEmpty !== "")
            return pct + " • " + Battery.timeToEmpty + " remaining";

        return pct + " remaining";
    }

    function batteryIsLow() {
        return Battery.available
            && !Battery.isPluggedIn
            && Battery.percentage <= lowThreshold;
    }

    function batteryRecovered() {
        return !Battery.available
            || Battery.isPluggedIn
            || Battery.percentage >= resetThreshold;
    }

    function syncVisibility() {
        if (batteryIsLow() && !lowStateLatched) {
            lowStateLatched = true;
            GlobalStates.batteryLowVisible = true;
            lowBatterySound.play()
            return;
        }

        if (batteryRecovered() && lowStateLatched) {
            lowStateLatched = false;
            GlobalStates.batteryLowVisible = false;
        }
    }

    Component.onCompleted: syncVisibility()

    Connections {
        target: Battery
        function onPercentageChanged() { root.syncVisibility(); }
        function onIsPluggedInChanged() { root.syncVisibility(); }
        function onAvailableChanged() { root.syncVisibility(); }
        function onChargeStateChanged() { root.syncVisibility(); }
    }

    SoundEffect {
        id: lowBatterySound 
        source: Quickshell.shellDir + "/assets/sound/polite-warning-tone.wav"
    }

    StyledRect {
        anchors.fill: parent
        variant: "bg"

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                GlobalStates.batteryLowVisible = false;
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                id: mainBody
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 12
                color: Styling.srItem("overprimary")
                opacity: 0.12

                Text {
                    anchors.centerIn: parent
                    text: Battery.getBatteryIcon()
                    color: Styling.srItem("overprimary")
                    font.pixelSize: 21
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.titleText
                    color: Styling.srItem("text")
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: root.detailText
                    color: Styling.srItem("subtext")
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
                    radius: 999
                    color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    Rectangle {
                        width: parent.width * root.normalizedBattery
                        height: parent.height
                        radius: parent.radius
                        color: Styling.srItem("overprimary")

                        Behavior on width {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }
}
