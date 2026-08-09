pragma Singleton

import QtQuick
import QtCore

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool busy: false
    property string _capturePath: ""

    function hasExecutable(name) {
        return StandardPaths
            .findExecutable(name, [])
            .toString() !== "";
    }

    function notify(title, message, urgency, icon) {
        if (!hasExecutable("notify-send")) {
            console.log(title + ": " + message);
            return;
        }

        Quickshell.execDetached([
            "notify-send",
            "-u", urgency,
            "-i", icon,
            title,
            message
        ]);
    }

    function scan() {
        if (busy)
            return;

        busy = true;

        _capturePath = Quickshell.cachePath(
            "qr-"
            + Quickshell.processId
            + "-"
            + Date.now()
            + ".png"
        );

        RegionSelector.select("qr");
    }

    function finish() {
        busy = false;
    }

    Connections {
        target: RegionSelector

        function onSelected(purpose, geometry) {
            if (purpose !== "qr")
                return;

            console.log("QR region:", geometry);

            grimProc.exec([
                "grim",
                "-g", geometry,
                root._capturePath
            ]);
        }

        function onCancelled(purpose) {
            if (purpose !== "qr")
                return;

            root.finish();
        }
    }

    Process {
        id: grimProc

        stderr: StdioCollector {
            id: grimError
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error(
                    "QR grim failed:",
                    grimError.text
                );

                root.notify(
                    "QR Scan Error",
                    "Failed to capture selected region",
                    "critical",
                    "dialog-error"
                );

                root.finish();
                return;
            }

            zbarProc.exec([
                "zbarimg",
                "-q",
                "--raw",
                root._capturePath
            ]);
        }
    }

    Process {
        id: zbarProc

        stdout: StdioCollector {
            id: zbarOutput
        }

        stderr: StdioCollector {
            id: zbarError
        }

        onExited: (exitCode, exitStatus) => {
            var result = zbarOutput.text
                .replace(/[\r\n]+$/, "");

            if (result === "") {
                root.notify(
                    "QR/Barcode Result",
                    "No code detected",
                    "low",
                    "dialog-error"
                );

                root.finish();
                return;
            }

            Quickshell.clipboardText = result;

            root.notify(
                "QR/Barcode Result",
                "Content copied to clipboard",
                "normal",
                "qr-code"
            );

            root.finish();
        }
    }
}
