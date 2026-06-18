import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.config
import qs.modules.services
import qs.modules.theme

PanelWindow {
  id: root

  required property ShellScreen targetScreen

  screen: targetScreen
  color: "transparent"
  focusable: false
  exclusionMode: ExclusionMode.Ignore

  anchors {
    top: true
    left: true
    right: true
    bottom: true
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "motion-cues"

  mask: Region {}

  readonly property var cfg: Config.system.motionCues

  readonly property int dotRadius: cfg && cfg.dotRadius !== undefined ? cfg.dotRadius : 4
  readonly property int spacing: cfg && cfg.spacing !== undefined ? cfg.spacing : 54
  readonly property int edgeInset: cfg && cfg.edgeInset !== undefined ? cfg.edgeInset : 28
  readonly property int maxShift: cfg && cfg.maxShift !== undefined ? cfg.maxShift : 34
  readonly property real opacityValue: cfg && cfg.opacity !== undefined ? cfg.opacity : 0.55
  readonly property color dotColor: Colors.primary

  Connections {
    target: MotionCues

    function onSmoothXChanged() {
      canvas.requestPaint();
    }

    function onSmoothYChanged() {
      canvas.requestPaint();
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      const ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);

      const shiftX = MotionCues.smoothX * root.maxShift;
      const shiftY = MotionCues.smoothY * root.maxShift;

      ctx.globalAlpha = root.opacityValue;
      ctx.fillStyle = root.dotColor;

      function dot(x, y) {
        ctx.beginPath();
        ctx.arc(x, y, root.dotRadius, 0, Math.PI * 2);
        ctx.fill();
      }

      for (let y = root.spacing; y < height - root.spacing; y += root.spacing) {
        dot(root.edgeInset + shiftX, y + shiftY);
        dot(width - root.edgeInset + shiftX, y + shiftY);
      }

      for (let x = root.spacing; x < width - root.spacing; x += root.spacing * 1.5) {
        dot(x + shiftX, root.edgeInset + shiftY);
        dot(x + shiftX, height - root.edgeInset + shiftY);
      }
    }
  }
}
