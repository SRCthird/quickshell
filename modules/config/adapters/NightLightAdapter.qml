import Quickshell.Io

JsonAdapter {
    property string mode: "always" // "always" or "location"
    property string command: "wlsunset"
    property string processName: "wlsunset"
    property real latitude: 0.0
    property real longitude: 0.0
    property int nightTemperature: 4000
    property int dayTemperature: 6500
    property int highTemperatureOffset: 1
    property string forcedSunsetTime: "00:00"
    property string forcedSunriseTime: "23:59"
    property int transitionDuration: 0
    property bool usePkillFallback: true
    property bool checkOnStartup: true
    property bool debugLogs: true
}
