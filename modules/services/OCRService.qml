pragma Singleton

import QtQuick
import QtCore

import Quickshell
import Quickshell.Io

import qs.modules.config

Singleton {
    id: root

    property bool busy: false

    property string _capturePath: ""
    property string _languages: "eng+spa"

    function configuredLanguages() {
        var ocrConfig = Config.system
            ? Config.system.ocr
            : null;

        var langs = [];

        if (ocrConfig) {
            if (ocrConfig.eng !== false)
                langs.push("eng");

            if (ocrConfig.spa !== false)
                langs.push("spa");

            if (ocrConfig.lat === true)
                langs.push("lat");

            if (ocrConfig.jpn === true)
                langs.push("jpn");

            if (ocrConfig.chi_sim === true)
                langs.push("chi_sim");

            if (ocrConfig.chi_tra === true)
                langs.push("chi_tra");

            if (ocrConfig.kor === true)
                langs.push("kor");
        } else {
            langs = ["eng", "spa"];
        }

        if (langs.length === 0)
            langs.push("eng");

        return langs.join("+");
    }

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

    function checkDependencies() {
        var dependencies = [
            "grim",
            "tesseract",
            "notify-send"
        ];

        var missing = [];

        for (var i = 0; i < dependencies.length; ++i) {
            if (!hasExecutable(dependencies[i]))
                missing.push(dependencies[i]);
        }

        if (missing.length === 0)
            return true;

        notify(
            "OCR Error",
            "Missing dependency: " + missing.join(", "),
            "critical",
            "dialog-error"
        );

        return false;
    }

    function scan() {
        if (busy)
            return;

        if (!checkDependencies())
            return;

        busy = true;

        _languages = configuredLanguages();

        _capturePath = Quickshell.cachePath(
            "ocr-"
            + Quickshell.processId
            + "-"
            + Date.now()
            + ".png"
        );

        RegionSelector.select("ocr");
    }

    function finish() {
        busy = false;
    }

    Connections {
        target: RegionSelector

        function onSelected(purpose, geometry) {
            if (purpose !== "ocr")
                return;

            console.log("OCR region:", geometry);

            grimProc.exec([
                "grim",
                "-g", geometry,
                root._capturePath
            ]);
        }

        function onCancelled(purpose) {
            if (purpose !== "ocr")
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
                    "OCR grim failed:",
                    grimError.text
                );

                root.notify(
                    "OCR Error",
                    "Failed to capture selected region",
                    "critical",
                    "dialog-error"
                );

                root.finish();
                return;
            }

            tesseractProc.exec([
                "tesseract",
                root._capturePath,
                "stdout",
                "-l", root._languages
            ]);
        }
    }

    Process {
        id: tesseractProc

        stdout: StdioCollector {
            id: tesseractOutput
        }

        stderr: StdioCollector {
            id: tesseractError
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error(
                    "Tesseract failed:",
                    tesseractError.text
                );

                root.notify(
                    "OCR Error",
                    "Tesseract failed",
                    "critical",
                    "dialog-error"
                );

                root.finish();
                return;
            }

            var text = tesseractOutput.text.trim();

            if (text === "") {
                root.notify(
                    "OCR Result",
                    "No text detected",
                    "low",
                    "dialog-error"
                );

                root.finish();
                return;
            }

            Quickshell.clipboardText = text;

            root.notify(
                "OCR Result",
                "Text copied to clipboard",
                "normal",
                "edit-paste"
            );

            root.finish();
        }
    }
}
