import QtQuick
import QtCore

import Quickshell
import Quickshell.Io

import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.modules.services

ActionGrid {
    id: root

    signal itemSelected

    QtObject {
        id: recordAction

        property string icon: ScreenRecorder.isRecording
            ? Icons.stop
            : Icons.recordScreen

        property string text: ScreenRecorder.isRecording
            ? ScreenRecorder.duration
            : ""

        property string tooltip: ScreenRecorder.isRecording
            ? "Stop Recording"
            : "Screen Recorder"

        property string command: ""

        property string variant: ScreenRecorder.isRecording
            ? "error"
            : "primary"

        property string type: "button"
    }

    QtObject {
        id: motionCueAction

        property string icon: MotionCues.enabled
            ? Icons.waveform
            : Icons.dotsNine

        property string text: MotionCues.enabled
            ? "On"
            : ""

        property string tooltip: MotionCues.enabled
            ? "Disable Motion Cues"
            : "Enable Motion Cues"

        property string command: ""
        property string variant: MotionCues.enabled ? "primary" : ""
        property string type: "button"
    }

    layout: "row"
    buttonSize: 48
    iconSize: 20
    spacing: 8

    actions: [
        {
            icon: Icons.camera,
            tooltip: "Screenshot",
            command: ""
        },
        {
            icon: Icons.screenshots,
            tooltip: "Open Screenshots",
            command: ""
        },
        {
            type: "separator"
        },
        recordAction,
        {
            icon: Icons.recordings,
            tooltip: "Open Recordings",
            command: ""
        },
        {
            type: "separator"
        },
        {
            icon: Icons.picker,
            tooltip: "Color Picker",
            command: ""
        },
        {
            icon: Icons.textT,
            tooltip: "OCR",
            command: ""
        },
        {
            icon: Icons.qrCode,
            tooltip: "QR Code",
            command: ""
        },
        {
            icon: Icons.google,
            tooltip: "Google Lens",
            command: ""
        },
        {
            icon: GlobalStates.mirrorWindowVisible
                ? Icons.webcamSlash
                : Icons.webcam,

            tooltip: "Mirror",
            command: ""
        },
        motionCueAction
    ]

    function localPath(url) {
        var path = url.toString();

        if (path.startsWith("file://"))
            path = path.substring(7);

        return decodeURIComponent(path);
    }

    function openUserFolder(location, subdirectory) {
        var base = localPath(
            StandardPaths.writableLocation(location)
        );

        if (base === "") {
            console.warn("Could not resolve user directory");
            return;
        }

        var path = base + "/" + subdirectory;

        folderProc.targetPath = path;
        folderProc.exec([
            "mkdir",
            "-p",
            path
        ]);
    }

    Process {
        id: folderProc

        property string targetPath: ""

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(
                    "Failed to create directory:",
                    targetPath
                );

                return;
            }

            Quickshell.execDetached([
                "xdg-open",
                targetPath
            ]);
        }
    }

    onActionTriggered: action => {
        console.log(
            "Tools action triggered:",
            action.tooltip
        );

        if (action.tooltip === "Screenshot") {
            Screenshot.initialize();
            GlobalStates.screenshotToolVisible = true;
            root.itemSelected();

        } else if (action.tooltip === "Screen Recorder") {
            ScreenRecorder.initialize();
            GlobalStates.screenRecordToolVisible = true;
            root.itemSelected();

        } else if (action.tooltip === "Stop Recording") {
            ScreenRecorder.toggleRecording();
            root.itemSelected();

        } else if (action.tooltip === "Open Screenshots") {
            root.openUserFolder(
                StandardPaths.PicturesLocation,
                "Screenshots"
            );

            root.itemSelected();

        } else if (action.tooltip === "Open Recordings") {
            root.openUserFolder(
                StandardPaths.MoviesLocation,
                "Recordings"
            );

            root.itemSelected();

        } else if (action.tooltip === "Color Picker") {
            ColorPicker.pick();
            root.itemSelected();

        } else if (action.tooltip === "OCR") {
            root.itemSelected();
            OCRService.scan();

        } else if (action.tooltip === "QR Code") {
            root.itemSelected();
            QRService.scan();

        } else if (action.tooltip === "Google Lens") {
            Screenshot.captureMode = "lens";
            GlobalStates.screenshotToolVisible = true;
            root.itemSelected();

        } else if (action.tooltip === "Mirror") {
            GlobalStates.mirrorWindowVisible =
                !GlobalStates.mirrorWindowVisible;

        } else if (
            action.tooltip === "Enable Motion Cues"
            || action.tooltip === "Disable Motion Cues"
        ) {
            MotionCues.toggle();
        }
    }
}
