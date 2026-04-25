import Quickshell.Io

JsonAdapter {
    property bool enabled: false
    property string theme: "default"
    property string position: "bottom"
    property int height: 56
    property int iconSize: 40
    property int spacing: 4
    property int margin: 8
    property int hoverRegionHeight: 4
    property bool pinnedOnStartup: false
    property bool hoverToReveal: true
    property bool availableOnFullscreen: false
    property bool showRunningIndicators: true
    property bool showPinButton: true
    property bool showOverviewButton: true
    property list<string> ignoredAppRegexes: ["quickshell.*", "xdg-desktop-portal.*"]
    property list<string> screenList: []
    property bool keepHidden: false
}
