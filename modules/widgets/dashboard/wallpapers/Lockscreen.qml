import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: lockscreen

    readonly property string cacheDir: Quickshell.cachePath("lockscreen")

    property string pendingWallpaper: ""
    property string inputPath: ""
    property string outputPath: ""
    property bool frameTimedOut: false

    function getFileType(path) {
        var extension = path.toLowerCase().split(".").pop();

        if (["jpg", "jpeg", "png", "webp", "tif", "tiff", "bmp"].includes(extension))
            return "image";

        if (extension === "gif")
            return "gif";

        if (["mp4", "webm", "mov", "avi", "mkv"].includes(extension))
            return "video";

        return "unknown";
    }

    function getFramePath(filePath) {
        if (!filePath)
            return "";

        var fileType = getFileType(filePath);

        if (fileType === "image")
            return filePath;

        if (fileType === "video" || fileType === "gif") {
            var fileName = filePath.split("/").pop();
            return cacheDir + "/" + fileName + ".jpg";
        }

        return filePath;
    }

    function selectPendingWallpaper() {
        if (!pendingWallpaper)
            return false;

        inputPath = pendingWallpaper;
        pendingWallpaper = "";
        outputPath = getFramePath(inputPath);

        return true;
    }

    function beginGeneration() {
        if (!pendingWallpaper)
            return;

        if (lockscreenMkdirProcess.running
                || lockscreenCleanupProcess.running
                || lockscreenFrameProcess.running) {
            return;
        }

        if (!selectPendingWallpaper())
            return;

        console.log("Preparing lockscreen frame for:", inputPath);

        lockscreenMkdirProcess.exec([
            "mkdir",
            "-p",
            cacheDir
        ]);
    }

    function generate(filePath) {
        if (!filePath) {
            console.warn("Lockscreen.generate: empty filePath");
            return;
        }

        var fileType = getFileType(filePath);

        if (fileType === "image") {
            console.log(
                "Lockscreen wallpaper is a static image; no extraction needed"
            );
            return;
        }

        if (fileType !== "video" && fileType !== "gif") {
            console.warn(
                "Unsupported lockscreen wallpaper type:",
                filePath
            );
            return;
        }

        pendingWallpaper = filePath;
        beginGeneration();
    }

    Process {
        id: lockscreenMkdirProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.warn(
                    "Failed to create lockscreen cache directory, code:",
                    exitCode
                );

                Qt.callLater(function() {
                    lockscreen.beginGeneration();
                });
                return;
            }

            lockscreenCleanupProcess.exec([
                "find",
                lockscreen.cacheDir,
                "-mindepth", "1",
                "-maxdepth", "1",
                "-type", "f",
                "-delete"
            ]);
        }
    }

    Process {
        id: lockscreenCleanupProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.warn(
                    "Failed to fully clean lockscreen cache, code:",
                    exitCode
                );
            }

            lockscreen.selectPendingWallpaper();

            if (!lockscreen.inputPath || !lockscreen.outputPath)
                return;

            console.log(
                "Extracting lockscreen frame:",
                lockscreen.inputPath,
                "->",
                lockscreen.outputPath
            );

            lockscreen.frameTimedOut = false;
            lockscreenFrameTimeout.restart();

            lockscreenFrameProcess.exec([
                "ffmpeg",
                "-hide_banner",
                "-loglevel", "error",
                "-nostdin",
                "-y",
                "-i", lockscreen.inputPath,
                "-map", "0:v:0",
                "-frames:v", "1",
                "-q:v", "2",
                "-f", "image2",
                lockscreen.outputPath
            ]);
        }
    }

    Timer {
        id: lockscreenFrameTimeout
        interval: 30000
        repeat: false

        onTriggered: {
            if (lockscreenFrameProcess.running) {
                console.warn("Lockscreen frame extraction timed out");
                lockscreen.frameTimedOut = true;
                lockscreenFrameProcess.running = false;
            }
        }
    }

    Process {
        id: lockscreenFrameProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                var message = text.trim();

                if (message.length > 0)
                    console.warn("Lockscreen FFmpeg error:", message);
            }
        }

        onExited: function(exitCode) {
            lockscreenFrameTimeout.stop();

            if (lockscreen.frameTimedOut) {
                console.warn(
                    "Lockscreen wallpaper extraction failed: timeout"
                );
            } else if (exitCode === 0) {
                console.log(
                    "Lockscreen wallpaper ready:",
                    lockscreen.outputPath
                );
            } else {
                console.warn(
                    "Lockscreen wallpaper extraction failed, code:",
                    exitCode
                );
            }

            lockscreen.inputPath = "";
            lockscreen.outputPath = "";
            lockscreen.frameTimedOut = false;

            Qt.callLater(function() {
                lockscreen.beginGeneration();
            });
        }
    }
}
