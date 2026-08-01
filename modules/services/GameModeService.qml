pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool toggled: false
    property bool initialized: false

    property string stateFile: Quickshell.statePath("states.json")

    readonly property string gameModeConfig: [
        "hl.config({",
        "animations = {",
        "enabled = false,",
        "},",
        "decoration = {",
        "shadow = {",
        "enabled = false,",
        "},",
        "blur = {",
        "enabled = false,",
        "},",
        "rounding = 0,",
        "},",
        "general = {",
        "gaps_in = 0,",
        "gaps_out = 0,",
        "border_size = 1,",
        "},",
        "})"
    ].join(" ")

    property Process enableProcess: Process {
        running: false
        stdout: SplitParser {}

        onExited: (code) => {
            if (code === 0) {
                root.toggled = true
                root.saveState()
            } else {
                console.warn(
                    "GameModeService: Failed to enable game mode:",
                    code
                )
            }
        }
    }

    property Process disableProcess: Process {
        running: false
        stdout: SplitParser {}

        onExited: (code) => {
            if (code === 0) {
                root.toggled = false
                root.saveState()
            } else {
                console.warn(
                    "GameModeService: Failed to disable game mode:",
                    code
                )
            }
        }
    }

    property Process writeStateProcess: Process {
        running: false
        stdout: SplitParser {}
    }

    property Process readCurrentStateProcess: Process {
        running: false

        stdout: SplitParser {
            onRead: (data) => {
                try {
                    const content = data ? data.trim() : ""
                    let states = {}

                    if (content) {
                        states = JSON.parse(content)
                    }

                    states.gameMode = root.toggled

                    writeStateProcess.command = [
                        "sh",
                        "-c",
                        `printf '%s' '${JSON.stringify(states)}' > "${root.stateFile}"`
                    ]
                    writeStateProcess.running = true
                } catch (e) {
                    console.warn(
                        "GameModeService: Failed to update state:",
                        e
                    )
                }
            }
        }

        onExited: (code) => {
            if (code !== 0) {
                const states = {
                    gameMode: root.toggled
                }

                writeStateProcess.command = [
                    "sh",
                    "-c",
                    `printf '%s' '${JSON.stringify(states)}' > "${root.stateFile}"`
                ]
                writeStateProcess.running = true
            }
        }
    }

    property Process readStateProcess: Process {
        running: false

        stdout: SplitParser {
            onRead: (data) => {
                try {
                    const content = data ? data.trim() : ""

                    if (content) {
                        const states = JSON.parse(content)

                        if (states.gameMode !== undefined) {
                            root.toggled = states.gameMode

                            if (root.toggled) {
                                root.enableGameMode()
                            }
                        }
                    }
                } catch (e) {
                    console.warn(
                        "GameModeService: Failed to parse states:",
                        e
                    )
                }

                root.initialized = true
            }
        }

        onExited: (code) => {
            if (code !== 0) {
                root.initialized = true
            }
        }
    }

    function enableGameMode() {
        enableProcess.command = [
            "hyprctl",
            "eval",
            gameModeConfig
        ]
        enableProcess.running = true
    }

    function disableGameMode() {
        disableProcess.command = [
            "hyprctl",
            "reload"
        ]
        disableProcess.running = true
    }

    function toggle() {
        if (enableProcess.running || disableProcess.running) {
            return
        }

        if (toggled) {
            disableGameMode()
        } else {
            enableGameMode()
        }
    }

    function saveState() {
        readCurrentStateProcess.command = [
            "cat",
            stateFile
        ]
        readCurrentStateProcess.running = true
    }

    function loadState() {
        readStateProcess.command = [
            "cat",
            stateFile
        ]
        readStateProcess.running = true
    }

    Timer {
        interval: 100
        running: true
        repeat: false

        onTriggered: {
            if (!root.initialized) {
                root.loadState()
            }
        }
    }
}
