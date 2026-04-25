import Quickshell.Io

JsonAdapter {
    property string position: "top"
    property string launcherIcon: ""
    property bool launcherIconTint: true
    property bool launcherIconFullTint: true
    property int launcherIconSize: 24
    property string pillStyle: "default"
    property list<string> screenList: []
    property bool enableFirefoxPlayer: false
    property list<var> barColor: [["surface", 0.0]]
    property bool frameEnabled: false
    property int frameThickness: 6
    // Auto-hide settings
    property bool pinnedOnStartup: true
    property bool hoverToReveal: true
    property int hoverRegionHeight: 8
    property bool showPinButton: true
    property bool availableOnFullscreen: false
    property bool use12hFormat: false
    property bool containBar: false
    property bool keepBarShadow: false
    property bool keepBarBorder: false
}
