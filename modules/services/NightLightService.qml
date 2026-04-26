pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.config

Singleton {
    id: root

    property bool active: StateService.get("nightLight", false)
    property bool processRunning: false

    readonly property QtObject cfg: Config.nightLight

    readonly property string mode: cfg ? cfg.mode : "always"
    readonly property string commandName: cfg ? cfg.command : "wlsunset"
    readonly property string processName: cfg ? cfg.processName : "wlsunset"

    readonly property real latitude: cfg ? cfg.latitude : 0.0
    readonly property real longitude: cfg ? cfg.longitude : 0.0

    readonly property int nightTemperature: Math.max(1000, cfg ? cfg.nightTemperature : 4000)
    readonly property int dayTemperature: Math.max(nightTemperature + 1, cfg ? cfg.dayTemperature : 6500)
    readonly property int highTemperatureOffset: Math.max(1, cfg ? cfg.highTemperatureOffset : 1)
    readonly property int forcedDayTemperature: nightTemperature + highTemperatureOffset

    readonly property string forcedSunsetTime: cfg ? cfg.forcedSunsetTime : "00:00"
    readonly property string forcedSunriseTime: cfg ? cfg.forcedSunriseTime : "23:59"
    readonly property int transitionDuration: Math.max(0, cfg ? cfg.transitionDuration : 0)

    readonly property bool usePkillFallback: cfg ? cfg.usePkillFallback : true
    readonly property bool checkOnStartup: cfg ? cfg.checkOnStartup : true
    readonly property bool debugLogs: cfg ? cfg.debugLogs : true

    function log(...args) {
        if (debugLogs) {
            console.log("NightLightService:", ...args)
        }
    }

    function warn(...args) {
        console.warn("NightLightService:", ...args)
    }

    function normalizedMode() {
        if (mode === "location" || mode === "always") {
            return mode
        }

        warn("invalid mode:", mode, "falling back to always")
        return "always"
    }

    function buildAlwaysCommand() {
        return [
            commandName,

            // Force a Night Light temperature regardless of time.
            // wlsunset requires high temp > low temp.
            "-T", forcedDayTemperature.toString(),
            "-t", nightTemperature.toString(),

            // Make almost the entire day count as night.
            "-s", forcedSunsetTime,
            "-S", forcedSunriseTime,

            "-d", transitionDuration.toString()
        ]
    }

    function buildLocationCommand() {
        return [
            commandName,

            // Location-based sunrise/sunset mode.
            "-l", latitude.toString(),
            "-L", longitude.toString(),

            "-T", dayTemperature.toString(),
            "-t", nightTemperature.toString(),

            "-d", transitionDuration.toString()
        ]
    }

    function buildCommand() {
        if (normalizedMode() === "location") {
            return buildLocationCommand()
        }

        return buildAlwaysCommand()
    }

    property Process wlsunsetProcess: Process {
        running: false
        command: root.buildCommand()

        stdout: SplitParser {
            onRead: data => {
                if (data) {
                    root.log("wlsunset stdout:", data)
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data) {
                    root.warn("wlsunset stderr:", data)
                }
            }
        }

        onStarted: {
            root.log("wlsunset started")
            root.processRunning = true
        }

        onExited: (code, status) => {
            root.log("wlsunset exited:", code, status)
            root.processRunning = false
        }
    }

    property Process killProcess: Process {
        running: false
        command: ["pkill", "-x", root.processName]

        stdout: SplitParser {
            onRead: data => {
                if (data) {
                    root.log("pkill stdout:", data)
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data) {
                    root.warn("pkill stderr:", data)
                }
            }
        }

        onExited: (code, status) => {
            root.log("pkill exited:", code, status)
            root.processRunning = false
        }
    }

    property Process checkRunningProcess: Process {
        running: false
        command: ["pgrep", "-x", root.processName]

        onExited: code => {
            const isRunning = code === 0
            root.processRunning = isRunning

            if (root.active && !isRunning) {
                root.start()
            } else if (!root.active && isRunning) {
                root.stop()
            }
        }
    }

    function start() {
        if (wlsunsetProcess.running) {
            processRunning = true
            return
        }

        wlsunsetProcess.command = buildCommand()
        log("starting", normalizedMode(), "mode:", wlsunsetProcess.command.join(" "))
        wlsunsetProcess.running = true
    }

    function stop() {
        if (wlsunsetProcess.running) {
            log("stopping owned wlsunset process")
            wlsunsetProcess.signal(15)
            return
        }

        if (usePkillFallback) {
            log("stopping fallback process:", processName)
            killProcess.command = ["pkill", "-x", processName]
            killProcess.running = true
        } else {
            processRunning = false
        }
    }

    function toggle() {
        active = !active
    }

    function syncState() {
        checkRunningProcess.command = ["pgrep", "-x", processName]
        checkRunningProcess.running = true
    }

    function restart() {
        if (!active) {
            return
        }

        stop()
        restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 250
        repeat: false
        onTriggered: root.start()
    }

    onActiveChanged: {
        if (StateService.initialized) {
            StateService.set("nightLight", active)
        }

        if (active) {
            start()
        } else {
            stop()
        }
    }

    Connections {
        target: root.cfg

        function onModeChanged() { root.restart() }

        function onCommandChanged() { root.restart() }
        function onProcessNameChanged() { root.syncState() }

        function onLatitudeChanged() { root.restart() }
        function onLongitudeChanged() { root.restart() }

        function onNightTemperatureChanged() { root.restart() }
        function onDayTemperatureChanged() { root.restart() }
        function onHighTemperatureOffsetChanged() { root.restart() }

        function onForcedSunsetTimeChanged() { root.restart() }
        function onForcedSunriseTimeChanged() { root.restart() }

        function onTransitionDurationChanged() { root.restart() }
    }

    Connections {
        target: StateService

        function onStateLoaded() {
            root.active = StateService.get("nightLight", false)

            if (root.checkOnStartup) {
                root.syncState()
            }
        }
    }

    Component.onCompleted: {
        if (StateService.initialized) {
            root.active = StateService.get("nightLight", false)

            if (root.checkOnStartup) {
                root.syncState()
            }
        }
    }
}
