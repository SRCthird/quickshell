import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: thumbnail

    property var wallpaperPaths: []
    property string wallpaperDir: ""
    property string fallbackDir: ""

    property int version: 0

    property var thumbnailQueue: []
    property bool thumbnailBatchActive: false
    property bool thumbnailRerunRequested: false
    property int thumbnailTotal: 0
    property int thumbnailCompleted: 0
    property int thumbnailGenerated: 0
    property int thumbnailFailed: 0
    property string thumbnailSource: ""
    property string thumbnailOutput: ""
    property string thumbnailFileType: ""
    property bool thumbnailTimedOut: false

    readonly property string thumbnailVideoFilter:
        "scale=140:140:force_original_aspect_ratio=increase,crop=140:140"

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

    function getParentDirectory(filePath) {
        var separator = filePath.lastIndexOf("/");

        if (separator <= 0)
            return ".";

        return filePath.substring(0, separator);
    }

    function pathIsInside(filePath, directory) {
        if (!filePath || !directory)
            return false;

        var root = directory.endsWith("/")
            ? directory.slice(0, -1)
            : directory;

        return filePath === root || filePath.startsWith(root + "/");
    }

    function getThumbnailSourceRoot(filePath) {
        if (pathIsInside(filePath, wallpaperDir))
            return wallpaperDir;

        if (pathIsInside(filePath, fallbackDir))
            return fallbackDir;

        return "";
    }

    function getThumbnailPath(filePath) {
        var sourceRoot = getThumbnailSourceRoot(filePath);
        var relativePath;

        if (sourceRoot) {
            var normalizedRoot = sourceRoot.endsWith("/")
                ? sourceRoot.slice(0, -1)
                : sourceRoot;

            relativePath = filePath.substring(normalizedRoot.length);

            while (relativePath.startsWith("/"))
                relativePath = relativePath.substring(1);
        } else {
            relativePath = filePath.split("/").pop();
        }

        var pathParts = relativePath.split("/");
        var fileName = pathParts.pop();
        var thumbnailName = fileName + ".jpg";
        var relativeDir = pathParts.join("/");

        if (relativeDir) {
            return Quickshell.cachePath(
                "thumbnails/" + relativeDir + "/" + thumbnailName
            );
        }

        return Quickshell.cachePath("thumbnails/" + thumbnailName);
    }

    function scheduleGeneration() {
        if (delayedThumbnailGen.running)
            delayedThumbnailGen.restart();
        else
            delayedThumbnailGen.start();
    }

    function requestGeneration() {
        if (thumbnailBatchActive) {
            thumbnailRerunRequested = true;
            return;
        }

        var files = wallpaperPaths.filter(function(filePath) {
            var fileType = getFileType(filePath);

            return fileType === "image"
                || fileType === "gif"
                || fileType === "video";
        });

        thumbnailQueue = files.slice();
        thumbnailTotal = files.length;
        thumbnailCompleted = 0;
        thumbnailGenerated = 0;
        thumbnailFailed = 0;
        thumbnailRerunRequested = false;

        if (thumbnailTotal === 0) {
            console.log("No media files found for thumbnail generation");
            return;
        }

        thumbnailBatchActive = true;

        console.log(
            "Checking",
            thumbnailTotal,
            "wallpaper thumbnails"
        );

        Qt.callLater(function() {
            thumbnail.processNextThumbnail();
        });
    }

    function processNextThumbnail() {
        if (!thumbnailBatchActive)
            return;

        if (thumbnailQueue.length === 0) {
            finishThumbnailBatch();
            return;
        }

        var queue = thumbnailQueue.slice();
        var nextSource = queue.shift();
        thumbnailQueue = queue;

        thumbnailSource = nextSource;
        thumbnailOutput = getThumbnailPath(nextSource);
        thumbnailFileType = getFileType(nextSource);
        thumbnailTimedOut = false;

        thumbnailFreshnessProcess.exec([
            "test",
            thumbnailSource,
            "-nt",
            thumbnailOutput
        ]);
    }

    function startThumbnailFfmpeg() {
        var command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel", "error",
            "-nostdin",
            "-y",
            "-i", thumbnailSource
        ];

        if (thumbnailFileType === "video")
            command.push("-ss", "00:00:01");

        command.push(
            "-map", "0:v:0",
            "-frames:v", "1",
            "-vf", thumbnailVideoFilter,
            "-q:v", "2",
            "-f", "image2",
            thumbnailOutput
        );

        thumbnailTimedOut = false;
        thumbnailTimeout.interval =
            thumbnailFileType === "video" ? 30000 : 15000;
        thumbnailTimeout.restart();

        console.log(
            "Generating thumbnail",
            thumbnailCompleted + 1,
            "of",
            thumbnailTotal,
            ":",
            thumbnailSource
        );

        thumbnailFfmpegProcess.exec(command);
    }

    function completeCurrentThumbnail(success, generated) {
        thumbnailCompleted++;

        if (generated)
            thumbnailGenerated++;

        if (!success)
            thumbnailFailed++;

        thumbnailSource = "";
        thumbnailOutput = "";
        thumbnailFileType = "";
        thumbnailTimedOut = false;

        Qt.callLater(function() {
            thumbnail.processNextThumbnail();
        });
    }

    function finishThumbnailBatch() {
        console.log(
            "Thumbnail generation complete:",
            thumbnailGenerated,
            "generated,",
            thumbnailTotal - thumbnailGenerated - thumbnailFailed,
            "already current,",
            thumbnailFailed,
            "failed"
        );

        if (thumbnailGenerated > 0)
            version++;

        var runAgain = thumbnailRerunRequested;

        thumbnailBatchActive = false;
        thumbnailRerunRequested = false;
        thumbnailQueue = [];
        thumbnailSource = "";
        thumbnailOutput = "";
        thumbnailFileType = "";

        if (runAgain) {
            Qt.callLater(function() {
                thumbnail.requestGeneration();
            });
        }
    }

    Process {
        id: thumbnailFreshnessProcess
        running: false

        onExited: function(exitCode) {
            if (!thumbnail.thumbnailBatchActive)
                return;

            if (exitCode === 0) {
                thumbnailMkdirProcess.exec([
                    "mkdir",
                    "-p",
                    thumbnail.getParentDirectory(
                        thumbnail.thumbnailOutput
                    )
                ]);
            } else if (exitCode === 1) {
                thumbnail.completeCurrentThumbnail(true, false);
            } else {
                console.warn(
                    "Failed to check thumbnail freshness for:",
                    thumbnail.thumbnailSource,
                    "code:",
                    exitCode
                );

                thumbnail.completeCurrentThumbnail(false, false);
            }
        }
    }

    Process {
        id: thumbnailMkdirProcess
        running: false

        onExited: function(exitCode) {
            if (!thumbnail.thumbnailBatchActive)
                return;

            if (exitCode !== 0) {
                console.warn(
                    "Failed to create thumbnail directory for:",
                    thumbnail.thumbnailOutput,
                    "code:",
                    exitCode
                );

                thumbnail.completeCurrentThumbnail(false, false);
                return;
            }

            thumbnail.startThumbnailFfmpeg();
        }
    }

    Timer {
        id: thumbnailTimeout
        interval: 15000
        repeat: false

        onTriggered: {
            if (thumbnailFfmpegProcess.running) {
                thumbnail.thumbnailTimedOut = true;

                console.warn(
                    "Thumbnail generation timed out for:",
                    thumbnail.thumbnailSource
                );

                thumbnailFfmpegProcess.running = false;
            }
        }
    }

    Process {
        id: thumbnailFfmpegProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                var message = text.trim();

                if (message.length > 0)
                    console.warn("Thumbnail FFmpeg error:", message);
            }
        }

        onExited: function(exitCode) {
            thumbnailTimeout.stop();

            if (!thumbnail.thumbnailBatchActive)
                return;

            if (thumbnail.thumbnailTimedOut) {
                thumbnail.completeCurrentThumbnail(false, false);
            } else if (exitCode === 0) {
                thumbnail.completeCurrentThumbnail(true, true);
            } else {
                console.warn(
                    "Thumbnail generation failed for:",
                    thumbnail.thumbnailSource,
                    "code:",
                    exitCode
                );

                thumbnail.completeCurrentThumbnail(false, false);
            }
        }
    }

    Timer {
        id: delayedThumbnailGen
        interval: 2000
        repeat: false

        onTriggered: thumbnail.requestGeneration()
    }
}
