pragma Singleton

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.config

Singleton {
    id: root

    // General Idle Settings
    property string lockCmd:
        Config.system.idle.general.lock_cmd
        ?? "qs ipc call lockscreen lock"

    property string beforeSleepCmd:
        Config.system.idle.general.before_sleep_cmd
        ?? "loginctl lock-session"

    property string afterSleepCmd:
        Config.system.idle.general.after_sleep_cmd
        ?? "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\""

    property bool awaitingPrepareForSleepValue: false

    property var loginLockProc: Process {
        id: loginLockProc

        running: true

        command: [
            "dbus-monitor",
            "--system",
            "type='signal',interface='org.freedesktop.login1.Session',member='Lock'"
        ]

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();

                if (line.indexOf(
                    "interface=org.freedesktop.login1.Session; member=Lock"
                ) !== -1) {
                    console.log("Received login1 Lock signal");

                    root.executeCommand(root.lockCmd);
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                const line = data.trim();

                if (line.length > 0)
                    console.warn("login1 lock monitor:", line);
            }
        }

        onExited: (exitCode, exitStatus) => {
            console.warn(
                "login1 lock monitor exited with code "
                + exitCode
                + ". Restarting..."
            );

            loginLockRestartTimer.start();
        }
    }

    property var loginLockRestartTimer: Timer {
        id: loginLockRestartTimer

        interval: 1000
        repeat: false

        onTriggered: {
            if (!loginLockProc.running)
                loginLockProc.running = true;
        }
    }

    property var sleepMonitorProc: Process {
        id: sleepMonitorProc

        running: true

        command: [
            "dbus-monitor",
            "--system",
            "type='signal',path='/org/freedesktop/login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
        ]

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();

                if (line.indexOf(
                    "interface=org.freedesktop.login1.Manager; member=PrepareForSleep"
                ) !== -1) {
                    root.awaitingPrepareForSleepValue = true;
                    return;
                }

                if (!root.awaitingPrepareForSleepValue)
                    return;

                if (line === "boolean true") {
                    root.awaitingPrepareForSleepValue = false;

                    console.log("System preparing for sleep");
                    SuspendManager.onPrepareForSleep();

                    return;
                }

                if (line === "boolean false") {
                    root.awaitingPrepareForSleepValue = false;

                    console.log("System resumed from sleep");
                    SuspendManager.onWakingUp();
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                const line = data.trim();

                if (line.length > 0)
                    console.warn("login1 sleep monitor:", line);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.awaitingPrepareForSleepValue = false;

            console.warn(
                "login1 sleep monitor exited with code "
                + exitCode
                + ". Restarting..."
            );

            sleepMonitorRestartTimer.start();
        }
    }

    property var sleepMonitorRestartTimer: Timer {
        id: sleepMonitorRestartTimer

        interval: 1000
        repeat: false

        onTriggered: {
            if (!sleepMonitorProc.running)
                sleepMonitorProc.running = true;
        }
    }

    property int elapsedIdleTime: 0

    property var triggeredListeners: []

    property var masterMonitor: IdleMonitor {
        id: masterMonitor

        timeout: 1
        respectInhibitors: true

        onIsIdleChanged: {
            if (isIdle) {
                idleTimer.start();
            } else {
                idleTimer.stop();
                root.resetIdleState();
            }
        }
    }

    property var idleTimer: Timer {
        id: idleTimer

        interval: 1000
        repeat: true

        onTriggered: {
            root.elapsedIdleTime += 1;
            root.checkListeners();
        }
    }

    function executeCommand(cmd) {
        if (!cmd || cmd.trim().length === 0)
            return;

        Quickshell.execDetached([
            "sh",
            "-c",
            cmd
        ]);
    }

    function checkListeners() {
        const listeners = Config.system.idle.listeners;

        for (let i = 0; i < listeners.length; i++) {
            const listener = listeners[i];
            const tVal = listener.timeout || 60;

            if (
                root.elapsedIdleTime >= tVal
                && !root.triggeredListeners.includes(i)
            ) {
                if (listener.onTimeout) {
                    console.log(
                        "Idle timer "
                        + tVal
                        + "s reached: "
                        + listener.onTimeout
                    );

                    root.executeCommand(listener.onTimeout);
                }

                root.triggeredListeners.push(i);
            }
        }
    }

    function resetIdleState() {
        const listeners = Config.system.idle.listeners;

        for (
            let i = root.triggeredListeners.length - 1;
            i >= 0;
            i--
        ) {
            const idx = root.triggeredListeners[i];
            const listener = listeners[idx];

            if (listener && listener.onResume) {
                console.log(
                    "Idle resuming (undoing "
                    + (listener.timeout || 0)
                    + "s): "
                    + listener.onResume
                );

                root.executeCommand(listener.onResume);
            }
        }

        root.elapsedIdleTime = 0;
        root.triggeredListeners = [];
    }
}
