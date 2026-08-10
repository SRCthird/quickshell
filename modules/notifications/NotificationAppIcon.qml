import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.modules.theme
import qs.modules.config

Item {
    id: root
    property var appIcon: ""
    property string appName: ""
    property string desktopEntry: ""
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    property var image: ""
    property real scale: 1
    property real size: 48 * scale
    property real appIconScale: scale
    property real smallAppIconScale: 0.4
    property real appIconSize: size * appIconScale
    property real smallAppIconSize: size * smallAppIconScale
    property bool usingAppIconFallback: false

    implicitWidth: size
    implicitHeight: size
    property real radius: Styling.radius(-8)

    function resolveIconSource(icon) {
        if (!icon)
            return "";

        const value = String(icon);

        if (value.startsWith("file://")
                || value.startsWith("data:")
                || value.startsWith("http://")
                || value.startsWith("https://")) {
            return value;
        }

        if (value.startsWith("/"))
            return "file://" + value;

        return Quickshell.iconPath(value, "image-missing");
    }

    function resolveDesktopEntryIcon() {
        let entry = null;
        let id = root.desktopEntry || "";

        if (id.endsWith(".desktop"))
            id = id.slice(0, -8);

        if (id)
            entry = DesktopEntries.byId(id);

        if (!entry && root.appName)
            entry = DesktopEntries.heuristicLookup(root.appName);

        if (entry && entry.icon)
            return Quickshell.iconPath(entry.icon, "image-missing");

        return Quickshell.iconPath("image-missing");
    }

    function appIconSource() {
        if (root.appIcon)
            return resolveIconSource(root.appIcon);

        return resolveDesktopEntryIcon();
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: root.urgency == NotificationUrgency.Critical ? Colors.shadow : Colors.surfaceBright
            border.width: root.urgency == NotificationUrgency.Critical ? 2 : 0
            border.color: root.urgency == NotificationUrgency.Critical ? Colors.criticalRed : "transparent"
            radius: root.radius
            visible: (root.image == "" && root.appIcon == "") || (appIconLoader.active && appIconLoader.item && appIconLoader.item.status === Image.Error)

            Text {
                anchors.centerIn: parent
                text: {
                    if (root.urgency == NotificationUrgency.Critical) return Icons.alert;
                    if (root.appName === "Pomodoro") return Icons.timer;
                    return Icons.bell;
                }
                font.family: Icons.font
                font.pixelSize: root.size * 0.5
                color: root.urgency == NotificationUrgency.Critical ? Colors.criticalText : Styling.srItem("overprimary")

                SequentialAnimation on opacity {
                    running: root.urgency == NotificationUrgency.Critical
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 1.0
                        to: 0.5
                        duration: 800
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: 0.5
                        to: 1.0
                        duration: 800
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        Loader {
            id: appIconLoader
            active: root.image == "" && (root.appIcon != "" || root.desktopEntry != "" || root.appName != "")
            anchors.fill: parent
            visible: item && item.status !== Image.Error
            sourceComponent: Image {
                mipmap: true
                id: appIconImage
                property bool triedDesktopFallback: false
                anchors.fill: parent
                source: root.appIconSource()
                fillMode: Image.PreserveAspectCrop
                smooth: true

                onStatusChanged: {
                    if (status === Image.Error && !triedDesktopFallback) {
                        triedDesktopFallback = true;
                        source = root.resolveDesktopEntryIcon();
                    }
                }
            }
        }

        Loader {
            id: notifImageLoader
            active: root.image != ""
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: root.radius
                    color: "transparent"

                    Image {
                        mipmap: true
                        id: notifImage
                        property bool triedAppIconFallback: false
                        property bool triedDesktopFallback: false

                        anchors.fill: parent
                        source: root.image
                        fillMode: Image.PreserveAspectCrop
                        smooth: true

                        onStatusChanged: {
                            if (status !== Image.Error)
                                return;

                            if (!triedAppIconFallback && root.appIcon) {
                                triedAppIconFallback = true;
                                root.usingAppIconFallback = true;
                                source = root.resolveIconSource(root.appIcon);
                                return;
                            }

                            if (!triedDesktopFallback) {
                                triedDesktopFallback = true;
                                root.usingAppIconFallback = true;
                                source = root.resolveDesktopEntryIcon();
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: notifImageAppIconLoader
        active: root.image != "" && (root.appIcon != "" || root.desktopEntry != "" || root.appName != "") && !root.usingAppIconFallback
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.smallAppIconSize
        height: root.smallAppIconSize
        sourceComponent: Rectangle {
            color: "transparent"

            Image {
                mipmap: true
                property bool triedDesktopFallback: false
                anchors.fill: parent
                source: root.appIconSource()
                fillMode: Image.PreserveAspectCrop
                smooth: true

                onStatusChanged: {
                    if (status === Image.Error && !triedDesktopFallback) {
                        triedDesktopFallback = true;
                        source = root.resolveDesktopEntryIcon();
                    }
                }
            }
        }
    }
}
