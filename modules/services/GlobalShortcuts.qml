pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.globals
import qs.modules.services
import qs.modules.config

import Quickshell.Io

QtObject {
    id: root

    readonly property string appId: "shell"
    readonly property string ipcPipe: "/tmp/shell_ipc.pipe"

    // High-performance Pipe Listener (Daemon mode)
    property Process pipeListener: Process {
        command: ["bash", "-c", "rm -f " + root.ipcPipe + "; mkfifo " + root.ipcPipe + "; tail -f " + root.ipcPipe]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }
    }

    property IpcHandler ipcShellHandler: IpcHandler {
        target: "shell"

        function launcher() {
            toggleLauncher();
        }
        function clipboard() {
            toggleLauncherWithPrefix(1, Config.prefix.clipboard + " ");
        }
        function emoji() {
            toggleLauncherWithPrefix(2, Config.prefix.emoji + " ");
        }
        function tmux() {
            toggleLauncherWithPrefix(3, Config.prefix.tmux + " ");
        }
        function notes() {
            toggleLauncherWithPrefix(4, Config.prefix.notes + " ");
        }
        function dashboard() {
            toggleDashboardTab(0);
        }
        function wallpapers() {
            toggleDashboardTab(1);
        }
        function assistant() {
            GlobalStates.toggleAssistant();
        }
        function widgets() {
            toggleDashboardTab(0);
        }
        function kanban() {
            toggleDashboardTab(2);
        }
        function controls() {
            toggleSettings();
        }
    }

    property IpcHandler ipcSystemHandler: IpcHandler {
        target: "system"

        function overview() {
          toggleSimpleModule("overview");
        } 
        function powermenu() {
          toggleSimpleModule("powermenu");
        }
        function tools() {
          toggleSimpleModule("tools");
        }
        function configs() {
          toggleSettings();
        }
        function screenshot(){
          Screenshot.initialize();
          GlobalStates.screenshotToolVisible = true;
        } 
        function screenrecord() {
          ScreenRecorder.initialize();
          GlobalStates.screenRecordToolVisible = true;
        }
        function lens() {
          Screenshot.initialize();
          Screenshot.captureMode = "lens";
          GlobalStates.screenshotToolVisible = true;
        }
        function lockscreen() {
          GlobalStates.lockscreenVisible = true;
        }
    }

    property IpcHandler ipcMediaHandler: IpcHandler {
        target: "media"

        function backward() {
            seekActivePlayer(-mediaSeekStepMs);
        }
        function forward() {
            seekActivePlayer(mediaSeekStepMs);
        }
        function toggle() {
            MprisController.togglePlaying();
        }
        function pause() {
            if (MprisController.isPlaying) MprisController.togglePlaying();
        }
        function play() {
            if (!MprisController.isPlaying) MprisController.togglePlaying();
        }
        function next() {
            MprisController.next();
        }
        function previous() {
            MprisController.previous();
        }
    }

    function toggleSettings() {
        GlobalStates.settingsWindowVisible = !GlobalStates.settingsWindowVisible;
        if (GlobalStates.settingsWindowVisible) {
            Visibilities.setActiveModule("");
        }
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.currentActiveModule === moduleName) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }

    function toggleLauncher() {
        const isActive = Visibilities.currentActiveModule === "launcher";
        if (isActive && GlobalStates.widgetsTabCurrentIndex === 0 && GlobalStates.launcherSearchText === "") {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.widgetsTabCurrentIndex = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("launcher");
            }
        }
    }

    function toggleLauncherWithPrefix(tabIndex, prefix) {
        const isActive = Visibilities.currentActiveModule === "launcher";
        const currentTab = GlobalStates.widgetsTabCurrentIndex;
        const currentText = GlobalStates.launcherSearchText;

        if (isActive && currentTab === tabIndex && (currentText === prefix || currentText === "")) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.widgetsTabCurrentIndex = tabIndex;
        GlobalStates.launcherSearchText = prefix;
        
        if (!isActive) {
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Special handling for widgets tab (launcher)
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                // Only toggle off if we're already in launcher without prefix
                Visibilities.setActiveModule("");
                return;
            }
            
            // Otherwise, always go to launcher (clear any prefix and ensure tab 0)
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        // For other tabs, normal toggle behavior
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function toggleDashboardWithPrefix(prefix) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === prefix) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.dashboardCurrentTab = 0;
        
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
            Qt.callLater(() => {
                GlobalStates.launcherSearchText = prefix;
            });
        } else {
            GlobalStates.launcherSearchText = prefix;
        }
    }

    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }
}
