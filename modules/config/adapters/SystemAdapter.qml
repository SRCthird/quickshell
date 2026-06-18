import Quickshell.Io

JsonAdapter {
    property list<string> disks: ["/"]
    property bool updateServiceEnabled: true
    property JsonObject idle: JsonObject {
        property JsonObject general: JsonObject {
            property string lock_cmd: "qs ipc call lockscreen lock"
            property string before_sleep_cmd: "loginctl lock-session"
            property string after_sleep_cmd: "hyprctl dispatch dpms on"
        }
        property list<var> listeners: [
            {
                "timeout": 150,
                "onTimeout": 'qs ipc call brightness set .15 ""',
                "onResume": 'qs ipc call brightness revert ""'
            },
            {
                "timeout": 300,
                "onTimeout": "loginctl lock-session"
            },
            {
                "timeout": 330,
                "onTimeout": "hyprctl dispatch dpms off",
                "onResume": "hyprctl dispatch dpms on"
            },
            {
                "timeout": 1800,
                "onTimeout": "loginctl suspend"
            }
        ]
    }
    property JsonObject ocr: JsonObject {
        property bool eng: true
        property bool spa: true
        property bool lat: false
        property bool jpn: false
        property bool chi_sim: false
        property bool chi_tra: false
        property bool kor: false
    }
    property JsonObject pomodoro: JsonObject {
        property int workTime: 1500
        property int restTime: 300
        property bool autoStart: false
        property bool syncSpotify: false
    }

    property JsonObject motionCues: JsonObject {
      property bool enabledByDefault: false
      // Leave empty for fake test motion.
      // My laptop doesn't have IIO :( 
      // But this can be any command that prints JSON lines:
      // {"x":0.1,"y":-0.2}
      property string sourceCommand: ""
      property int dotRadius: 4
      property int spacing: 54
      property int edgeInset: 28
      property int maxShift: 34
      property real opacity: 0.55
      property real smoothing: 0.18
    }
}
