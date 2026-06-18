pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.config

QtObject {
  id: root

  property bool enabled: false
  property real x: 0.0
  property real y: 0.0
  property real smoothX: 0.0
  property real smoothY: 0.0

  property real smoothing: {
    const cfg = Config.system.motionCues;
    return cfg && cfg.smoothing !== undefined ? cfg.smoothing : 0.18;
  }

  property string sourceCommand: {
    const cfg = Config.system.motionCues;
    return cfg && cfg.sourceCommand !== undefined ? cfg.sourceCommand : "";
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function setMotion(nx, ny) {
    root.x = clamp(nx, -1.0, 1.0);
    root.y = clamp(ny, -1.0, 1.0);
  }

  function start() {
    root.enabled = true;
  }

  function stop() {
    root.enabled = false;
    root.x = 0.0;
    root.y = 0.0;
    root.smoothX = 0.0;
    root.smoothY = 0.0;
  }

  function toggle() {
    root.enabled ? root.stop() : root.start();
  }

  property Timer smoothingTimer: Timer {
    interval: 16
    running: root.enabled
    repeat: true

    onTriggered: {
      root.smoothX += (root.x - root.smoothX) * root.smoothing;
      root.smoothY += (root.y - root.smoothY) * root.smoothing;
    }
  }

  property Timer fakeMotionTimer: Timer {
    interval: 16
    running: root.enabled && root.sourceCommand.length === 0
    repeat: true

    onTriggered: {
      const now = Date.now() / 1000.0;

      root.setMotion(
        Math.sin(now * 0.85) * 0.55 + Math.sin(now * 2.1) * 0.10,
        Math.cos(now * 0.65) * 0.35
      );
    }
  }

  property Process sensorProcess: Process {
    running: root.enabled && root.sourceCommand.length > 0
    command: root.sourceCommand.length > 0
      ? ["sh", "-c", root.sourceCommand]
      : []

    stdout: SplitParser {
      onRead: function(line) {
        try {
          const data = JSON.parse(line);

          if (data.x !== undefined && data.y !== undefined) {
            root.setMotion(Number(data.x), Number(data.y));
          }
        } catch (error) {
          console.warn("MotionCues: bad sensor line:", line);
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text.length > 0)
          console.warn("MotionCues source stderr:", this.text);
      }
    }
  }
}
