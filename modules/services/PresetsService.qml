pragma Singleton

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Public state
    property var presets: []
    property string activePreset: ""

    signal presetsUpdated()

    // Paths
    readonly property string configDir: Quickshell.shellPath("config/")
    readonly property string assetsPresetsDir: Quickshell.shellPath("assets/presets")
    readonly property string activePresetFile: joinPath(configDir, "active_preset")

    // Files that should never be saved, loaded, or displayed as preset files.
    readonly property var excludedFiles: [
        "binds.json",
        "system.json",
        "ai.json",
        "prefix.json",
        "weather.json"
    ]

    // Pending operation state
    property string pendingPresetName: ""
    property string pendingUpdateName: ""
    property string pendingDeleteName: ""
    property string pendingLoadName: ""
    property var pendingRename: null
    property bool _initialized: false

    // -------------------------------------------------------------------------
    // General helpers
    // -------------------------------------------------------------------------

    function joinPath(base: string, child: string): string {
        if (base.endsWith("/")) return base + child
        return base + "/" + child
    }

    function shellQuote(value: string): string {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function notify(title: string, message: string) {
        Quickshell.execDetached(["notify-send", title, message])
    }

    function isExcludedFile(fileName: string): bool {
        return root.excludedFiles.includes(fileName)
    }

    function isValidPresetName(name: string): bool {
        const trimmed = name.trim()

        return trimmed.length > 0
            && trimmed !== "."
            && trimmed !== ".."
            && !trimmed.includes("/")
            && !trimmed.includes("\\")
            && trimmed.indexOf("\u0000") === -1
    }

    function customPresetPath(presetName: string): string {
        return joinPath(configDir, presetName)
    }

    function findPreset(presetName: string): var {
        return presets.find(preset => preset.name === presetName)
    }

    function isOfficialName(presetName: string): bool {
        return presets.some(preset => preset.name === presetName && preset.isOfficial)
    }

    function selectedConfigFiles(configFiles: var): var {
        const files = []

        for (const configFile of configFiles) {
            if (!isExcludedFile(configFile)) files.push(configFile)
        }

        return files
    }

    function copyFilesCommand(srcDir: string, dstDir: string, configFiles: var): string {
        const commands = []

        for (const jsonFile of selectedConfigFiles(configFiles)) {
            commands.push(
                "cp "
                + shellQuote(joinPath(srcDir, jsonFile))
                + " "
                + shellQuote(joinPath(dstDir, jsonFile))
            )
        }

        return commands.join(" && ")
    }

    function writeFileCommand(path: string, content: string): string {
        return "printf %s " + shellQuote(content) + " > " + shellQuote(path)
    }

    function validateEditablePresetName(presetName: string, action: string): bool {
        if (!isValidPresetName(presetName)) {
            console.warn("Invalid preset name for", action + ":", presetName)
            return false
        }

        return true
    }

    function scan() {
        scanProcess.running = true
        readActivePresetProcess.running = true
    }

    // Backwards-compatible alias for existing callers.
    function scanPresets() {
        scan()
    }

    // -------------------------------------------------------------------------
    // Public preset actions
    // -------------------------------------------------------------------------

    function loadPreset(presetName: string) {
        if (!validateEditablePresetName(presetName, "load")) return

        const preset = findPreset(presetName)
        if (!preset) {
            console.warn("Preset not found:", presetName)
            notify("Error", `Preset "${presetName}" was not found.`)
            return
        }

        const copyCommand = copyFilesCommand(preset.path, configDir, preset.configFiles)
        if (copyCommand.length === 0) {
            console.warn("No config files found in preset:", presetName)
            notify("Error", `Preset "${presetName}" has no config files to load.`)
            return
        }

        pendingLoadName = presetName
        loadProcess.command = [
            "sh",
            "-c",
            copyCommand + " && " + writeFileCommand(activePresetFile, presetName)
        ]
        loadProcess.running = true
    }

    function savePreset(presetName: string, configFiles: var) {
        if (!validateEditablePresetName(presetName, "save")) return

        if (isOfficialName(presetName)) {
            console.warn("Cannot create preset with official name:", presetName)
            notify("Error", `Cannot use reserved official preset name "${presetName}".`)
            return
        }

        const files = selectedConfigFiles(configFiles)
        if (files.length === 0) {
            console.warn("No config files selected for preset")
            notify("Error", "No preset files were selected.")
            return
        }

        const presetPath = customPresetPath(presetName)
        const infoJson = JSON.stringify({ author: "User", authorUrl: "" }, null, 4)
        const commands = [
            "mkdir -p " + shellQuote(presetPath),
            copyFilesCommand(configDir, presetPath, files),
            writeFileCommand(joinPath(presetPath, "info.json"), infoJson)
        ].filter(command => command.length > 0)

        pendingPresetName = presetName
        saveProcess.command = ["sh", "-c", commands.join(" && ")]
        saveProcess.running = true
    }

    function updatePreset(presetName: string, configFiles: var) {
        if (!validateEditablePresetName(presetName, "update")) return

        const files = selectedConfigFiles(configFiles)
        if (files.length === 0) {
            console.warn("No config files selected for update")
            notify("Error", "No preset files were selected.")
            return
        }

        const preset = findPreset(presetName)
        if (preset && preset.isOfficial) {
            savePreset(presetName + " (Custom)", files)
            return
        }

        const presetPath = customPresetPath(presetName)
        const copyCommand = copyFilesCommand(configDir, presetPath, files)

        pendingUpdateName = presetName
        updateProcess.command = ["sh", "-c", copyCommand]
        updateProcess.running = true
    }

    function renamePreset(oldName: string, newName: string) {
        if (!validateEditablePresetName(oldName, "rename")) return
        if (!validateEditablePresetName(newName, "rename")) return

        if (oldName === newName) {
            console.warn("Preset rename ignored because the names match")
            return
        }

        const preset = findPreset(oldName)
        if (preset && preset.isOfficial) {
            console.warn("Cannot rename official preset:", oldName)
            notify("Error", "Official presets cannot be renamed.")
            return
        }

        if (isOfficialName(newName)) {
            console.warn("Cannot rename to official preset name:", newName)
            notify("Error", `Cannot rename to reserved official preset name "${newName}".`)
            return
        }

        pendingRename = { oldName: oldName, newName: newName }
        renameProcess.command = ["mv", customPresetPath(oldName), customPresetPath(newName)]
        renameProcess.running = true
    }

    function deletePreset(presetName: string) {
        if (!validateEditablePresetName(presetName, "delete")) return

        const preset = findPreset(presetName)
        if (preset && preset.isOfficial) {
            console.warn("Cannot delete official preset:", presetName)
            notify("Error", "Official presets cannot be deleted.")
            return
        }

        pendingDeleteName = presetName
        deleteProcess.command = ["rm", "-rf", customPresetPath(presetName)]
        deleteProcess.running = true
    }

    function initialize() {
        if (_initialized) return

        _initialized = true
        console.log("PresetsService initialized. configDir:", configDir)
        initProcess.running = true
    }

    // -------------------------------------------------------------------------
    // Processes
    // -------------------------------------------------------------------------

    Process {
        id: initProcess
        command: ["mkdir", "-p", configDir]
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.scan()
            } else {
                console.warn("Failed to create preset config directory:", configDir)
            }
        }
    }

    Process {
        id: scanProcess
        running: false
        command: [
            "sh",
            "-c",
            [
                "find " + shellQuote(configDir) + " " + shellQuote(assetsPresetsDir)
                    + " -mindepth 2 -maxdepth 2 -name '*.json'"
                    + " -not -name 'info.json'"
                    + " -not -name 'system.json'"
                    + " -not -name 'ai.json'"
                    + " -not -name 'prefix.json'"
                    + " -not -name 'weather.json'",
                "printf '%s\\n' '---METADATA---'",
                "find " + shellQuote(configDir) + " " + shellQuote(assetsPresetsDir)
                    + " -mindepth 2 -maxdepth 2 -name 'info.json' -exec grep -H . {} +"
            ].join("; ")
        ]

        stdout: StdioCollector {
            onStreamFinished: root.parseScanOutput(text)
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.warn("Preset scan exited with code:", exitCode)
            }
        }
    }

    function parseScanOutput(text: string) {
        const lines = text.trim().length > 0 ? text.trim().split("\n") : []
        const presetsByPath = {}
        const metadataByPath = {}
        let readingMetadata = false

        for (const line of lines) {
            if (line === "---METADATA---") {
                readingMetadata = true
                continue
            }

            if (!readingMetadata) {
                parsePresetFileLine(line, presetsByPath)
            } else {
                parseMetadataLine(line, metadataByPath)
            }
        }

        applyMetadata(presetsByPath, metadataByPath)

        const newPresets = Object.values(presetsByPath)
        newPresets.sort(comparePresets)

        root.presets = newPresets
        root.presetsUpdated()
    }

    function parsePresetFileLine(line: string, presetsByPath: var) {
        if (line.length === 0) return

        const parts = line.split("/")
        const configName = parts.pop()
        const presetPath = parts.join("/")
        const presetName = parts[parts.length - 1]
        const isOfficial = line.startsWith(root.assetsPresetsDir)

        if (!presetsByPath[presetPath]) {
            presetsByPath[presetPath] = {
                name: presetName,
                path: presetPath,
                isOfficial: isOfficial,
                configFiles: [],
                author: "Unknown",
                authorUrl: ""
            }
        }

        presetsByPath[presetPath].configFiles.push(configName)
    }

    function parseMetadataLine(line: string, metadataByPath: var) {
        const splitAt = line.indexOf(":")
        if (splitAt === -1) return

        const filePath = line.substring(0, splitAt)
        const content = line.substring(splitAt + 1)
        const parts = filePath.split("/")
        parts.pop()

        const presetPath = parts.join("/")
        metadataByPath[presetPath] = (metadataByPath[presetPath] || "") + content + "\n"
    }

    function applyMetadata(presetsByPath: var, metadataByPath: var) {
        for (const presetPath in metadataByPath) {
            if (!presetsByPath[presetPath]) continue

            try {
                const info = JSON.parse(metadataByPath[presetPath])
                presetsByPath[presetPath].author = info.author || "Unknown"
                presetsByPath[presetPath].authorUrl = info.authorUrl || ""
            } catch (error) {
                console.warn("Failed to parse metadata for preset:", presetPath, error)
            }
        }
    }

    function comparePresets(a: var, b: var): int {
        if (a.isOfficial && !b.isOfficial) return -1
        if (!a.isOfficial && b.isOfficial) return 1
        return a.name.localeCompare(b.name)
    }

    Process {
        id: saveProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                console.log("Preset saved successfully:", root.pendingPresetName)
                notify("Preset Saved", `Preset "${root.pendingPresetName}" saved successfully.`)
                root.scan()
            } else {
                console.warn("Failed to save preset:", root.pendingPresetName)
                notify("Error", `Failed to save preset "${root.pendingPresetName}".`)
            }

            root.pendingPresetName = ""
        }
    }

    Process {
        id: updateProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                console.log("Preset updated successfully:", root.pendingUpdateName)
                notify("Preset Updated", `Preset "${root.pendingUpdateName}" updated successfully.`)
                root.scan()
            } else {
                console.warn("Failed to update preset:", root.pendingUpdateName)
                notify("Error", `Failed to update preset "${root.pendingUpdateName}".`)
            }

            root.pendingUpdateName = ""
        }
    }

    Process {
        id: loadProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                console.log("Preset loaded successfully:", root.pendingLoadName)
                root.activePreset = root.pendingLoadName
                notify("Preset Loaded", `Preset "${root.pendingLoadName}" loaded successfully.`)
            } else {
                console.warn("Failed to load preset:", root.pendingLoadName)
                notify("Error", `Failed to load preset "${root.pendingLoadName}".`)
            }

            root.pendingLoadName = ""
        }
    }

    Process {
        id: renameProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0 && root.pendingRename) {
                console.log(
                    "Preset renamed successfully:",
                    root.pendingRename.oldName,
                    "->",
                    root.pendingRename.newName
                )
                notify("Preset Renamed", `Preset renamed to "${root.pendingRename.newName}".`)

                if (root.activePreset === root.pendingRename.oldName) {
                    root.activePreset = root.pendingRename.newName
                    writeActivePresetProcess.command = [
                        "sh",
                        "-c",
                        writeFileCommand(activePresetFile, root.pendingRename.newName)
                    ]
                    writeActivePresetProcess.running = true
                }

                root.scan()
            } else {
                console.warn("Failed to rename preset")
                notify("Error", "Failed to rename preset.")
            }

            root.pendingRename = null
        }
    }

    Process {
        id: deleteProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                console.log("Preset deleted successfully:", root.pendingDeleteName)
                notify("Preset Deleted", `Preset "${root.pendingDeleteName}" deleted.`)

                if (root.activePreset === root.pendingDeleteName) {
                    root.activePreset = ""
                    writeActivePresetProcess.command = ["rm", "-f", activePresetFile]
                    writeActivePresetProcess.running = true
                }

                root.scan()
            } else {
                console.warn("Failed to delete preset:", root.pendingDeleteName)
                notify("Error", `Failed to delete preset "${root.pendingDeleteName}".`)
            }

            root.pendingDeleteName = ""
        }
    }

    Process {
        id: writeActivePresetProcess
        running: false
    }

    Process {
        id: readActivePresetProcess
        command: ["cat", activePresetFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.activePreset = text.trim()
        }
    }

    // -------------------------------------------------------------------------
    // Watchers
    // -------------------------------------------------------------------------

    FileView {
        path: configDir
        watchChanges: true
        printErrors: false

        onFileChanged: scanDebounce.restart()
    }

    Instantiator {
        model: root.presets

        delegate: FileView {
            required property var modelData

            path: modelData.path
            watchChanges: true
            printErrors: false

            onFileChanged: scanDebounce.restart()
        }
    }

    Timer {
        id: scanDebounce
        interval: 150
        repeat: false
        onTriggered: root.scan()
    }
}
