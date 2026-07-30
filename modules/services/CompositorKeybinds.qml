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
            argument: bind.argument === undefined || bind.argument === null
                ? ""
                : bind.argument,
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
            argument: action.argument === undefined || action.argument === null
                ? ""
                : action.argument,
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

    function luaString(value) {
        const source = value === undefined || value === null
            ? ""
            : String(value);

        const escaped = source
            .replace(/\\/g, "\\\\")
            .replace(/\"/g, "\\\"")
            .replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r")
            .replace(/\t/g, "\\t");

        return "\"" + escaped + "\"";
    }

    function buildKeySpec(bind) {
        if (!bind || !bind.key)
            return "";

        const modifiers = cloneArray(bind.modifiers);
        modifiers.push(String(bind.key));
        return modifiers.join(" + ");
    }

    function parseResizeArgument(argument) {
        const source = String(argument).trim();

        if (!source)
            return null;

        const parts = source.split(/\s+/);

        if (parts.length !== 2)
            return null;

        const x = Number(parts[0]);
        const y = Number(parts[1]);

        if (!isFinite(x) || !isFinite(y))
            return null;

        return {
            x: x,
            y: y
        };
    }

    function buildDispatcher(bind) {
        const dispatcher = bind.dispatcher || "";
        const argument = bind.argument === undefined || bind.argument === null
            ? ""
            : String(bind.argument);
        const flags = bind.flags || "";

        switch (dispatcher) {
        case "exec":
            return "hl.dsp.exec_cmd(" + luaString(argument) + ")";

        case "killactive":
            return "hl.dsp.window.close()";

        case "workspace":
            return "hl.dsp.focus({ workspace = " + luaString(argument) + " })";

        case "movetoworkspace":
            return "hl.dsp.window.move({ workspace = " + luaString(argument) + " })";

        case "movetoworkspacesilent":
            return "hl.dsp.window.move({ workspace = " + luaString(argument) + ", follow = false })";

        case "movefocus":
            return "hl.dsp.focus({ direction = " + luaString(argument) + " })";

        case "movewindow":
            if (flags.indexOf("m") !== -1)
                return "hl.dsp.window.drag()";

            return "hl.dsp.window.move({ direction = " + luaString(argument) + " })";

        case "resizewindow":
            if (flags.indexOf("m") !== -1)
                return "hl.dsp.window.resize()";

            console.error(
                "CompositorKeybinds: resizewindow is only supported as a mouse bind."
            );
            return null;

        case "resizeactive": {
            const resize = parseResizeArgument(argument);

            if (!resize) {
                console.error(
                    "CompositorKeybinds: Invalid resizeactive argument '" +
                    argument + "'. Expected two numbers."
                );
                return null;
            }

            return "hl.dsp.window.resize({ x = " + resize.x +
                ", y = " + resize.y + ", relative = true })";
        }

        case "layoutmsg":
            return "hl.dsp.layout(" + luaString(argument) + ")";

        case "togglespecialworkspace":
            return "hl.dsp.workspace.toggle_special(" + luaString(argument) + ")";

        case "togglefloating":
            return "hl.dsp.window.float({ action = \"toggle\" })";

        case "pseudo":
            return "hl.dsp.window.pseudo({ action = \"toggle\" })";

        case "fullscreen": {
            const mode = argument === "1" ? "maximized" : "fullscreen";
            return "hl.dsp.window.fullscreen({ mode = " + luaString(mode) +
                ", action = \"toggle\" })";
        }

        case "pin":
            return "hl.dsp.window.pin()";

        case "centerwindow":
            return "hl.dsp.window.center()";

        case "togglegroup":
            return "hl.dsp.group.toggle()";

        case "submap":
            return "hl.dsp.submap(" + luaString(argument) + ")";

        case "dpms":
            return "hl.dsp.dpms({ action = " + luaString(argument) + " })";

        case "global":
            return "hl.dsp.global(" + luaString(argument) + ")";

        case "forcerendererreload":
            return "hl.dsp.force_renderer_reload()";

        case "exit":
            return "hl.dsp.exit()";

        default:
            console.error(
                "CompositorKeybinds: Unsupported Lua dispatcher '" +
                dispatcher + "'."
            );
            return null;
        }
    }

    function buildFlags(flags) {
        const source = flags || "";
        let values = [];

        for (let i = 0; i < source.length; i++) {
            const flag = source[i];

            switch (flag) {
            case "l":
                values.push("locked = true");
                break;
            case "r":
                values.push("release = true");
                break;
            case "c":
                values.push("click = true");
                break;
            case "g":
                values.push("drag = true");
                break;
            case "o":
                values.push("long_press = true");
                break;
            case "e":
                values.push("repeating = true");
                break;
            case "n":
                values.push("non_consuming = true");
                break;
            case "m":
                values.push("mouse = true");
                break;
            case "t":
                values.push("transparent = true");
                break;
            case "i":
                values.push("ignore_mods = true");
                break;
            case "p":
                values.push("dont_inhibit = true");
                break;
            case "u":
                values.push("submap_universal = true");
                break;
            default:
                console.error(
                    "CompositorKeybinds: Unsupported Lua bind flag '" +
                    flag + "' in flags '" + source + "'."
                );
                return null;
            }
        }

        return values.length > 0 ? "{ " + values.join(", ") + " }" : "";
    }

    function buildLuaUnbind(unbind) {
        const keySpec = buildKeySpec(unbind);

        if (!keySpec)
            return null;

        return "hl.unbind(" + luaString(keySpec) + ")";
    }

    function buildLuaBind(bind) {
        if (!bind || bind.enabled === false || !bind.key || !bind.dispatcher)
            return null;

        const keySpec = buildKeySpec(bind);
        const dispatcher = buildDispatcher(bind);
        const flags = buildFlags(bind.flags);

        if (!keySpec || !dispatcher || flags === null)
            return null;

        if (flags)
            return "hl.bind(" + luaString(keySpec) + ", " + dispatcher + ", " + flags + ")";

        return "hl.bind(" + luaString(keySpec) + ", " + dispatcher + ")";
    }

    function buildLuaProgram(payload) {
        let statements = [];
        let unbindCount = 0;
        let bindCount = 0;

        for (let i = 0; i < payload.unbinds.length; i++) {
            const statement = buildLuaUnbind(payload.unbinds[i]);

            if (statement) {
                statements.push(statement);
                unbindCount++;
            }
        }

        for (let i = 0; i < payload.binds.length; i++) {
            const statement = buildLuaBind(payload.binds[i]);

            if (statement) {
                statements.push(statement);
                bindCount++;
            }
        }

        if (statements.length === 0) {
            return {
                source: "",
                unbindCount: 0,
                bindCount: 0
            };
        }

        let lines = ["do"];

        for (let i = 0; i < statements.length; i++)
            lines.push("    " + statements[i]);

        lines.push("end");

        return {
            source: lines.join("\n"),
            unbindCount: unbindCount,
            bindCount: bindCount
        };
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

        if (compositorProcess.running) {
            applyTimer.restart();
            return;
        }

        const payload = buildPayload();
        const luaProgram = buildLuaProgram(payload);

        rememberCurrentBinds(payload);

        if (!luaProgram.source) {
            console.log("CompositorKeybinds: There are no Lua keybinds to apply.");
            return;
        }

        console.log(
            "CompositorKeybinds: Sending hyprctl eval (" +
            luaProgram.unbindCount + " unbinds, " +
            luaProgram.bindCount + " binds, layout: " +
            GlobalStates.compositorLayout + ")"
        );

        compositorProcess.command = [
            "hyprctl",
            "eval",
            luaProgram.source
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
