import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.modules.config
import qs.modules.theme
import qs.modules.bar
import qs.modules.globals

QtObject {
    id: root

    property Process compositorProcess: Process {
        stderr: SplitParser {
            onRead: line => {
                if (line && line.trim().length > 0) {
                    console.error("CompositorConfig: hyprctl eval error:", line);
                }
            }
        }

        onExited: code => {
            if (code !== 0) {
                console.error("CompositorConfig: hyprctl eval exited with code:", code);
            }
        }
    }

    function configReady() {
        return Config.themeReady
            && Config.compositorReady
            && Config.barReady
            && Config.theme
            && Config.compositor
            && Config.bar;
    }

    property var currentAnimationConfig: null
    property Process readAnimationsProcess: Process {
        command: ["hyprctl", "-j", "animations"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        currentAnimationConfig = parsed;
                    }
                } catch (e) {
                    console.error("CompositorConfig: Error parsing animations:", e);
                }
            }
        }
    }

    property var barInstances: []

    function registerBar(barInstance) {
        barInstances.push(barInstance);
    }

    function getBarOrientation() {
        if (barInstances.length > 0) {
            return barInstances[0].orientation || "horizontal";
        }
        const position = Config.bar.position || "top";
        return (position === "left" || position === "right") ? "vertical" : "horizontal";
    }

    property Timer applyTimer: Timer {
        interval: 100
        repeat: false
        onTriggered: applyCompositorConfigInternal()
    }

    function getColorValue(colorName) {
        const resolved = Config.resolveColor(colorName);
        // Convert HEX string to color, or return if already a color.
        return (typeof resolved === 'string') ? Qt.color(resolved) : resolved;
    }

    function formatColorForCompositor(color) {
        // HyprctlService expects colors in format: rgb(rrggbb) or rgba(rrggbbaa)
        const r = Math.round(color.r * 255).toString(16).padStart(2, '0');
        const g = Math.round(color.g * 255).toString(16).padStart(2, '0');
        const b = Math.round(color.b * 255).toString(16).padStart(2, '0');
        const a = Math.round(color.a * 255).toString(16).padStart(2, '0');

        if (color.a === 1.0) {
            return `rgb(${r}${g}${b})`;
        } else {
            return `rgba(${r}${g}${b}${a})`;
        }
    }

    function luaString(value) {
        return JSON.stringify(String(value));
    }

    function luaBoolean(value) {
        return value ? "true" : "false";
    }

    function luaNumber(value, fallback) {
        const parsed = Number(value);
        return isFinite(parsed) ? String(parsed) : String(fallback);
    }

    function luaScalar(value, fallback) {
        if (typeof value === "boolean")
            return luaBoolean(value);

        if (typeof value === "number")
            return luaNumber(value, fallback);

        const stringValue = String(value);
        const parsed = Number(value);

        if (stringValue.trim() !== "" && isFinite(parsed))
            return String(parsed);

        return luaString(value);
    }

    function formatGradientForLua(colorNames, fallbackColorName, angle, forceOpaque) {
        const names = colorNames && colorNames.length > 0
            ? colorNames
            : [fallbackColorName];

        const colors = names.map(colorName => {
            const color = getColorValue(colorName);
            const resolvedColor = forceOpaque
                ? Qt.rgba(color.r, color.g, color.b, 1.0)
                : color;

            return luaString(formatColorForCompositor(resolvedColor));
        });

        if (colors.length === 1)
            return colors[0];

        return `{ colors = { ${colors.join(", ")} }, angle = ${luaNumber(angle, 0)} }`;
    }

    function formatVec2ForLua(value) {
        if (Array.isArray(value) && value.length >= 2) {
            return `{ ${luaNumber(value[0], 0)}, ${luaNumber(value[1], 0)} }`;
        }

        if (value && value.x !== undefined && value.y !== undefined) {
            return `{ ${luaNumber(value.x, 0)}, ${luaNumber(value.y, 0)} }`;
        }

        const text = value === undefined || value === null ? "" : String(value);
        const parts = text
            .replace(/[\[\](),]/g, " ")
            .trim()
            .split(/\s+/);

        if (parts.length >= 2) {
            return `{ ${luaNumber(parts[0], 0)}, ${luaNumber(parts[1], 0)} }`;
        }

        return "{ 0, 0 }";
    }

    function applyCompositorConfig() {
        readAnimationsProcess.running = true;
        applyTimer.restart();
    }

    function applyCompositorConfigInternal() {
        if (!configReady()) {
            console.log("CompositorConfig: Waiting for Config...");
            return;
        }

        // Wait for layout to be ready.
        if (!GlobalStates.compositorLayoutReady) {
            console.log("CompositorConfig: Esperando que se detecte el layout de HyprctlService...");
            return;
        }

        const activeBorderLua = Config.compositor.syncBorderColor
            ? luaString(formatColorForCompositor(getColorValue(Config.compositorBorderColor)))
            : formatGradientForLua(
                Config.compositor.activeBorderColor,
                Config.compositorBorderColor,
                Config.compositor.borderAngle,
                false
            );

        const inactiveBorderLua = formatGradientForLua(
            Config.compositor.inactiveBorderColor,
            "surface",
            Config.compositor.inactiveBorderAngle,
            true
        );

        // Shadow colors.
        const shadowColor = getColorValue(Config.compositorShadowColor);
        const shadowColorInactive = getColorValue(Config.compositor.shadowColorInactive);
        const shadowColorWithOpacity = Qt.rgba(
            shadowColor.r,
            shadowColor.g,
            shadowColor.b,
            shadowColor.a * Config.compositorShadowOpacity
        );
        const shadowColorInactiveWithOpacity = Qt.rgba(
            shadowColorInactive.r,
            shadowColorInactive.g,
            shadowColorInactive.b,
            shadowColorInactive.a * Config.compositorShadowOpacity
        );
        const shadowColorFormatted = formatColorForCompositor(shadowColorWithOpacity);
        const shadowColorInactiveFormatted = formatColorForCompositor(shadowColorInactiveWithOpacity);

        const barOrientation = getBarOrientation();
        let speed = 2.5;
        let bezier = "default";

        if (currentAnimationConfig && currentAnimationConfig.length > 0) {
            const animations = Array.isArray(currentAnimationConfig[0])
                ? currentAnimationConfig[0]
                : currentAnimationConfig;
            const workspaceAnim = animations.find(anim => anim.name === "workspaces");

            if (workspaceAnim) {
                speed = workspaceAnim.speed || speed;
                bezier = workspaceAnim.bezier || workspaceAnim.curve || bezier;
            }
        }

        const workspacesAnimation = barOrientation === "vertical"
            ? "slidefadevert 20%"
            : "slidefade 20%";

        // Calculate ignorealpha.
        let ignoreAlphaValue = 0.0;

        if (Config.compositor.blurExplicitIgnoreAlpha) {
            ignoreAlphaValue = Config.compositor.blurIgnoreAlphaValue.toFixed(2);
        } else {
            // Dynamic ignorealpha based on StyledRect opacity.
            // Use min(barbg, bg) opacity if barbg > 0, else use bg.
            const barBgOpacity = (Config.theme.srBarBg && Config.theme.srBarBg.opacity !== undefined) ? Config.theme.srBarBg.opacity : 0;
            const bgOpacity = (Config.theme.srBg && Config.theme.srBg.opacity !== undefined) ? Config.theme.srBg.opacity : 1.0;
            ignoreAlphaValue = (barBgOpacity > 0 ? Math.min(barBgOpacity, bgOpacity) : bgOpacity).toFixed(2);
            console.log(`CompositorConfig: Auto ignorealpha calculated: ${ignoreAlphaValue} (bg: ${bgOpacity}, bar: ${barBgOpacity})`);
        }

        const layoutConfig = GlobalStates.compositorLayout
            ? `layout = ${luaString(GlobalStates.compositorLayout)},`
            : "";

        const luaConfig = `
hl.config({
    general = {
        border_size = ${luaNumber(Config.compositorBorderSize, 1)},
        gaps_in = ${luaScalar(Config.compositor.gapsIn, 0)},
        gaps_out = ${luaScalar(Config.compositor.gapsOut, 0)},
        col = {
            active_border = ${activeBorderLua},
            inactive_border = ${inactiveBorderLua},
        },
        ${layoutConfig}
    },
    decoration = {
        rounding = ${luaNumber(Config.compositorRounding, 0)},
        shadow = {
            enabled = ${luaBoolean(Config.compositor.shadowEnabled)},
            range = ${luaNumber(Config.compositor.shadowRange, 4)},
            render_power = ${luaNumber(Config.compositor.shadowRenderPower, 3)},
            sharp = ${luaBoolean(Config.compositor.shadowSharp)},
            color = ${luaString(shadowColorFormatted)},
            color_inactive = ${luaString(shadowColorInactiveFormatted)},
            offset = ${formatVec2ForLua(Config.compositor.shadowOffset)},
            scale = ${luaNumber(Config.compositor.shadowScale, 1)},
        },
        blur = {
            enabled = ${luaBoolean(Config.compositor.blurEnabled)},
            size = ${luaNumber(Config.compositor.blurSize, 8)},
            passes = ${luaNumber(Config.compositor.blurPasses, 1)},
            ignore_opacity = ${luaBoolean(Config.compositor.blurIgnoreOpacity)},
            new_optimizations = ${luaBoolean(Config.compositor.blurNewOptimizations)},
            xray = ${luaBoolean(Config.compositor.blurXray)},
            noise = ${luaNumber(Config.compositor.blurNoise, 0.0117)},
            contrast = ${luaNumber(Config.compositor.blurContrast, 0.8916)},
            brightness = ${luaNumber(Config.compositor.blurBrightness, 0.8172)},
            vibrancy = ${luaNumber(Config.compositor.blurVibrancy, 0.1696)},
            vibrancy_darkness = ${luaNumber(Config.compositor.blurVibrancyDarkness, 0)},
            special = ${luaBoolean(Config.compositor.blurSpecial)},
            popups = ${luaBoolean(Config.compositor.blurPopups)},
            popups_ignorealpha = ${luaNumber(Config.compositor.blurPopupsIgnorealpha, 0.2)},
            input_methods = ${luaBoolean(Config.compositor.blurInputMethods)},
            input_methods_ignorealpha = ${luaNumber(Config.compositor.blurInputMethodsIgnorealpha, 0.2)},
        },
    },
})

hl.curve("myBezier", {
    type = "bezier",
    points = {
        { 0.4, 0.0 },
        { 0.2, 1.0 },
    },
})

hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 2.5,
    bezier = "myBezier",
    style = "popin 80%",
})

hl.animation({
    leaf = "border",
    enabled = true,
    speed = 2.5,
    bezier = "myBezier",
})

hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 2.5,
    bezier = "myBezier",
})

hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = ${luaNumber(speed, 2.5)},
    bezier = ${luaString(bezier)},
    style = ${luaString(workspacesAnimation)},
})

hl.layer_rule({
    name = "quickshell-compositor",
    match = {
        namespace = "^quickshell$",
    },
    no_anim = true,
    blur = true,
    blur_popups = true,
    ignore_alpha = ${ignoreAlphaValue},
})
`;

        console.log(
            `CompositorConfig: Applying ignorealpha: ${ignoreAlphaValue}, explicit: ${Config.compositor.blurExplicitIgnoreAlpha}`
        );
        console.log("CompositorConfig: Applying compositor Lua configuration");

        compositorProcess.command = [
            "hyprctl",
            "eval",
            luaConfig
        ];
        compositorProcess.running = true;
    }

    property Connections configConnections: Connections {
        target: Config

        function onThemeUpdated() {
            applyCompositorConfig();
        }

        function onThemeReadyChanged() {
            if (Config.themeReady)
                applyCompositorConfig();
        }

        function onCompositorReadyChanged() {
            if (Config.compositorReady)
                applyCompositorConfig();
        }

        function onBarReadyChanged() {
            if (Config.barReady)
                applyCompositorConfig();
        }
    }

    property Connections compositorConfigConnections: Connections {
        target: Config.compositor

        function onBorderSizeChanged() {
            applyCompositorConfig();
        }
        function onRoundingChanged() {
            applyCompositorConfig();
        }
        function onGapsInChanged() {
            applyCompositorConfig();
        }
        function onGapsOutChanged() {
            applyCompositorConfig();
        }
        function onActiveBorderColorChanged() {
            applyCompositorConfig();
        }
        function onInactiveBorderColorChanged() {
            applyCompositorConfig();
        }
        function onBorderAngleChanged() {
            applyCompositorConfig();
        }
        function onInactiveBorderAngleChanged() {
            applyCompositorConfig();
        }
        function onSyncRoundnessChanged() {
            applyCompositorConfig();
        }
        function onSyncBorderWidthChanged() {
            applyCompositorConfig();
        }
        function onSyncBorderColorChanged() {
            applyCompositorConfig();
        }
        function onSyncShadowOpacityChanged() {
            applyCompositorConfig();
        }
        function onSyncShadowColorChanged() {
            applyCompositorConfig();
        }
        function onShadowEnabledChanged() {
            applyCompositorConfig();
        }
        function onShadowRangeChanged() {
            applyCompositorConfig();
        }
        function onShadowRenderPowerChanged() {
            applyCompositorConfig();
        }
        function onShadowSharpChanged() {
            applyCompositorConfig();
        }
        function onShadowColorChanged() {
            applyCompositorConfig();
        }
        function onShadowColorInactiveChanged() {
            applyCompositorConfig();
        }
        function onShadowOpacityChanged() {
            applyCompositorConfig();
        }
        function onShadowOffsetChanged() {
            applyCompositorConfig();
        }
        function onShadowScaleChanged() {
            applyCompositorConfig();
        }
        function onBlurEnabledChanged() {
            applyCompositorConfig();
        }
        function onBlurSizeChanged() {
            applyCompositorConfig();
        }
        function onBlurPassesChanged() {
            applyCompositorConfig();
        }
        function onBlurIgnoreOpacityChanged() {
            applyCompositorConfig();
        }
        function onBlurExplicitIgnoreAlphaChanged() {
            applyCompositorConfig();
        }
        function onBlurIgnoreAlphaValueChanged() {
            applyCompositorConfig();
        }
        function onBlurNewOptimizationsChanged() {
            applyCompositorConfig();
        }
        function onBlurXrayChanged() {
            applyCompositorConfig();
        }
        function onBlurNoiseChanged() {
            applyCompositorConfig();
        }
        function onBlurContrastChanged() {
            applyCompositorConfig();
        }
        function onBlurBrightnessChanged() {
            applyCompositorConfig();
        }
        function onBlurVibrancyChanged() {
            applyCompositorConfig();
        }
        function onBlurVibrancyDarknessChanged() {
            applyCompositorConfig();
        }
        function onBlurSpecialChanged() {
            applyCompositorConfig();
        }
        function onBlurPopupsChanged() {
            applyCompositorConfig();
        }
        function onBlurPopupsIgnorealphaChanged() {
            applyCompositorConfig();
        }
        function onBlurInputMethodsChanged() {
            applyCompositorConfig();
        }
        function onBlurInputMethodsIgnorealphaChanged() {
            applyCompositorConfig();
        }
    }

    property Connections colorsConnections: Connections {
        target: Colors
        function onFileChanged() {
            applyCompositorConfig();
        }
        function onLoaded() {
            applyCompositorConfig();
        }
    }

    property Connections barConnections: Connections {
        target: Config.bar
        function onPositionChanged() {
            applyCompositorConfig();
        }
    }

    property Connections srBgConnections: Connections {
        target: Config.theme.srBg
        function onOpacityChanged() {
            applyCompositorConfig();
        }
    }

    property Connections srBarBgConnections: Connections {
        target: Config.theme.srBarBg
        function onOpacityChanged() {
            applyCompositorConfig();
        }
    }

    property Connections globalStatesConnections: Connections {
        target: GlobalStates
        function onCompositorLayoutChanged() {
            applyCompositorConfig();
        }
        function onCompositorLayoutReadyChanged() {
            if (GlobalStates.compositorLayoutReady) {
                applyCompositorConfig();
            }
        }
    }

    property Connections compositorConnections: Connections {
        target: HyprctlService
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                console.log("CompositorConfig: Detectado configreloaded, reaplicando configuración...");
                applyCompositorConfig();
            }
        }
    }

    Component.onCompleted: {
        if (configReady())
            applyCompositorConfig();
    }
}
