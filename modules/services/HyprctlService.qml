pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var focusedMonitor: null
    property var focusedWorkspace: null
    property var focusedClient: null

    property int focusHistoryCounter: 0
    property bool shuttingDown: false

    property QtObject clients: QtObject {
        property var values: []
    }

    property QtObject monitors: QtObject {
        property var values: []
    }

    property QtObject workspaces: QtObject {
        property var values: []
    }

    signal rawEvent(var event)

    function dispatch(command) {
        if (!command) return;

        let spaceIdx = command.indexOf(" ");
        let action = spaceIdx !== -1 ? command.substring(0, spaceIdx).trim() : command.trim();
        let rawArgs = spaceIdx !== -1 ? command.substring(spaceIdx + 1).trim() : "";

        function getAddr(str) {
            let m = str.match(/address:([^\s,]+)/);
            return m ? m[1] : str.trim();
        }

        let finalCommand = ["hyprctl", "dispatch"];

        if (action === "workspace") {
            finalCommand.push("workspace");
            if (rawArgs) finalCommand.push(rawArgs);
        } else if (action === "closewindow") {
            finalCommand.push("closewindow");
            if (rawArgs) finalCommand.push("address:" + getAddr(rawArgs));
        } else if (action === "focuswindow") {
            finalCommand.push("focuswindow");
            if (rawArgs) finalCommand.push("address:" + getAddr(rawArgs));
        } else if (action === "movetoworkspacesilent") {
            finalCommand.push("movetoworkspacesilent");
            let subParts = rawArgs.split(",");
            let ws = subParts.length > 0 ? subParts[0].trim() : "";
            if (subParts.length > 1) {
                finalCommand.push(ws + ",address:" + getAddr(subParts[1]));
            } else if (ws) {
                finalCommand.push(ws);
            }
        } else if (action === "togglespecialworkspace") {
            finalCommand.push("togglespecialworkspace");
            if (rawArgs) finalCommand.push(rawArgs);
        } else {
            finalCommand.push(action);
            if (rawArgs) finalCommand.push(rawArgs);
        }

        let proc = Qt.createQmlObject("import Quickshell.Io; Process {}", root);
        proc.command = finalCommand;
        proc.onExited.connect(() => proc.destroy());
        proc.running = true;
    }

    function monitorFor(screen) {
        if (!screen) return null;
        let screenName = screen.name || screen;
        let values = root.monitors.values || [];
        for (let i = 0; i < values.length; i++) {
            if (values[i].name === screenName) return values[i];
        }
        return null;
    }

    function applyState(state) {
        if (!state) return;

        // --- Windows ---
        if (state.windows) {
            let existingClients = root.clients.values || [];
            let mappedClients = state.windows.map(win => {
                let existing = existingClients.find(c => c.address === win.id);
                let prevFocus = existing && existing.focusHistoryID !== undefined
                    ? existing.focusHistoryID
                    : 999999;
                let newFocus = win.is_focused
                    ? (existing && existing.is_focused ? prevFocus : --root.focusHistoryCounter)
                    : prevFocus;

                return {
                    address: win.id,
                    class: win.app_id,
                    title: win.title,
                    workspace: {
                        id: parseInt(win.workspace_id) || 0,
                        name: win.workspace_id
                    },
                    monitor: parseInt(win.metadata ? win.metadata.monitor_id : 0) || 0,
                    floating: !!win.is_floating,
                    fullscreen: !!win.is_fullscreen,
                    hidden: !!win.is_hidden,
                    mapped: true,
                    at: [
                        win.metadata ? (win.metadata.x || 0) : 0,
                        win.metadata ? (win.metadata.y || 0) : 0
                    ],
                    size: [
                        win.metadata ? (win.metadata.width || 100) : 100,
                        win.metadata ? (win.metadata.height || 100) : 100
                    ],
                    xwayland: !!(win.metadata ? win.metadata.xwayland : false),
                    is_focused: !!win.is_focused,
                    focusHistoryID: newFocus
                };
            });

            root.clients.values = mappedClients;

            let focused = mappedClients.find(w => w.is_focused)
                || mappedClients.find(w => w.address === (root.focusedClient ? root.focusedClient.address : undefined))
                || null;

            if (focused !== root.focusedClient) {
                root.focusedClient = focused;
            }
        }

        // --- Workspaces ---
        if (state.workspaces) {
            let mappedWorkspaces = state.workspaces.map(ws => ({
                id: parseInt(ws.id) || 0,
                name: ws.name,
                monitor: ws.monitor_id,
                active: !!ws.is_active,
                windows: ws.windows !== undefined ? ws.windows : 0
            }));

            root.workspaces.values = mappedWorkspaces;

            let focused = mappedWorkspaces.find(ws => ws.active) || null;
            if (focused !== root.focusedWorkspace) {
                root.focusedWorkspace = focused;
            }
        }

        // --- Monitors ---
        if (state.monitors) {
            let mappedMonitors = state.monitors.map(mon => ({
                id: parseInt(mon.id) || 0,
                name: mon.name,
                focused: !!mon.is_focused,
                width: mon.width,
                height: mon.height,
                refreshRate: mon.refresh_rate,
                scale: mon.scale,
                activeWorkspace: {
                    id: parseInt(mon.metadata ? mon.metadata.active_workspace : 0) || 0,
                    name: mon.metadata ? mon.metadata.active_workspace : ""
                }
            }));

            root.monitors.values = mappedMonitors;

            let focused = mappedMonitors.find(m => m.focused) || null;
            if (focused !== root.focusedMonitor) {
                root.focusedMonitor = focused;
            }
        }
    }

    Timer {
        id: subscribeDelay
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            if (root.shuttingDown) return;
            hyprSubscribe.running = true;
            root.refreshStateFromHyprland();
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.shuttingDown) return;
            hyprSubscribe.running = true;
            root.refreshStateFromHyprland();
        }
    }

    property Process hyprSubscribe: Process {
        command: [
            "sh", "-lc",
            "exec socat -U - UNIX-CONNECT:\"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock\""
        ]
        running: false

        stdout: SplitParser {
            onRead: (line) => {
                if (!line) return;

                try {
                    const idx = line.indexOf(">>");
                    const eventName = idx >= 0
                        ? line.slice(0, idx).trim().toLowerCase()
                        : "";
                    const eventData = idx >= 0
                        ? line.slice(idx + 2).trim()
                        : line.trim();

                    if (
                        eventName === "openwindow" ||
                        eventName === "closewindow" ||
                        eventName === "movewindow" ||
                        eventName === "activewindow" ||
                        eventName === "activewindowv2" ||
                        eventName === "workspace" ||
                        eventName === "workspacev2" ||
                        eventName === "focusedmon" ||
                        eventName === "focusedmonv2" ||
                        eventName === "fullscreen" ||
                        eventName === "monitoradded" ||
                        eventName === "monitoraddedv2" ||
                        eventName === "monitorremoved" ||
                        eventName === "monitorremovedv2" ||
                        eventName === "createworkspace" ||
                        eventName === "createworkspacev2" ||
                        eventName === "destroyworkspace" ||
                        eventName === "destroyworkspacev2"
                    ) {
                        root.refreshStateFromHyprland();
                    }

                    root.rawEvent({
                        jsonrpc: "2.0",
                        method: eventName,
                        name: eventName,
                        params: eventData,
                        data: eventData
                    });
                } catch (e) {
                    console.error("Hyprland subscribe parse error:", e, "line:", line);
                }
            }
        }

        stderr: SplitParser {
            onRead: (line) => {
                if (line && line.trim().length > 0) {
                    console.error("hyprSubscribe stderr:", line);
                }
            }
        }

        onExited: (code) => {
            if (root.shuttingDown) return;
            console.warn("hyprland socket2 exited:", code);
            reconnectTimer.restart();
        }
    }

    property var hyprStateScratch: ({})
    property string hyprStatePhase: ""
    property string hyprStateStdout: ""
    property bool hyprRefreshInFlight: false
    property bool hyprRefreshPending: false

    property Process hyprStateDump: Process {
        id: hyprStateDumpProc
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.hyprStateStdout = this.text || "";
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line && line.trim().length > 0) {
                    console.error("hyprStateDump stderr:", line);
                }
            }
        }

        onExited: code => {
            const phase = root.hyprStatePhase;
            const text = (root.hyprStateStdout || "").trim();

            if (root.shuttingDown) return;

            if (code !== 0) {
                console.warn("hyprStateDump exited with code:", code, "phase:", phase);
                root.finishHyprRefresh();
                return;
            }

            try {
                let parsed;
                if (text.length === 0) {
                    parsed = (phase === "activewindow") ? {} : [];
                } else {
                    parsed = JSON.parse(text);
                }

                root.hyprStateScratch[phase] = parsed;

                switch (phase) {
                case "windows":
                    root.runHyprStatePhase("workspaces", ["hyprctl", "-j", "workspaces"]);
                    break;
                case "workspaces":
                    root.runHyprStatePhase("monitors", ["hyprctl", "-j", "monitors"]);
                    break;
                case "monitors":
                    root.runHyprStatePhase("activewindow", ["hyprctl", "-j", "activewindow"]);
                    break;
                case "activewindow":
                    root.applyState(root.normalizeHyprState(root.hyprStateScratch));
                    root.finishHyprRefresh();
                    break;
                default:
                    root.finishHyprRefresh();
                    break;
                }
            } catch (e) {
                console.error("Hyprland state dump parse error:", e);
                console.error("Phase:", phase);
                console.error("Raw hyprStateDump stdout:", text);
                root.finishHyprRefresh();
            }
        }
    }

    function runHyprStatePhase(phase, command) {
        root.hyprStatePhase = phase;
        root.hyprStateStdout = "";
        hyprStateDumpProc.exec(command);
    }

    function finishHyprRefresh() {
        root.hyprRefreshInFlight = false;

        if (root.hyprRefreshPending) {
            root.hyprRefreshPending = false;
            root.refreshStateFromHyprland();
        }
    }

    function refreshStateFromHyprland() {
        if (root.shuttingDown) return;

        if (root.hyprRefreshInFlight) {
            root.hyprRefreshPending = true;
            return;
        }

        root.hyprRefreshInFlight = true;
        root.hyprRefreshPending = false;
        root.hyprStateScratch = {};
        root.runHyprStatePhase("windows", ["hyprctl", "-j", "clients"]);
    }

    function normalizeHyprState(raw) {
        const activeAddress = raw.activewindow?.address ?? "";

        return {
            windows: (raw.windows ?? []).map(w => ({
                id: w.address,
                title: w.title,
                app_id: w.class,
                workspace_id: String(w.workspace?.id ?? ""),
                is_focused: w.address === activeAddress,
                is_floating: !!w.floating,
                is_fullscreen: !!w.fullscreen,
                is_hidden: !!w.hidden,
                metadata: {
                    height: w.size?.[1] ?? 0,
                    monitor_id: String(w.monitor ?? ""),
                    pinned: !!w.pinned,
                    width: w.size?.[0] ?? 0,
                    x: w.at?.[0] ?? 0,
                    y: w.at?.[1] ?? 0
                }
            })),

            workspaces: (raw.workspaces ?? []).map(ws => {
                const focusedMonitor = (raw.monitors ?? []).find(m => m.focused);
                const owningMonitor = (raw.monitors ?? []).find(
                    m => m.activeWorkspace?.id === ws.id || m.activeWorkspace?.name === ws.name
                );

                return {
                    id: String(ws.id),
                    name: ws.name,
                    monitor_id: owningMonitor?.name ?? ws.monitor ?? "",
                    is_active: !!owningMonitor,
                    is_empty: (ws.windows ?? 0) === 0,
                    windows: ws.windows ?? 0,
                    metadata: {
                        focused: !!focusedMonitor && (
                            focusedMonitor.activeWorkspace?.id === ws.id ||
                            focusedMonitor.activeWorkspace?.name === ws.name
                        )
                    }
                };
            }),

            monitors: (raw.monitors ?? []).map(m => ({
                id: String(m.id ?? ""),
                name: m.name,
                width: m.width ?? 0,
                height: m.height ?? 0,
                refresh_rate: m.refreshRate ?? 0,
                scale: m.scale ?? 1,
                is_focused: !!m.focused,
                metadata: {
                    active_workspace: String(m.activeWorkspace?.id ?? m.activeWorkspace?.name ?? ""),
                    transform: m.transform ?? 0,
                    x: m.x ?? 0,
                    y: m.y ?? 0
                }
            }))
        };
    }

    Component.onDestruction: {
        root.shuttingDown = true;
        reconnectTimer.stop();
        subscribeDelay.stop();
        hyprSubscribe.running = false;
        hyprStateDump.running = false;
    }
}
