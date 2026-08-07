pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool busy: false

    property string hexColor: ""
    property string rgbColor: ""
    property string hsvColor: ""

    property string samplePath: ""
    property string previewPath: ""

    function hexComponent(value) {
        return ("0" + value.toString(16).toUpperCase()).slice(-2);
    }

    function rgbToHsv(r, g, b) {
        const rn = r / 255.0;
        const gn = g / 255.0;
        const bn = b / 255.0;

        const max = Math.max(rn, gn, bn);
        const min = Math.min(rn, gn, bn);
        const delta = max - min;

        let h = 0;

        if (delta !== 0) {
            if (max === rn) {
                h = 60 * (((gn - bn) / delta) % 6);
            } else if (max === gn) {
                h = 60 * (((bn - rn) / delta) + 2);
            } else {
                h = 60 * (((rn - gn) / delta) + 4);
            }
        }

        if (h < 0)
            h += 360;

        const s = max === 0 ? 0 : delta / max;
        const v = max;

        return "hsv("
            + Math.round(h) + ", "
            + Math.round(s * 100) + "%, "
            + Math.round(v * 100) + "%)";
    }

    function pick() {
        if (busy)
            return;

        busy = true;

        const id = Date.now();

        samplePath = "/tmp/quickshell-color-picker-" + id + ".ppm";
        previewPath = "/tmp/quickshell-color-picker-" + id + ".png";

        dependencyProc.exec([
            "bash",
            "-c",
            "for dep in grim slurp magick wl-copy notify-send; do "
                + "command -v \"$dep\" >/dev/null 2>&1 || { "
                + "printf '%s' \"$dep\"; "
                + "exit; "
                + "}; "
                + "done"
        ]);
    }

    function parseColor(output) {
        const parts = output.trim().split(/\s+/);

        if (parts.length !== 3) {
            fail("Failed to read selected color");
            return;
        }

        const r = parseInt(parts[0]);
        const g = parseInt(parts[1]);
        const b = parseInt(parts[2]);

        if (isNaN(r) || isNaN(g) || isNaN(b)) {
            fail("Failed to parse selected color");
            return;
        }

        hexColor = "#"
            + hexComponent(r)
            + hexComponent(g)
            + hexComponent(b);

        rgbColor = "rgb(" + r + ", " + g + ", " + b + ")";
        hsvColor = rgbToHsv(r, g, b);

        previewProc.exec([
            "magick",
            "-size",
            "64x64",
            "xc:" + hexColor,
            previewPath
        ]);
    }

    function fail(message) {
        console.warn("ColorPicker:", message);

        errorNotifyProc.exec([
            "notify-send",
            "Color Picker",
            message,
            "-u",
            "critical"
        ]);

        finish();
    }

    function finish() {
        busy = false;

        if (samplePath !== "") {
            sampleCleanupProc.exec([
                "rm",
                "-f",
                samplePath
            ]);
        }
    }

    Process {
        id: dependencyProc

        stdout: StdioCollector {
            onStreamFinished: {
                const missing = text.trim();

                if (missing === "") {
                    slurpProc.exec([
                        "slurp",
                        "-p"
                    ]);
                    return;
                }

                console.warn(
                    "ColorPicker: missing dependency:",
                    missing
                );

                if (missing !== "notify-send") {
                    errorNotifyProc.exec([
                        "notify-send",
                        "Color Picker",
                        "Missing dependency: " + missing,
                        "-u",
                        "critical"
                    ]);
                }

                root.finish();
            }
        }
    }

    Process {
        id: slurpProc

        stdout: StdioCollector {
            onStreamFinished: {
                const coords = text.trim();

                if (coords === "") {
                    root.finish();
                    return;
                }

                grimProc.exec([
                    "grim",
                    "-g",
                    coords,
                    "-t",
                    "ppm",
                    root.samplePath
                ]);
            }
        }
    }

    Process {
        id: grimProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.fail("Failed to capture selected color");
                return;
            }

            magickProc.exec([
                "magick",
                root.samplePath,
                "-format",
                "%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]",
                "info:-"
            ]);
        }
    }

    Process {
        id: magickProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseColor(text);

                sampleCleanupProc.exec([
                    "rm",
                    "-f",
                    root.samplePath
                ]);
            }
        }
    }

    Process {
        id: sampleCleanupProc
    }

    Process {
        id: previewProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.fail("Failed to create color preview");
                return;
            }

            initialCopyProc.exec([
                "wl-copy",
                "--",
                root.hexColor
            ]);
        }
    }

    function showNotification() {
        const session = notificationSession.createObject(root, {
            hex: root.hexColor,
            rgb: root.rgbColor,
            hsv: root.hsvColor,
            preview: root.previewPath
        });

        if (session === null) {
            console.warn(
                "ColorPicker: failed to create notification session:",
                notificationSession.errorString()
            );

            root.busy = false;
            return;
        }

        session.start();

        root.busy = false;
    }

    Process {
        id: initialCopyProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.fail("Failed to copy color to clipboard");
                return;
            }
        
            root.showNotification();
        }
    }

    Process {
        id: errorNotifyProc
    }

    Component {
        id: notificationSession

        Item {
            id: session

            visible: false

            required property string hex
            required property string rgb
            required property string hsv
            required property string preview

            property string selectedValue: ""
            property string selectedLabel: ""

            function start() {
                notificationProc.exec([
                    "notify-send",
                    "Color Picked",
                    hex + " copied to clipboard",
                    "-i",
                    preview,
                    "-a",
                    "ColorPicker",
                    "-u",
                    "normal",
                    "--action=hex=Copy HEX",
                    "--action=rgb=Copy RGB",
                    "--action=hsv=Copy HSV"
                ]);
            }

            function handleAction(action) {
                switch (action) {
                case "hex":
                    selectedValue = hex;
                    selectedLabel = "HEX";
                    break;

                case "rgb":
                    selectedValue = rgb;
                    selectedLabel = "RGB";
                    break;

                case "hsv":
                    selectedValue = hsv;
                    selectedLabel = "HSV";
                    break;

                default:
                    cleanup();
                    return;
                }

                copyProc.exec([
                    "wl-copy",
                    "--",
                    selectedValue
                ]);
            }

            function cleanup() {
                cleanupProc.exec([
                    "rm",
                    "-f",
                    preview
                ]);
            }

            Process {
                id: notificationProc

                stdout: StdioCollector {
                    onStreamFinished: {
                        session.handleAction(text.trim());
                    }
                }
            }

            Process {
                id: copyProc

                onExited: (exitCode, exitStatus) => {
                    if (exitCode !== 0) {
                        console.warn(
                            "ColorPicker: failed to copy",
                            session.selectedLabel,
                            "to clipboard"
                        );

                        session.cleanup();
                        return;
                    }

                    confirmProc.exec([
                        "notify-send",
                        "Color Picker",
                        session.selectedLabel
                            + " copied: "
                            + session.selectedValue,
                        "-i",
                        session.preview,
                        "-u",
                        "low"
                    ]);
                }
            }

            Process {
                id: confirmProc

                onExited: {
                    session.cleanup();
                }
            }

            Process {
                id: cleanupProc

                onExited: {
                    session.destroy();
                }
            }
        }
    }
}
