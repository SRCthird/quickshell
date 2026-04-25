pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

QtObject {
    id: root

    property string sessionPath: ""

    property Process pathProc: Process {
        command: [
            "bash", "-lc",
            "busctl --system call " +
            "org.freedesktop.login1 " +
            "/org/freedesktop/login1 " +
            "org.freedesktop.login1.Manager " +
            "GetSession s \"$XDG_SESSION_ID\" | awk -F'\"' '{print $2}'"
        ]
        running: true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.sessionPath = text.trim();
                console.log("logind sessionPath:", root.sessionPath);
                if (root.sessionPath !== "")
                    root.monitor.running = true;
                else
                    console.warn("Could not determine logind session object path");
            }
        }
    }

    property Process monitor: Process {
        running: false
        command: [
            "gdbus", "monitor",
            "--system",
            "--dest", "org.freedesktop.login1",
            "--object-path", root.sessionPath
        ]

        stdout: SplitParser {
            onRead: data => {
                const s = data.toString();
                console.log("logind:", s);

                if (s.indexOf("member=Lock") !== -1 || s.indexOf("Lock ()") !== -1) {
                    console.log("logind requested lock");
                    GlobalStates.lockscreenVisible = true;
                }
            }
        }
    }
}
