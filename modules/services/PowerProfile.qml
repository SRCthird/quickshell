pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme

Singleton {
    id: root

    property var availableProfiles: []
    property string currentProfile: ""
    property bool isAvailable: false
    property string backendType: "" // "powerprofilesctl", "asusctl", or "tlp"

    signal profileChanged(string profile)

    Timer {
        id: startupDelay
        interval: 2000
        running: true
        onTriggered: initialize()
    }

    property bool _initialized: false

    function initialize() {
        if (_initialized)
            return;

        _initialized = true;
        console.info("PowerProfile: Component initialized");
        checkPowerProfilesCtl.running = true;
    }

    function normalizeAsusctlProfile(rawProfile) {
        const profile = (rawProfile || "").trim().toLowerCase();

        if (profile === "quiet")
            return "power-saver";
        if (profile === "balanced")
            return "balanced";
        if (profile === "performance")
            return "performance";

        return "";
    }

    function toAsusctlProfile(profileName) {
        if (profileName === "power-saver")
            return "Quiet";
        if (profileName === "balanced")
            return "Balanced";
        if (profileName === "performance")
            return "Performance";

        return "";
    }

    // ============================================
    // POWERPROFILESCTL CHECK
    // ============================================
    Process {
        id: checkPowerProfilesCtl
        workingDirectory: "/"
        command: ["powerprofilesctl", "version"]
        running: false
        stdout: SplitParser {}

        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("PowerProfile: powerprofilesctl detected");
                backendType = "powerprofilesctl";
                isAvailable = true;

                Qt.callLater(() => {
                    console.info("PowerProfile: Getting profiles...");
                    getProc.running = true;

                    console.info("PowerProfile: Listing profiles...");
                    listProc.running = true;
                });
            } else {
                console.info("PowerProfile: powerprofilesctl not available, trying asusctl...");
                checkAsusctl.running = true;
            }
        }
    }

    // ============================================
    // ASUSCTL CHECK
    // ============================================
    Process {
        id: checkAsusctl
        workingDirectory: "/"
        command: ["bash", "-lc", "command -v asusctl >/dev/null 2>&1"]
        running: false
        stdout: SplitParser {}

        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("PowerProfile: asusctl detected");
                backendType = "asusctl";
                isAvailable = true;

                Qt.callLater(() => {
                    console.info("PowerProfile: Getting ASUS profile...");
                    getAsusctlProc.running = true;

                    console.info("PowerProfile: Listing ASUS profiles...");
                    listAsusctlProc.running = true;
                });
            } else {
                console.info("PowerProfile: asusctl not available, trying tlp...");
                checkTLP.running = true;
            }
        }
    }

    // ============================================
    // TLP CHECK (FALLBACK)
    // ============================================
    Process {
        id: checkTLP
        workingDirectory: "/"
        command: ["/sbin/tlp", "--version"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const output = data.trim();
                if (output && output.length > 0)
                    console.info("PowerProfile: " + output);
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("PowerProfile: ✓ TLP detected");
                backendType = "tlp";
                isAvailable = true;
                availableProfiles = ["power-saver", "balanced", "performance"];
                getTLPProc.running = true;
            } else {
                console.warn("PowerProfile: Neither powerprofilesctl, asusctl, nor tlp available");
                isAvailable = false;
                backendType = "";
                availableProfiles = [];
                currentProfile = "";
            }
        }
    }

    // ============================================
    // POWERPROFILESCTL - Get current profile
    // ============================================
    Process {
        id: getProc
        workingDirectory: "/"
        command: ["powerprofilesctl", "get"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const profile = data.trim();
                if (profile && profile.length > 0) {
                    console.info("PowerProfile: Current profile:", profile);
                    currentProfile = profile;
                    profileChanged(profile);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("PowerProfile: Failed to get powerprofilesctl profile");
        }
    }

    // ============================================
    // POWERPROFILESCTL - List available profiles
    // ============================================
    Process {
        id: listProc
        workingDirectory: "/"
        command: ["bash", "-c", "powerprofilesctl list 2>&1"]
        running: false

        property string fullOutput: ""

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                listProc.fullOutput += data + "\n";
            }
        }

        onExited: exitCode => {
            console.info("PowerProfile: listProc exit code:", exitCode);

            if (exitCode === 0 && fullOutput.trim().length > 0) {
                console.info("PowerProfile: Full output:", fullOutput);

                const lines = fullOutput.split("\n");
                const profiles = [];

                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.endsWith(":")) {
                        const profileName = line.replace("*", "").replace(":", "").trim();
                        if (profileName && profileName.length > 0 && profiles.indexOf(profileName) === -1)
                            profiles.push(profileName);
                    }
                }

                const order = ["power-saver", "balanced", "performance"];
                profiles.sort((a, b) => {
                    const indexA = order.indexOf(a);
                    const indexB = order.indexOf(b);
                    if (indexA === -1)
                        return 1;
                    if (indexB === -1)
                        return -1;
                    return indexA - indexB;
                });

                availableProfiles = profiles;
                console.info("PowerProfile: powerprofilesctl profiles loaded:", availableProfiles);
            } else {
                console.warn("PowerProfile: powerprofilesctl list failed, falling back to asusctl...");
                backendType = "";
                isAvailable = false;
                availableProfiles = [];
                checkAsusctl.running = true;
            }

            fullOutput = "";
        }
    }

    // ============================================
    // ASUSCTL - Get current profile
    // ============================================
    Process {
        id: getAsusctlProc
        workingDirectory: "/"
        command: ["asusctl", "profile", "get"]
        running: false

        property string fullOutput: ""

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                getAsusctlProc.fullOutput += data + "\n";
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("PowerProfile: Failed to get asusctl profile");
                fullOutput = "";
                return;
            }

            const lines = fullOutput.split("\n");
            let profile = "";

            for (let i = 0; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line)
                    continue;

                if (line.startsWith("Active profile:")) {
                    const rawProfile = line.substring("Active profile:".length).trim();
                    profile = root.normalizeAsusctlProfile(rawProfile);
                    break;
                }
            }

            if (profile && profile.length > 0) {
                console.info("PowerProfile: asusctl current profile:", profile);
                currentProfile = profile;
                profileChanged(profile);
            } else if (fullOutput.trim().length > 0) {
                console.warn("PowerProfile: Could not parse active asusctl profile from:", fullOutput.trim());
            }

            fullOutput = "";
        }
    }
    // ============================================
    // ASUSCTL - List available profiles
    // ============================================
    Process {
        id: listAsusctlProc
        workingDirectory: "/"
        command: ["asusctl", "profile", "list"]
        running: false

        property string fullOutput: ""

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                listAsusctlProc.fullOutput += data + "\n";
            }
        }

        onExited: exitCode => {
            console.info("PowerProfile: listAsusctlProc exit code:", exitCode);

            if (exitCode === 0) {
                const lines = fullOutput.split("\n");
                const profiles = [];

                for (let i = 0; i < lines.length; i++) {
                    const normalized = root.normalizeAsusctlProfile(lines[i]);
                    if (normalized && profiles.indexOf(normalized) === -1)
                        profiles.push(normalized);
                }

                const order = ["power-saver", "balanced", "performance"];
                profiles.sort((a, b) => {
                    const indexA = order.indexOf(a);
                    const indexB = order.indexOf(b);
                    if (indexA === -1)
                        return 1;
                    if (indexB === -1)
                        return -1;
                    return indexA - indexB;
                });

                availableProfiles = profiles;
                console.info("PowerProfile: asusctl profiles loaded:", availableProfiles);
            } else {
                console.warn("PowerProfile: Failed to list asusctl profiles");
            }

            fullOutput = "";
        }
    }

    // ============================================
    // TLP - Get current profile
    // ============================================
    Process {
        id: getTLPProc
        workingDirectory: "/"
        command: ["bash", "-c", "/sbin/tlp-stat -p 2>/dev/null | grep -i 'Active profile' | head -1"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line)
                    return;

                console.info("PowerProfile: tlp-stat output:", line);
                let profile = "";

                if (line.includes("power-saver") || line.includes("powersaver")) {
                    profile = "power-saver";
                } else if (line.includes("balanced")) {
                    profile = "balanced";
                } else if (line.includes("performance")) {
                    profile = "performance";
                }

                if (profile && currentProfile !== profile) {
                    currentProfile = profile;
                    console.info("PowerProfile: ✓ Current profile set to:", profile);
                    profileChanged(profile);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("PowerProfile: Failed to get TLP profile");
        }
    }

    // ============================================
    // SET PROFILE - Support all backends
    // ============================================
    Process {
        id: setProc
        workingDirectory: "/"
        running: false
        stdout: SplitParser {}
        stderr: SplitParser {
            onRead: data => {
                const err = data.trim();
                if (err && err.length > 0)
                    console.warn("PowerProfile: Error:", err);
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("PowerProfile: Profile changed successfully");

                Qt.callLater(() => {
                    if (backendType === "powerprofilesctl") {
                        getProc.running = true;
                    } else if (backendType === "asusctl") {
                        getAsusctlProc.running = true;
                    } else if (backendType === "tlp") {
                        getTLPProc.running = true;
                    }
                });
            } else {
                console.warn("PowerProfile: Failed to set profile");
            }
        }
    }

    function updateCurrentProfile() {
        if (!isAvailable)
            return;

        if (backendType === "powerprofilesctl") {
            getProc.running = true;
        } else if (backendType === "asusctl") {
            getAsusctlProc.running = true;
        } else if (backendType === "tlp") {
            getTLPProc.running = true;
        }
    }

    function updateAvailableProfiles() {
        if (!isAvailable)
            return;

        if (backendType === "powerprofilesctl") {
            availableProfiles = [];
            listProc.running = true;
        } else if (backendType === "asusctl") {
            availableProfiles = [];
            listAsusctlProc.running = true;
        } else if (backendType === "tlp") {
            console.info("PowerProfile: Available profiles:", availableProfiles);
        }
    }

    function setProfile(profileName) {
        if (!isAvailable) {
            console.warn("PowerProfile: Cannot set profile - service not available");
            return;
        }

        let found = false;
        for (let i = 0; i < availableProfiles.length; i++) {
            if (availableProfiles[i] === profileName) {
                found = true;
                break;
            }
        }

        if (!found) {
            console.warn("PowerProfile: Profile not available:", profileName);
            return;
        }

        console.info("PowerProfile: Setting profile to:", profileName, "using", backendType);

        if (backendType === "powerprofilesctl") {
            setProc.command = ["powerprofilesctl", "set", profileName];
        } else if (backendType === "asusctl") {
            const asusctlProfile = toAsusctlProfile(profileName);
            if (!asusctlProfile) {
                console.warn("PowerProfile: Could not map profile for asusctl:", profileName);
                return;
            }

            setProc.command = ["asusctl", "profile", "set", asusctlProfile];
        } else if (backendType === "tlp") {
            setProc.command = ["sudo", "/sbin/tlp", profileName];
        } else {
            console.warn("PowerProfile: Unknown backend:", backendType);
            return;
        }

        setProc.running = true;
    }

    function getProfileIcon(profileName) {
        if (profileName === "power-saver")
            return Icons.powerSave;
        if (profileName === "balanced")
            return Icons.balanced;
        if (profileName === "performance")
            return Icons.performance;
        return Icons.balanced;
    }

    function getProfileDisplayName(profileName) {
        if (profileName === "power-saver")
            return "Power Save";
        if (profileName === "balanced")
            return "Balanced";
        if (profileName === "performance")
            return "Performance";
        return profileName;
    }
}
