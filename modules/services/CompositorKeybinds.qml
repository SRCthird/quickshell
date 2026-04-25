import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.modules.config
import qs.modules.globals

QtObject {
    id: root

    property Process compositorProcess: Process {}

    property var previousUnbinds: []
    property bool hasPreviousBinds: false

    property var shellBindKeys: [
        "launcher",
        "dashboard",
        "assistant",
        "clipboard",
        "emoji",
        "notes",
        "tmux",
        "wallpapers"
    ]

    property var systemBindKeys: [
        "overview",
        "powermenu",
        "config",
        "lockscreen",
        "tools",
        "screenshot",
        "screenrecord",
        "lens",
        "reload",
        "quit"
    ]

    property Timer applyTimer: Timer {
        interval: 100
        repeat: false
        onTriggered: applyKeybindsInternal()
    }

    function applyKeybinds() {
        applyTimer.restart();
    }

    function configReady() {
        return Config.keybindsReady && Config.keybinds && Config.keybinds.shell;
    }

    function cloneArray(value) {
        return value ? value.slice() : [];
    }

    function makeUnbindTarget(bind) {
        if (!bind)
            return null;

        return {
            modifiers: cloneArray(bind.modifiers),
            key: bind.key || ""
        };
    }

    function makeBindFromCore(bind) {
        if (!bind)
            return null;

        return {
            modifiers: cloneArray(bind.modifiers),
            key: bind.key || "",
            dispatcher: bind.dispatcher || "",
            argument: bind.argument || "",
            flags: bind.flags || "",
            enabled: bind.enabled !== false
        };
    }

    function makeBindFromKeyAction(keyObj, action) {
        if (!keyObj || !action)
            return null;

        return {
            modifiers: cloneArray(keyObj.modifiers),
            key: keyObj.key || "",
            dispatcher: action.dispatcher || "",
            argument: action.argument || "",
            flags: action.flags || "",
            enabled: true
        };
    }

    function pushValid(list, item) {
        if (item && item.key)
            list.push(item);
    }

    function actionMatchesLayout(action) {
        if (!action.layouts || action.layouts.length === 0)
            return true;

        return action.layouts.indexOf(GlobalStates.compositorLayout) !== -1;
    }

    function addCoreSection(payload, section, keys) {
        if (!section)
            return;

        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            const bind = section[key];

            if (!bind)
                continue;

            pushValid(payload.unbinds, makeUnbindTarget(bind));
            pushValid(payload.binds, makeBindFromCore(bind));
        }
    }

    function addCustomBinds(payload, customBinds) {
        if (!customBinds || customBinds.length === 0)
            return;

        for (let i = 0; i < customBinds.length; i++) {
            const bind = customBinds[i];

            if (!bind || !bind.keys || !bind.actions)
                continue;

            for (let k = 0; k < bind.keys.length; k++)
                pushValid(payload.unbinds, makeUnbindTarget(bind.keys[k]));

            if (bind.enabled === false)
                continue;

            for (let k = 0; k < bind.keys.length; k++) {
                for (let a = 0; a < bind.actions.length; a++) {
                    const action = bind.actions[a];

                    if (actionMatchesLayout(action))
                        pushValid(payload.binds, makeBindFromKeyAction(bind.keys[k], action));
                }
            }
        }
    }

    function buildPayload() {
        const keybinds = Config.keybinds;
        const shell = keybinds.shell;
        const system = shell.system;
        const custom = keybinds.custom;

        let payload = {
            binds: [],
            unbinds: []
        };

        if (hasPreviousBinds) {
            for (let i = 0; i < previousUnbinds.length; i++)
                pushValid(payload.unbinds, previousUnbinds[i]);
        }

        addCoreSection(payload, shell, shellBindKeys);
        addCoreSection(payload, system, systemBindKeys);
        addCustomBinds(payload, custom);

        return payload;
    }

    function rememberCurrentBinds(payload) {
        previousUnbinds = [];

        for (let i = 0; i < payload.binds.length; i++)
            pushValid(previousUnbinds, makeUnbindTarget(payload.binds[i]));

        hasPreviousBinds = true;
    }

    function joinModifiers(modifiers) {
        return modifiers && modifiers.length > 0 ? modifiers.join(" ") : "";
    }

    function buildHyprUnbindCommand(unbind) {
        if (!unbind || !unbind.key)
            return null;

        const mods = joinModifiers(unbind.modifiers);
        return "keyword unbind " + mods + ", " + unbind.key;
    }

    function buildHyprBindCommand(bind) {
        if (!bind || bind.enabled === false || !bind.key || !bind.dispatcher)
            return null;

        const mods = joinModifiers(bind.modifiers);
        const keyword = "bind" + (bind.flags || "");

        if (bind.argument !== undefined && bind.argument !== null && bind.argument !== "") {
            return "keyword " + keyword + " "
                + mods + ", "
                + bind.key + ", "
                + bind.dispatcher + ", "
                + bind.argument;
        }

        return "keyword " + keyword + " "
            + mods + ", "
            + bind.key + ", "
            + bind.dispatcher;
    }

    function buildBatchCommands(payload) {
        let commands = [];

        for (let i = 0; i < payload.unbinds.length; i++) {
            const command = buildHyprUnbindCommand(payload.unbinds[i]);
            if (command)
                commands.push(command);
        }

        for (let i = 0; i < payload.binds.length; i++) {
            const command = buildHyprBindCommand(payload.binds[i]);
            if (command)
                commands.push(command);
        }

        return commands;
    }

    function applyKeybindsInternal() {
        if (!configReady()) {
            console.log("CompositorKeybinds: Waiting for keybind config...");
            return;
        }

        if (!GlobalStates.compositorLayoutReady) {
            console.log("CompositorKeybinds: Waiting for compositor layout...");
            return;
        }

        const payload = buildPayload();
        const batchCommands = buildBatchCommands(payload);

        rememberCurrentBinds(payload);

        if (batchCommands.length === 0) {
            console.log("CompositorKeybinds: There are no commands to apply.");
            return;
        }

        console.log(
            "CompositorKeybinds: Sending hyprctl --batch (" +
            payload.unbinds.length + " unbinds, " +
            payload.binds.length + " binds, layout: " +
            GlobalStates.compositorLayout + ")"
        );

        compositorProcess.command = [
            "hyprctl",
            "--batch",
            batchCommands.join(" ; ")
        ];

        compositorProcess.running = true;
    }

    property Connections configConnections: Connections {
        target: Config

        function onKeybindsUpdated() {
            applyKeybinds();
        }

        function onKeybindsReadyChanged() {
            if (Config.keybindsReady)
                applyKeybinds();
        }
    }

    property Connections globalStatesConnections: Connections {
        target: GlobalStates

        function onCompositorLayoutChanged() {
            console.log("CompositorKeybinds: Layout changed to " + GlobalStates.compositorLayout + ", reapplying keybinds...");
            applyKeybinds();
        }

        function onCompositorLayoutReadyChanged() {
            if (GlobalStates.compositorLayoutReady)
                applyKeybinds();
        }
    }

    property Connections compositorConnections: Connections {
        target: HyprctlService

        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                console.log("CompositorKeybinds: configreloaded detected, reapplying keybinds...");
                applyKeybinds();
            }
        }
    }

    Component.onCompleted: {
        if (configReady())
            applyKeybinds();
    }
}
