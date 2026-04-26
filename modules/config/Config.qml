pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals
import qs.modules.theme
import qs.modules.services as Services
import qs.modules.config.adapters

Singleton {
    id: root

    property string version: "0.0.0"

    FileView {
        id: versionFile
        path: Qt.resolvedUrl("../../version").toString().replace("file://", "")
        onLoaded: root.version = text().trim()
    }

    property bool pauseAutoSave: false

    // Module init status
    property bool themeReady: false
    property bool barReady: false
    property bool workspacesReady: false
    property bool overviewReady: false
    property bool notchReady: false
    property bool compositorReady: false
    property bool performanceReady: false
    property bool weatherReady: false
    property bool desktopReady: false
    property bool lockscreenReady: false
    property bool prefixReady: false
    property bool systemReady: false
    property bool dockReady: false
    property bool aiReady: false
    property bool pinnedAppsReady: false
    property bool keybindsReady: false

    property bool initialLoadComplete: themeReady && barReady && workspacesReady && overviewReady && notchReady && compositorReady && performanceReady && weatherReady && desktopReady && lockscreenReady && prefixReady && systemReady && dockReady && aiReady && pinnedAppsReady

    // ============================================
    // BATCH INITIALIZATION
    // ============================================
    property bool configBootstrapReady: false

    Process {
        id: ensureConfigDir
        running: true
        command: [
            "bash", "-lc",
            `
            cfg="${Quickshell.shellDir}/config"
            mkdir -p "$cfg"

            for f in ai bar binds compositor desktop dock lockscreen notch overview performance prefix system theme weather workspaces; do
                [ -e "$cfg/$f.json" ] || : > "$cfg/$f.json"
            done

            dataFile="${Quickshell.dataPath("pinnedapps.json")}"
            mkdir -p "$(dirname "$dataFile")"
            [ -e "$dataFile" ] || : > "$dataFile"
            `
        ]

        onExited: {
            root.configBootstrapReady = true;
        }
    }

    function initModule(name, loader, onComplete) {
        var raw = loader.text();

        if (!raw || raw.trim().length === 0) {
            console.log(name + ".json missing or empty, creating from adapter...");
            loader.writeAdapter();
            onComplete();
            return;
        }

        try {
            JSON.parse(raw);
        } catch (e) {
            console.warn(name + ".json invalid, resetting from adapter:", e);
            loader.writeAdapter();
            onComplete();
            return;
        }

        loader.writeAdapter();
        onComplete();
    }

    // ============================================
    // THEME MODULE
    // ============================================
    Process {
        id: systemColorSchemeProcess
        running: false
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    console.log("systemColorScheme stdout:", text);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    console.warn("systemColorScheme stderr:", text);
            }
        }

        onExited: code => {
            console.log("systemColorScheme exited with code:", code);
        }
    }
    function syncSystemColorScheme() {
        var scheme = root.lightMode ? "prefer-light" : "prefer-dark";
        var gtkDark = root.lightMode ? "false" : "true";

        if (systemColorSchemeProcess.running)
            systemColorSchemeProcess.running = false;

        systemColorSchemeProcess.command = [
            "bash",
            "-lc",
            "gsettings set org.gnome.desktop.interface color-scheme " + scheme + " && " +
            "gsettings set org.gnome.desktop.interface gtk-application-prefer-dark-theme " + gtkDark
        ];

        systemColorSchemeProcess.running = true;
    }
    FileView {
        id: themeLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/theme.json") : ""
        atomicWrites: true
        watchChanges: true

        onLoaded: {
            if (!root.themeReady) {
                initModule("theme", themeLoader, () => {
                    root.themeReady = true;
                    root.themeUpdated();
                    root.syncSystemColorScheme();
                });
            } else {
                root.themeUpdated();
                root.syncSystemColorScheme();
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.themeReady && !root.pauseAutoSave) {
                themeLoader.writeAdapter();
                root.themeUpdated();
            }
        }

        adapter: ThemeAdapter {}

    }

    // ============================================
    // BAR MODULE
    // ============================================
    FileView {
        id: barLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/bar.json") : ""
        atomicWrites: true
        watchChanges: true

        onLoaded: {
            if (!root.barReady) {
                initModule("bar", barLoader, () => {
                    root.barReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.barReady && !root.pauseAutoSave) {
                barLoader.writeAdapter();
            }
        }

        adapter: BarAdapter {}
    }

    // ============================================
    // WORKSPACES MODULE
    // ============================================
    FileView {
        id: workspacesLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/workspaces.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.workspacesReady) {
                initModule("workspaces", workspacesLoader, () => {
                    root.workspacesReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.workspacesReady && !root.pauseAutoSave) {
                workspacesLoader.writeAdapter();
            }
        }

        adapter: WorkspacesAdapter {} 
    }

    // ============================================
    // OVERVIEW MODULE
    // ============================================
    FileView {
        id: overviewLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/overview.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.overviewReady) {
                initModule("overview", overviewLoader, () => {
                    root.overviewReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.overviewReady && !root.pauseAutoSave) {
                overviewLoader.writeAdapter();
            }
        }

        adapter: OverviewAdapter {}
    }

    // ============================================
    // NOTCH MODULE
    // ============================================
    FileView {
        id: notchLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/notch.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.notchReady) {
                initModule("notch", notchLoader, () => {
                    root.notchReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.notchReady && !root.pauseAutoSave) {
                notchLoader.writeAdapter();
            }
        }

        adapter: NotchAdapter {} 
    }

    // ============================================
    // COMPOSITOR MODULE
    // ============================================
    FileView {
        id: compositorLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/compositor.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.compositorReady) {
                initModule("compositor", compositorLoader, () => {
                    root.compositorReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.compositorReady && !root.pauseAutoSave) {
                compositorLoader.writeAdapter();
            }
        }

        adapter: ComposerAdapter {} 
    }

    // ============================================
    // PERFORMANCE MODULE
    // ============================================
    FileView {
        id: performanceLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/performance.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.performanceReady) {
                initModule("performance", performanceLoader, () => {
                    root.performanceReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.performanceReady && !root.pauseAutoSave) {
                performanceLoader.writeAdapter();
            }
        }

        adapter: PerformanceAdapter {} 
    }

    // ============================================
    // WEATHER MODULE
    // ============================================
    FileView {
        id: weatherLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/weather.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.weatherReady) {
                initModule("weather", weatherLoader, () => {
                    root.weatherReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.weatherReady && !root.pauseAutoSave) {
                weatherLoader.writeAdapter();
            }
        }

        adapter: WeatherAdapter {} 
    }

    // ============================================
    // DESKTOP MODULE
    // ============================================
    FileView {
        id: desktopLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/desktop.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.desktopReady) {
                initModule("desktop", desktopLoader, () => {
                    root.desktopReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.desktopReady && !root.pauseAutoSave) {
                desktopLoader.writeAdapter();
            }
        }

        adapter: DesktopAdapter {} 
    }

    // ============================================
    // LOCKSCREEN MODULE
    // ============================================
    FileView {
        id: lockscreenLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/lockscreen.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.lockscreenReady) {
                initModule("lockscreen", lockscreenLoader, () => {
                    root.lockscreenReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.lockscreenReady && !root.pauseAutoSave) {
                lockscreenLoader.writeAdapter();
            }
        }

        adapter: LockscreenAdapter {} 
    }

    // ============================================
    // PREFIX MODULE
    // ============================================
    FileView {
        id: prefixLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/prefix.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.prefixReady) {
                initModule("prefix", prefixLoader, () => {
                    root.prefixReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.prefixReady && !root.pauseAutoSave) {
                prefixLoader.writeAdapter();
            }
        }

        adapter: PrefixAdapter {} 
    }

    // ============================================
    // SYSTEM MODULE
    // ============================================
    FileView {
        id: systemLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/system.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.systemReady) {
                initModule("system", systemLoader, () => {
                    root.systemReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.systemReady && !root.pauseAutoSave) {
                systemLoader.writeAdapter();
            }
        }

        adapter: SystemAdapter {} 
    }

    // ============================================
    // DOCK MODULE
    // ============================================
    FileView {
        id: dockLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/dock.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.dockReady) {
                initModule("dock", dockLoader, () => {
                    root.dockReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.dockReady && !root.pauseAutoSave) {
                dockLoader.writeAdapter();
            }
        }

        adapter: DockAdapter {} 
    }


    FileView {
        id: pinnedAppsLoader
        path: Quickshell.dataPath("pinnedapps.json")
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.pinnedAppsReady) {
                initModule("pinnedApps", pinnedAppsLoader, () => {
                    root.pinnedAppsReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.pinnedAppsReady && !root.pauseAutoSave) {
                pinnedAppsLoader.writeAdapter();
            }
        }

        adapter: PinnedAppsAdapter {}
    }

    // ============================================
    // AI MODULE
    // ============================================
    FileView {
        id: aiLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/ai.json") : ""
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (!root.aiReady) {
                initModule("ai", aiLoader, () => {
                    root.aiReady = true;
                });
            }
        }
        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }
        onPathChanged: reload()
        onAdapterUpdated: {
            if (root.aiReady && !root.pauseAutoSave) {
                aiLoader.writeAdapter();
            }
        }

        adapter: AiAdapter {} 
    }

    // ============================================
    // KEYBINDS MODULE
    // ============================================
    FileView {
        id: keybindsLoader
        path: root.configBootstrapReady ? Quickshell.shellPath("config/binds.json") : ""
        atomicWrites: true
        watchChanges: true

        onLoaded: {
            if (!root.keybindsReady) {
                initModule("binds", keybindsLoader, () => {
                    root.keybindsReady = true;
                    root.keybindsUpdated();
                });
            } else {
                root.keybindsUpdated();
            }
        }

        onFileChanged: {
            root.pauseAutoSave = true;
            reload();
            root.pauseAutoSave = false;
        }

        onPathChanged: reload()

        onAdapterUpdated: {
            if (root.keybindsReady && !root.pauseAutoSave) {
                keybindsLoader.writeAdapter();
                root.keybindsUpdated();
            }
        }

        adapter: KeybindsAdapter {} 
    }

    // Exposed properties

    property bool oledMode: lightMode ? false : theme.oledMode
    property bool lightMode: theme.lightMode

    property int roundness: theme.roundness
    property string defaultFont: theme.font
    property int animDuration: Services.GameModeService.toggled ? 0 : theme.animDuration
    property bool tintIcons: theme.tintIcons

    // Handle lightMode changes
    onLightModeChanged: {
        console.log("lightMode changed to:", lightMode);

        syncSystemColorScheme();

        if (GlobalStates.wallpaperManager) {
            var wallpaperManager = GlobalStates.wallpaperManager;
            if (wallpaperManager.currentWallpaper) {
                console.log("Re-running Matugen due to lightMode change");
                wallpaperManager.runMatugenForCurrentWallpaper();
            }
        }
    }
    // Bar configuration
    property QtObject bar: barLoader.adapter
    property bool showBackground: theme.srBarBg.opacity > 0

    // Workspace configuration
    property QtObject workspaces: workspacesLoader.adapter

    // Overview configuration
    property QtObject overview: overviewLoader.adapter

    // Notch configuration
    property QtObject notch: notchLoader.adapter
    property string notchTheme: notch.theme
    property string notchPosition: notch.position

    onNotchPositionChanged: {
        if (!initialLoadComplete || !dockReady) return;

        // If notch moves bottom
        if (notchPosition === "bottom") {
            // Conflict with Dock?
            if (dock.position === "bottom") {
                console.log("Notch moved to bottom, adjusting Dock position...");
                // Offset Dock to avoid notch
                if (bar.position === "left") {
                    dock.position = "right";
                } else {
                    dock.position = "left";
                }
                // Trigger save
                GlobalStates.markShellChanged();
            }
        } 
        // If notch moves top
        else if (notchPosition === "top") {
            // Restore Dock if displaced
            if (dock.position === "left" || dock.position === "right") {
                console.log("Notch moved to top, restoring Dock to bottom...");
                dock.position = "bottom";
                GlobalStates.markShellChanged();
            }
        }
    }

    // Compositor configuration
    property QtObject compositor: compositorLoader.adapter
    property int compositorRounding: compositor.syncRoundness ? roundness : compositor.rounding
    property int compositorBorderSize: compositor.syncBorderWidth ? (theme.srBg.border[1] || 0) : compositor.borderSize
    property string compositorBorderColor: compositor.syncBorderColor ? (theme.srBg.border[0] || "primary") : (compositor.activeBorderColor.length > 0 ? compositor.activeBorderColor[0] : "primary")
    property real compositorShadowOpacity: compositor.syncShadowOpacity ? theme.shadowOpacity : compositor.shadowOpacity
    property string compositorShadowColor: compositor.syncShadowColor ? theme.shadowColor : compositor.shadowColor

    // Performance configuration
    property QtObject performance: performanceLoader.adapter
    property bool blurTransition: performance.blurTransition

    // Weather configuration
    property QtObject weather: weatherLoader.adapter

    // Desktop configuration
    property QtObject desktop: desktopLoader.adapter

    // Lockscreen configuration
    property QtObject lockscreen: lockscreenLoader.adapter

    // Prefix configuration
    property QtObject prefix: prefixLoader.adapter

    // System configuration
    property QtObject system: systemLoader.adapter

    // Dock configuration
    property QtObject dock: dockLoader.adapter

    // Pinned apps configuration (stored in dataPath)
    property QtObject pinnedApps: pinnedAppsLoader.adapter

    // AI configuration
    property QtObject ai: aiLoader.adapter

    // Theme configuration
    signal themeUpdated()
    property QtObject theme: themeLoader.adapter

    // Keybinds configuration
    signal keybindsUpdated()
    property QtObject keybinds: keybindsLoader.adapter

    // Module save functions
    function saveBar() {
        barLoader.writeAdapter();
    }
    function saveWorkspaces() {
        workspacesLoader.writeAdapter();
    }
    function saveOverview() {
        overviewLoader.writeAdapter();
    }
    function saveNotch() {
        notchLoader.writeAdapter();
    }
    function saveCompositor() {
        compositorLoader.writeAdapter();
    }
    function savePerformance() {
        performanceLoader.writeAdapter();
    }
    function saveWeather() {
        weatherLoader.writeAdapter();
    }
    function saveDesktop() {
        desktopLoader.writeAdapter();
    }
    function saveLockscreen() {
        lockscreenLoader.writeAdapter();
    }
    function savePrefix() {
        prefixLoader.writeAdapter();
    }
    function saveSystem() {
        systemLoader.writeAdapter();
    }
    function saveDock() {
        dockLoader.writeAdapter();
    }
    function savePinnedApps() {
        pinnedAppsLoader.writeAdapter();
    }
    function saveAi() {
        aiLoader.writeAdapter();
    }

    // Color helpers
    function isHexColor(colorValue) {
        if (!colorValue || typeof colorValue !== 'string')
            return false;
        const normalized = colorValue.toLowerCase().trim();
        return normalized.startsWith('#') || normalized.startsWith('rgb');
    }

    function resolveColor(colorValue) {
        if (!colorValue) return "transparent"; // Fallback
        
        if (isHexColor(colorValue)) {
            return colorValue;
        }
        
        // Check Colors singleton
        if (typeof Colors === 'undefined' || !Colors) return "transparent";
        
        return Colors[colorValue] || "transparent"; 
    }

    function resolveColorWithOpacity(colorValue, opacity) {
        if (!colorValue) return Qt.rgba(0,0,0,0);
        
        const color = isHexColor(colorValue) ? Qt.color(colorValue) : (Colors[colorValue] || Qt.color("transparent"));
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }
}
