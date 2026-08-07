pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.config
import qs.modules.globals

pragma ComponentBehavior: Bound

Singleton {
    id: root

    property real cpuUsage: 0.0
    property string cpuModel: ""
    property int cpuTemp: -1

    property real previousCpuTotal: 0
    property real previousCpuIdle: 0

    property string cpuTempPath: ""
    property bool cpuTempDiscovering: false
    property var cpuHwmonNamePaths: []
    property int cpuHwmonIndex: -1
    property var cpuTempCandidatePaths: []
    property int cpuTempCandidateIndex: -1

    property string currentCpuHwmonNamePath:
        cpuTempDiscovering
        && cpuHwmonIndex >= 0
        && cpuHwmonIndex < cpuHwmonNamePaths.length
            ? cpuHwmonNamePaths[cpuHwmonIndex]
            : ""

    property string currentCpuTempCandidatePath:
        cpuTempDiscovering
        && cpuTempCandidateIndex >= 0
        && cpuTempCandidateIndex < cpuTempCandidatePaths.length
            ? cpuTempCandidatePaths[cpuTempCandidateIndex]
            : ""

    property real ramUsage: 0.0
    property real ramTotal: 0
    property real ramUsed: 0
    property real ramAvailable: 0

    property var gpuUsages: []
    property var gpuVendors: []
    property var gpuNames: []
    property int gpuCount: 0
    property bool gpuDetected: false
    property var gpuTemps: []

    property var gpuDevices: []

    property var nvidiaPciIds: []
    property int nvidiaDiscoveryIndex: -1
    property var discoveredNvidiaGpus: []
    property bool nvidiaDiscoveryDone: false

    property string currentNvidiaInfoPath:
        nvidiaDiscoveryIndex >= 0
        && nvidiaDiscoveryIndex < nvidiaPciIds.length
            ? "/proc/driver/nvidia/gpus/"
                + nvidiaPciIds[nvidiaDiscoveryIndex]
                + "/information"
            : ""

    property var drmCards: []
    property int drmDiscoveryIndex: -1
    property var discoveredDrmGpus: []
    property bool drmDiscoveryDone: false

    property string currentDrmVendorPath:
        drmDiscoveryIndex >= 0
        && drmDiscoveryIndex < drmCards.length
            ? "/sys/class/drm/"
                + drmCards[drmDiscoveryIndex]
                + "/device/vendor"
            : ""

    property var amdTempDiscoveryIndices: []
    property int amdTempDiscoveryCursor: -1

    property bool gpuPollBusy: false
    property int gpuPollIndex: -1
    property var pendingGpuUsages: []
    property var pendingGpuTemps: []

    property string gpuRuntimeStatusPath: ""
    property string amdGpuUsagePath: ""
    property string amdGpuTempPath: ""

    property real gpuUsage: gpuUsages.length > 0 ? gpuUsages[0] : 0.0
    property string gpuVendor: gpuVendors.length > 0 ? gpuVendors[0] : "unknown"
    property int gpuTemp: gpuTemps.length > 0 ? gpuTemps[0] : -1

    property var diskUsage: ({})
    property var diskTypes: ({})
    property var validDisks: []

    property int diskTypeIndex: -1
    property var pendingDiskTypes: ({})
    property string currentDiskSource: ""

    property var cpuHistory: []
    property var ramHistory: []
    property var gpuHistories: []
    property var cpuTempHistory: []
    property var gpuTempHistories: []

    property int maxHistoryPoints: 50
    property int totalDataPoints: 0

    property int updateInterval: 2000

    property bool configReady: Config.initialLoadComplete

    property bool monitoring:
        GlobalStates.dashboardOpen
        && GlobalStates.dashboardCurrentTab === 2
        && validDisks.length > 0

    FileView {
        id: cpuInfoFile
        path: "/proc/cpuinfo"

        onLoaded: {
            root.parseCpuInfo(text());
        }
    }

    FileView {
        id: cpuStatFile
        path: "/proc/stat"

        onLoaded: {
            root.parseCpuStat(text());
        }
    }

    FileView {
        id: memInfoFile
        path: "/proc/meminfo"

        onLoaded: {
            root.parseMemInfo(text());
        }
    }

    FileView {
        id: cpuTempFile
        path: root.cpuTempPath

        onLoaded: {
            root.parseCpuTemp(text());
        }

        onLoadFailed: {
            if (root.cpuTempPath !== "")
                root.cpuTemp = -1;
        }
    }

    Process {
        id: cpuHwmonListProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleCpuHwmonList(text);
            }
        }
    }

    FileView {
        id: cpuHwmonNameProbe
        path: root.currentCpuHwmonNamePath

        onLoaded: {
            if (root.cpuTempDiscovering)
                root.handleCpuHwmonName(text());
        }

        onLoadFailed: {
            if (root.cpuTempDiscovering)
                root.advanceCpuHwmon();
        }
    }

    Process {
        id: cpuTempCandidateListProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleCpuTempCandidateList(text);
            }
        }
    }

    FileView {
        id: cpuTempCandidateProbe
        path: root.currentCpuTempCandidatePath

        onLoaded: {
            if (root.cpuTempDiscovering)
                root.handleCpuTempCandidate(text());
        }

        onLoadFailed: {
            if (root.cpuTempDiscovering)
                root.advanceCpuTempCandidate();
        }
    }

    Process {
        id: nvidiaGpuListProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleNvidiaGpuList(text);
            }
        }
    }

    Process {
        id: drmGpuListProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleDrmGpuList(text);
            }
        }
    }

    FileView {
        id: nvidiaInfoProbe
        path: root.currentNvidiaInfoPath

        onLoaded: {
            root.handleNvidiaInfo(text());
        }

        onLoadFailed: {
            root.handleNvidiaInfo("");
        }
    }

    FileView {
        id: drmVendorProbe
        path: root.currentDrmVendorPath

        onLoaded: {
            root.handleDrmVendor(text());
        }

        onLoadFailed: {
            root.advanceDrmGpu();
        }
    }

    Process {
        id: amdTempPathProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleAmdTempPath(text);
            }
        }
    }

    FileView {
        id: nvidiaRuntimeStatusFile
        path: root.gpuRuntimeStatusPath

        onLoaded: {
            root.handleNvidiaRuntimeStatus(text());
        }

        onLoadFailed: {
            if (root.gpuPollBusy)
                root.runNvidiaStats();
        }
    }

    Process {
        id: nvidiaStatsProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleNvidiaStats(text);
            }
        }
    }

    FileView {
        id: amdGpuUsageFile
        path: root.amdGpuUsagePath

        onLoaded: {
            root.handleAmdGpuUsage(text());
        }

        onLoadFailed: {
            if (root.gpuPollBusy)
                root.handleAmdGpuUsage("");
        }
    }

    FileView {
        id: amdGpuTempFile
        path: root.amdGpuTempPath

        onLoaded: {
            root.handleAmdGpuTemp(text());
        }

        onLoadFailed: {
            if (root.gpuPollBusy)
                root.handleAmdGpuTemp("");
        }
    }

    Process {
        id: diskStatsProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseDiskStats(text);
            }
        }
    }

    Process {
        id: diskSourceProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleDiskSource(text);
            }
        }
    }

    Process {
        id: diskRotationalProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleDiskRotational(text);
            }
        }
    }

    Timer {
        id: monitorTimer

        interval: root.updateInterval
        repeat: true
        running: root.monitoring

        onTriggered: {
            root.updateHistory();
            root.poll();
        }
    }

    Component.onCompleted: {
        validateDisks();
        detectCpuTemp();
        detectGpus();
    }

    Connections {
        target: Config.system

        function onDisksChanged() {
            root.validateDisks();
        }
    }

    onConfigReadyChanged: {
        if (configReady)
            validateDisks();
    }

    onValidDisksChanged: {
        detectDiskTypes();

        if (monitoring)
            pollDisks();
    }

    onMonitoringChanged: {
        if (monitoring)
            poll();
    }

    function nonEmptyLines(data) {
        const result = [];
        const lines = String(data || "").split("\n");

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();

            if (line !== "")
                result.push(line);
        }

        return result;
    }

    function loadFile(file, path) {
        if (!path)
            return;

        if (file.path === path)
            file.reload();
        else
            file.path = path;
    }

    function poll() {
        cpuStatFile.reload();
        memInfoFile.reload();

        if (cpuTempPath !== "")
            cpuTempFile.reload();

        pollDisks();

        if (gpuDetected)
            pollGpus();
    }

    function pollDisks() {
        if (validDisks.length === 0)
            return;

        diskStatsProcess.exec(
            [
                "df",
                "-B1",
                "--output=size,avail",
                "--"
            ].concat(validDisks)
        );
    }

    function parseCpuInfo(data) {
        if (!data)
            return;

        const lines = data.split("\n");

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];

            if (!line.startsWith("model name"))
                continue;

            const separator = line.indexOf(":");

            if (separator < 0)
                continue;

            let model = line.substring(separator + 1).trim();

            model = model.replace(
                / (?:CPU|FPU|APU|Processor|Dual-Core|Quad-Core|Six-Core|Eight-Core|Ten-Core|[0-9]+-Core)$/i,
                ""
            );

            model = model.replace(/ w\/ Radeon.*$/i, "");
            model = model.replace(/ with Radeon.*$/i, "");
            model = model.replace(/ @.*$/, "");
            model = model.replace(/\s+/g, " ").trim();

            cpuModel = model !== "" ? model : "Unknown CPU";
            return;
        }

        cpuModel = "Unknown CPU";
    }

    function parseCpuStat(data) {
        if (!data)
            return;

        const line = data.split("\n")[0];

        if (!line || !line.startsWith("cpu "))
            return;

        const fields = line.trim().split(/\s+/);

        if (fields.length < 5)
            return;

        const values = [];

        for (let i = 1; i < fields.length; i++) {
            const value = Number(fields[i]);

            if (!Number.isFinite(value))
                return;

            values.push(value);
        }

        const idle =
            values[3]
            + (values.length > 4 ? values[4] : 0);

        let total = 0;

        for (let i = 0; i < values.length; i++)
            total += values[i];

        const diffIdle = idle - previousCpuIdle;
        const diffTotal = total - previousCpuTotal;

        previousCpuIdle = idle;
        previousCpuTotal = total;

        if (diffTotal <= 0) {
            cpuUsage = 0.0;
            return;
        }

        cpuUsage = Math.max(
            0.0,
            Math.min(
                100.0,
                ((diffTotal - diffIdle) * 100.0) / diffTotal
            )
        );
    }

    function detectCpuTemp() {
        cpuTemp = -1;
        cpuTempPath = "";
        cpuTempDiscovering = true;

        cpuHwmonNamePaths = [];
        cpuHwmonIndex = -1;

        cpuTempCandidatePaths = [];
        cpuTempCandidateIndex = -1;

        cpuHwmonListProcess.exec([
            "find",
            "-L",
            "/sys/class/hwmon",
            "-maxdepth",
            "2",
            "-type",
            "f",
            "-name",
            "name",
            "-print"
        ]);
    }

    function handleCpuHwmonList(data) {
        if (!cpuTempDiscovering)
            return;

        cpuHwmonNamePaths = nonEmptyLines(data);

        if (cpuHwmonNamePaths.length === 0) {
            finishCpuTempDiscovery();
            return;
        }

        cpuHwmonIndex = 0;
    }

    function handleCpuHwmonName(data) {
        if (!cpuTempDiscovering)
            return;

        if (cpuHwmonIndex < 0
                || cpuHwmonIndex >= cpuHwmonNamePaths.length)
            return;

        const name = String(data).trim();

        const supportedNames = [
            "coretemp",
            "k10temp",
            "zenpower",
            "cpu_thermal",
            "x86_pkg_temp",
            "amd_energy"
        ];

        if (supportedNames.indexOf(name) < 0) {
            advanceCpuHwmon();
            return;
        }

        const namePath = cpuHwmonNamePaths[cpuHwmonIndex];
        const separator = namePath.lastIndexOf("/");

        if (separator < 0) {
            advanceCpuHwmon();
            return;
        }

        const hwmonPath = namePath.substring(0, separator);

        cpuTempCandidateListProcess.exec([
            "find",
            "-L",
            hwmonPath,
            "-maxdepth",
            "1",
            "-type",
            "f",
            "-name",
            "temp*_input",
            "-print"
        ]);
    }

    function handleCpuTempCandidateList(data) {
        if (!cpuTempDiscovering)
            return;

        cpuTempCandidatePaths = nonEmptyLines(data);

        if (cpuTempCandidatePaths.length === 0) {
            advanceCpuHwmon();
            return;
        }

        cpuTempCandidateIndex = 0;
    }

    function handleCpuTempCandidate(data) {
        if (!cpuTempDiscovering)
            return;

        const value = Number(String(data).trim());

        if (Number.isFinite(value)
                && value > 10000
                && value < 120000) {
            const path =
                cpuTempCandidatePaths[cpuTempCandidateIndex];

            cpuTempPath = path;
            cpuTemp = Math.floor(value / 1000);
            cpuTempDiscovering = false;

            cpuHwmonNamePaths = [];
            cpuHwmonIndex = -1;
            cpuTempCandidatePaths = [];
            cpuTempCandidateIndex = -1;

            return;
        }

        advanceCpuTempCandidate();
    }

    function advanceCpuTempCandidate() {
        if (!cpuTempDiscovering)
            return;

        cpuTempCandidateIndex++;

        if (cpuTempCandidateIndex
                >= cpuTempCandidatePaths.length) {
            cpuTempCandidatePaths = [];
            cpuTempCandidateIndex = -1;
            advanceCpuHwmon();
        }
    }

    function advanceCpuHwmon() {
        if (!cpuTempDiscovering)
            return;

        cpuTempCandidatePaths = [];
        cpuTempCandidateIndex = -1;

        cpuHwmonIndex++;

        if (cpuHwmonIndex >= cpuHwmonNamePaths.length)
            finishCpuTempDiscovery();
    }

    function finishCpuTempDiscovery() {
        cpuTempDiscovering = false;
        cpuTemp = -1;
        cpuTempPath = "";

        cpuHwmonNamePaths = [];
        cpuHwmonIndex = -1;

        cpuTempCandidatePaths = [];
        cpuTempCandidateIndex = -1;
    }

    function parseCpuTemp(data) {
        const value = Number(String(data).trim());

        if (Number.isFinite(value)
                && value > 10000
                && value < 120000) {
            cpuTemp = Math.floor(value / 1000);
        } else {
            cpuTemp = -1;
        }
    }

    function parseMemInfo(data) {
        if (!data)
            return;

        const lines = data.split("\n");

        let total = 0;
        let available = 0;

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];

            if (line.startsWith("MemTotal:")) {
                const parts = line.trim().split(/\s+/);
                total = Number(parts[1]);
            } else if (line.startsWith("MemAvailable:")) {
                const parts = line.trim().split(/\s+/);
                available = Number(parts[1]);
            }

            if (total > 0 && available > 0)
                break;
        }

        if (total <= 0) {
            ramUsage = 0.0;
            ramTotal = 0;
            ramUsed = 0;
            ramAvailable = 0;
            return;
        }

        const used = total - available;

        ramTotal = total;
        ramAvailable = available;
        ramUsed = used;
        ramUsage = (used * 100.0) / total;
    }

    function detectGpus() {
        gpuDevices = [];

        discoveredNvidiaGpus = [];
        discoveredDrmGpus = [];

        nvidiaPciIds = [];
        drmCards = [];

        nvidiaDiscoveryIndex = -1;
        drmDiscoveryIndex = -1;

        nvidiaDiscoveryDone = false;
        drmDiscoveryDone = false;

        nvidiaGpuListProcess.exec(
            gpuDiscoveryCommand("nvidia")
        );

        drmGpuListProcess.exec(
            gpuDiscoveryCommand("drm")
        );
    }

    function gpuDiscoveryCommand(type) {
        if (type === "nvidia") {
            return [
                "ls",
                "-1",
                "/proc/driver/nvidia/gpus"
            ];
        }

        if (type === "drm") {
            return [
                "ls",
                "-1",
                "/sys/class/drm"
            ];
        }

        return [];
    }

    function handleNvidiaGpuList(data) {
        const lines = nonEmptyLines(data);
        const ids = [];

        for (let i = 0; i < lines.length; i++) {
            if (/^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/
                    .test(lines[i])) {
                ids.push(lines[i]);
            }
        }

        nvidiaPciIds = ids;

        if (ids.length === 0) {
            nvidiaDiscoveryDone = true;
            maybeFinishGpuDiscovery();
            return;
        }

        nvidiaDiscoveryIndex = 0;
    }

    function handleNvidiaInfo(data) {
        if (nvidiaDiscoveryIndex < 0
                || nvidiaDiscoveryIndex >= nvidiaPciIds.length)
            return;

        const pciId = nvidiaPciIds[nvidiaDiscoveryIndex];

        let name = "NVIDIA GPU";

        const lines = String(data || "").split("\n");

        for (let i = 0; i < lines.length; i++) {
            if (!lines[i].startsWith("Model:"))
                continue;

            const model =
                lines[i].substring("Model:".length).trim();

            if (model !== "")
                name = model;

            break;
        }

        const next = discoveredNvidiaGpus.slice();

        next.push({
            vendor: "nvidia",
            name: name,
            pciId: pciId,
            runtimePath:
                "/sys/bus/pci/devices/"
                + pciId
                + "/power/runtime_status",
            busyPath: "",
            tempPath: ""
        });

        discoveredNvidiaGpus = next;

        nvidiaDiscoveryIndex++;

        if (nvidiaDiscoveryIndex >= nvidiaPciIds.length) {
            nvidiaDiscoveryIndex = -1;
            nvidiaDiscoveryDone = true;
            maybeFinishGpuDiscovery();
        }
    }

    function handleDrmGpuList(data) {
        const lines = nonEmptyLines(data);
        const cards = [];

        for (let i = 0; i < lines.length; i++) {
            if (/^card[0-9]+$/.test(lines[i]))
                cards.push(lines[i]);
        }

        drmCards = cards;

        if (cards.length === 0) {
            drmDiscoveryDone = true;
            maybeFinishGpuDiscovery();
            return;
        }

        drmDiscoveryIndex = 0;
    }

    function handleDrmVendor(data) {
        if (drmDiscoveryIndex < 0
                || drmDiscoveryIndex >= drmCards.length)
            return;

        const card = drmCards[drmDiscoveryIndex];
        const vendorId = String(data).trim().toLowerCase();

        let device = null;

        if (vendorId === "0x1002") {
            device = {
                vendor: "amd",
                name: "AMD GPU " + card.substring(4),
                pciId: "",
                card: card,
                runtimePath: "",
                busyPath:
                    "/sys/class/drm/"
                    + card
                    + "/device/gpu_busy_percent",
                tempPath: ""
            };
        } else if (vendorId === "0x8086") {
            device = {
                vendor: "intel",
                name: "Intel GPU " + card.substring(4),
                pciId: "",
                card: card,
                runtimePath: "",
                busyPath: "",
                tempPath: ""
            };
        }

        if (device !== null) {
            const next = discoveredDrmGpus.slice();
            next.push(device);
            discoveredDrmGpus = next;
        }

        advanceDrmGpu();
    }

    function advanceDrmGpu() {
        if (drmDiscoveryIndex < 0)
            return;

        drmDiscoveryIndex++;

        if (drmDiscoveryIndex >= drmCards.length) {
            drmDiscoveryIndex = -1;
            drmDiscoveryDone = true;
            maybeFinishGpuDiscovery();
        }
    }

    function maybeFinishGpuDiscovery() {
        if (!nvidiaDiscoveryDone || !drmDiscoveryDone)
            return;

        gpuDevices =
            discoveredNvidiaGpus.concat(discoveredDrmGpus);

        const names = [];
        const vendors = [];
        const usages = [];
        const temps = [];

        for (let i = 0; i < gpuDevices.length; i++) {
            names.push(gpuDevices[i].name);
            vendors.push(gpuDevices[i].vendor);
            usages.push(0.0);
            temps.push(-1);
        }

        gpuNames = names;
        gpuVendors = vendors;
        gpuUsages = usages;
        gpuTemps = temps;

        gpuCount = gpuDevices.length;
        gpuDetected = gpuCount > 0;

        discoverAmdTempPaths();
    }

    function discoverAmdTempPaths() {
        const indices = [];

        for (let i = 0; i < gpuDevices.length; i++) {
            if (gpuDevices[i].vendor === "amd")
                indices.push(i);
        }

        amdTempDiscoveryIndices = indices;

        if (indices.length === 0) {
            amdTempDiscoveryCursor = -1;

            if (monitoring && gpuDetected)
                pollGpus();

            return;
        }

        amdTempDiscoveryCursor = 0;
        discoverNextAmdTempPath();
    }

    function discoverNextAmdTempPath() {
        if (amdTempDiscoveryCursor < 0
                || amdTempDiscoveryCursor
                    >= amdTempDiscoveryIndices.length) {
            amdTempDiscoveryCursor = -1;

            if (monitoring && gpuDetected)
                pollGpus();

            return;
        }

        const gpuIndex =
            amdTempDiscoveryIndices[amdTempDiscoveryCursor];

        const gpu = gpuDevices[gpuIndex];

        amdTempPathProcess.exec([
            "find",
            "-L",
            "/sys/class/drm/"
                + gpu.card
                + "/device/hwmon",
            "-maxdepth",
            "2",
            "-type",
            "f",
            "-name",
            "temp1_input",
            "-print",
            "-quit"
        ]);
    }

    function handleAmdTempPath(data) {
        if (amdTempDiscoveryCursor < 0
                || amdTempDiscoveryCursor
                    >= amdTempDiscoveryIndices.length)
            return;

        const gpuIndex =
            amdTempDiscoveryIndices[amdTempDiscoveryCursor];

        const paths = nonEmptyLines(data);
        const tempPath =
            paths.length > 0 ? paths[0] : "";

        const devices = gpuDevices.slice();
        const original = devices[gpuIndex];

        devices[gpuIndex] = {
            vendor: original.vendor,
            name: original.name,
            pciId: original.pciId || "",
            card: original.card || "",
            runtimePath: original.runtimePath || "",
            busyPath: original.busyPath || "",
            tempPath: tempPath
        };

        gpuDevices = devices;

        amdTempDiscoveryCursor++;

        Qt.callLater(() => {
            root.discoverNextAmdTempPath();
        });
    }

    function pollGpus() {
        if (!gpuDetected
                || gpuDevices.length === 0
                || gpuPollBusy)
            return;

        const usages = [];
        const temps = [];

        for (let i = 0; i < gpuDevices.length; i++) {
            usages.push(0.0);
            temps.push(-1);
        }

        pendingGpuUsages = usages;
        pendingGpuTemps = temps;

        gpuPollBusy = true;
        gpuPollIndex = 0;

        pollCurrentGpu();
    }

    function pollCurrentGpu() {
        if (!gpuPollBusy)
            return;

        if (gpuPollIndex < 0
                || gpuPollIndex >= gpuDevices.length) {
            finishGpuPoll();
            return;
        }

        const gpu = gpuDevices[gpuPollIndex];

        if (gpu.vendor === "nvidia") {
            if (gpu.runtimePath !== "") {
                gpuRuntimeStatusPath = gpu.runtimePath;

                loadFile(
                    nvidiaRuntimeStatusFile,
                    gpu.runtimePath
                );
            } else {
                runNvidiaStats();
            }

            return;
        }

        if (gpu.vendor === "amd") {
            if (gpu.busyPath !== "") {
                amdGpuUsagePath = gpu.busyPath;

                loadFile(
                    amdGpuUsageFile,
                    gpu.busyPath
                );
            } else {
                pollAmdTemperature();
            }

            return;
        }

        pendingGpuUsages[gpuPollIndex] = 0.0;
        pendingGpuTemps[gpuPollIndex] = -1;

        advanceGpuPoll();
    }

    function handleNvidiaRuntimeStatus(data) {
        if (!gpuPollBusy)
            return;

        const state = String(data).trim();

        if (state === "active") {
            runNvidiaStats();
        } else {
            pendingGpuUsages[gpuPollIndex] = 0.0;
            pendingGpuTemps[gpuPollIndex] = -1;

            advanceGpuPoll();
        }
    }

    function runNvidiaStats() {
        if (!gpuPollBusy
                || gpuPollIndex < 0
                || gpuPollIndex >= gpuDevices.length)
            return;

        const gpu = gpuDevices[gpuPollIndex];
        const command = gpuPollCommand(gpu);

        if (command.length === 0) {
            advanceGpuPoll();
            return;
        }

        nvidiaStatsProcess.exec(command);
    }

    function gpuPollCommand(gpu) {
        if (!gpu || gpu.vendor !== "nvidia")
            return [];

        return [
            "nvidia-smi",
            "-i",
            gpu.pciId,
            "--query-gpu=utilization.gpu,temperature.gpu",
            "--format=csv,noheader,nounits"
        ];
    }

    function handleNvidiaStats(data) {
        if (!gpuPollBusy)
            return;

        let usage = 0.0;
        let temp = -1;

        const lines = nonEmptyLines(data);

        if (lines.length > 0) {
            const parts = lines[0].split(",");

            if (parts.length >= 1) {
                const parsedUsage = Number(parts[0].trim());

                if (Number.isFinite(parsedUsage))
                    usage = parsedUsage;
            }

            if (parts.length >= 2) {
                const parsedTemp = Number(parts[1].trim());

                if (Number.isFinite(parsedTemp))
                    temp = Math.trunc(parsedTemp);
            }
        }

        pendingGpuUsages[gpuPollIndex] = usage;
        pendingGpuTemps[gpuPollIndex] = temp;

        advanceGpuPoll();
    }

    function handleAmdGpuUsage(data) {
        if (!gpuPollBusy)
            return;

        let usage = Number(String(data).trim());

        if (!Number.isFinite(usage))
            usage = 0.0;

        pendingGpuUsages[gpuPollIndex] = usage;

        pollAmdTemperature();
    }

    function pollAmdTemperature() {
        if (!gpuPollBusy
                || gpuPollIndex < 0
                || gpuPollIndex >= gpuDevices.length)
            return;

        const gpu = gpuDevices[gpuPollIndex];

        if (gpu.tempPath) {
            amdGpuTempPath = gpu.tempPath;

            loadFile(
                amdGpuTempFile,
                gpu.tempPath
            );
        } else {
            pendingGpuTemps[gpuPollIndex] = -1;
            advanceGpuPoll();
        }
    }

    function handleAmdGpuTemp(data) {
        if (!gpuPollBusy)
            return;

        const value = Number(String(data).trim());

        if (Number.isFinite(value))
            pendingGpuTemps[gpuPollIndex] =
                Math.trunc(value / 1000);
        else
            pendingGpuTemps[gpuPollIndex] = -1;

        advanceGpuPoll();
    }

    function advanceGpuPoll() {
        if (!gpuPollBusy)
            return;

        gpuPollIndex++;

        if (gpuPollIndex >= gpuDevices.length) {
            finishGpuPoll();
            return;
        }

        Qt.callLater(() => {
            root.pollCurrentGpu();
        });
    }

    function finishGpuPoll() {
        gpuUsages = pendingGpuUsages.slice();
        gpuTemps = pendingGpuTemps.slice();

        gpuPollIndex = -1;
        gpuPollBusy = false;
    }

    function validateDisks() {
        const configuredDisks =
            Config.system.disks || ["/"];

        let newValidDisks = [];

        for (let i = 0; i < configuredDisks.length; i++) {
            const disk = configuredDisks[i];

            if (disk
                    && typeof disk === "string"
                    && disk.trim() !== "") {
                newValidDisks.push(disk.trim());
            }
        }

        if (newValidDisks.length === 0)
            newValidDisks = ["/"];

        validDisks = newValidDisks;
    }

    function parseDiskStats(data) {
        const lines =
            String(data).trim().split("\n");

        const result = {};

        let diskIndex = 0;

        for (let i = 1;
             i < lines.length
             && diskIndex < validDisks.length;
             i++) {
            const line = lines[i].trim();

            if (line === "")
                continue;

            const match =
                line.match(/^(\d+)\s+(\d+)$/);

            if (!match) {
                result[validDisks[diskIndex]] = 0.0;
                diskIndex++;
                continue;
            }

            const total = Number(match[1]);
            const available = Number(match[2]);

            let usage = 0.0;

            if (total > 0) {
                const used = total - available;
                usage = (used / total) * 100.0;
            }

            result[validDisks[diskIndex]] = usage;
            diskIndex++;
        }

        while (diskIndex < validDisks.length) {
            result[validDisks[diskIndex]] = 0.0;
            diskIndex++;
        }

        diskUsage = result;
    }

    function detectDiskTypes() {
        const types = {};

        for (let i = 0; i < validDisks.length; i++)
            types[validDisks[i]] = "unknown";

        pendingDiskTypes = types;
        currentDiskSource = "";

        if (validDisks.length === 0) {
            diskTypes = types;
            diskTypeIndex = -1;
            return;
        }

        diskTypeIndex = 0;
        detectCurrentDiskSource();
    }

    function detectCurrentDiskSource() {
        if (diskTypeIndex < 0
                || diskTypeIndex >= validDisks.length) {
            finishDiskTypeDetection();
            return;
        }

        diskSourceProcess.exec([
            "findmnt",
            "-n",
            "-o",
            "SOURCE",
            "--target",
            validDisks[diskTypeIndex]
        ]);
    }

    function handleDiskSource(data) {
        if (diskTypeIndex < 0
                || diskTypeIndex >= validDisks.length)
            return;

        const lines = nonEmptyLines(data);

        if (lines.length === 0) {
            advanceDiskTypeDetection();
            return;
        }

        let source = lines[0];

        const bracket = source.indexOf("[");

        if (bracket >= 0)
            source = source.substring(0, bracket);

        source = source.trim();
        currentDiskSource = source;

        if (!source.startsWith("/dev/")) {
            advanceDiskTypeDetection();
            return;
        }

        diskRotationalProcess.exec([
            "lsblk",
            "-n",
            "-d",
            "-o",
            "ROTA",
            source
        ]);
    }

    function handleDiskRotational(data) {
        if (diskTypeIndex < 0
                || diskTypeIndex >= validDisks.length)
            return;

        const lines = nonEmptyLines(data);

        let type = "unknown";

        if (lines.length > 0) {
            const value = lines[0].trim();

            if (value === "0")
                type = "ssd";
            else if (value === "1")
                type = "hdd";
        }

        const mount = validDisks[diskTypeIndex];

        pendingDiskTypes[mount] = type;

        advanceDiskTypeDetection();
    }

    function advanceDiskTypeDetection() {
        diskTypeIndex++;
        currentDiskSource = "";

        if (diskTypeIndex >= validDisks.length) {
            finishDiskTypeDetection();
            return;
        }

        Qt.callLater(() => {
            root.detectCurrentDiskSource();
        });
    }

    function finishDiskTypeDetection() {
        const result = {};

        for (let i = 0; i < validDisks.length; i++) {
            const mount = validDisks[i];

            result[mount] =
                pendingDiskTypes[mount] || "unknown";
        }

        diskTypes = result;

        diskTypeIndex = -1;
        currentDiskSource = "";
    }

    function updateHistory() {
        totalDataPoints++;

        const pushHistory = (arr, value) => {
            let next = arr.slice();

            next.push(value);

            if (next.length > maxHistoryPoints)
                next.shift();

            return next;
        };

        cpuHistory = pushHistory(
            cpuHistory,
            cpuUsage / 100
        );

        cpuTempHistory = pushHistory(
            cpuTempHistory,
            cpuTemp
        );

        ramHistory = pushHistory(
            ramHistory,
            ramUsage / 100
        );

        if (gpuDetected && gpuCount > 0) {
            let newGpuHistories =
                gpuHistories.slice();

            let newGpuTempHistories =
                gpuTempHistories.slice();

            while (newGpuHistories.length < gpuCount)
                newGpuHistories.push([]);

            while (newGpuTempHistories.length < gpuCount)
                newGpuTempHistories.push([]);

            for (let i = 0; i < gpuCount; i++) {
                newGpuHistories[i] = pushHistory(
                    newGpuHistories[i],
                    (gpuUsages[i] || 0) / 100
                );

                newGpuTempHistories[i] = pushHistory(
                    newGpuTempHistories[i],
                    gpuTemps[i] ?? -1
                );
            }

            gpuHistories = newGpuHistories;
            gpuTempHistories = newGpuTempHistories;
        }
    }
}
