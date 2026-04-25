import Quickshell.Io

JsonAdapter {
    property bool oledMode: false
    property bool lightMode: false
    property int roundness: 16
    property string font: "Roboto Condensed"
    property int fontSize: 14
    property string monoFont: "Iosevka Nerd Font Mono"
    property int monoFontSize: 14
    property bool tintIcons: false
    property bool enableCorners: true
    property int animDuration: 300
    property real shadowOpacity: 0.5
    property string shadowColor: "shadow"
    property int shadowXOffset: 0
    property int shadowYOffset: 0
    property real shadowBlur: 1

    property JsonObject srBg: JsonObject {
        property string label: "Background"
        property list<var> gradient: [["background", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "surface"
        property string halftoneBackgroundColor: "background"
        property list<var> border: ["surfaceBright", 0]
        property string itemColor: "overBackground"
        property real opacity: 1.0
    }

    property JsonObject srPopup: JsonObject {
        property string label: "Popup"
        property list<var> gradient: [["background", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "surface"
        property string halftoneBackgroundColor: "background"
        property list<var> border: ["surfaceBright", 2]
        property string itemColor: "overBackground"
        property real opacity: 1.0
    }

    property JsonObject srInternalBg: JsonObject {
        property string label: "Internal BG"
        property list<var> gradient: [["background", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "surface"
        property string halftoneBackgroundColor: "background"
        property list<var> border: ["surfaceBright", 0]
        property string itemColor: "overBackground"
        property real opacity: 1.0
    }

    property JsonObject srBarBg: JsonObject {
        property string label: "Bar BG"
        property list<var> gradient: [["surfaceDim", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "surface"
        property string halftoneBackgroundColor: "surfaceDim"
        property list<var> border: ["surfaceBright", 0]
        property string itemColor: "overBackground"
        property real opacity: 0.0
    }

    property JsonObject srPane: JsonObject {
        property string label: "Pane"
        property list<var> gradient: [["surface", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "surfaceBright"
        property string halftoneBackgroundColor: "surface"
        property list<var> border: ["surfaceBright", 0]
        property string itemColor: "overBackground"
        property real opacity: 1.0
    }

    property JsonObject srCommon: JsonObject {
        property string label: "Common"
        property list<var> gradient: [["surface", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "background"
        property string halftoneBackgroundColor: "surface"
        property list<var> border: ["surfaceBright", 0]
        property string itemColor: "overBackground"
        property real opacity: 1.0
    }

    property JsonObject srFocus: JsonObject {
        property string label: "Focus"
        property list<var> gradient: [["surfaceBright", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "surfaceVariant"
        property string halftoneBackgroundColor: "surfaceBright"
        property list<var> border: ["surfaceBright", 0]
        property string itemColor: "overBackground"
        property real opacity: 1.0
    }

    property JsonObject srPrimary: JsonObject {
        property string label: "Primary"
        property list<var> gradient: [["primary", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "overPrimaryContainer"
        property string halftoneBackgroundColor: "primary"
        property list<var> border: ["primary", 0]
        property string itemColor: "overPrimary"
        property real opacity: 1.0
    }

    property JsonObject srPrimaryFocus: JsonObject {
        property string label: "Primary Focus"
        property list<var> gradient: [["overPrimaryContainer", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "primary"
        property string halftoneBackgroundColor: "overPrimaryContainer"
        property list<var> border: ["overBackground", 0]
        property string itemColor: "overPrimary"
        property real opacity: 1.0
    }

    property JsonObject srOverPrimary: JsonObject {
        property string label: "Over Primary"
        property list<var> gradient: [["overPrimary", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "primaryContainer"
        property string halftoneBackgroundColor: "overPrimary"
        property list<var> border: ["overPrimary", 0]
        property string itemColor: "primary"
        property real opacity: 1.0
    }

    property JsonObject srSecondary: JsonObject {
        property string label: "Secondary"
        property list<var> gradient: [["secondary", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "overSecondaryContainer"
        property string halftoneBackgroundColor: "secondary"
        property list<var> border: ["secondary", 0]
        property string itemColor: "overSecondary"
        property real opacity: 1.0
    }

    property JsonObject srSecondaryFocus: JsonObject {
        property string label: "Secondary Focus"
        property list<var> gradient: [["overSecondaryContainer", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "secondary"
        property string halftoneBackgroundColor: "overSecondaryContainer"
        property list<var> border: ["overBackground", 0]
        property string itemColor: "overSecondary"
        property real opacity: 1.0
    }

    property JsonObject srOverSecondary: JsonObject {
        property string label: "Over Secondary"
        property list<var> gradient: [["overSecondary", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "secondaryContainer"
        property string halftoneBackgroundColor: "overSecondary"
        property list<var> border: ["overSecondary", 0]
        property string itemColor: "secondary"
        property real opacity: 1.0
    }

    property JsonObject srTertiary: JsonObject {
        property string label: "Tertiary"
        property list<var> gradient: [["tertiary", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "overTertiaryContainer"
        property string halftoneBackgroundColor: "tertiary"
        property list<var> border: ["tertiary", 0]
        property string itemColor: "overTertiary"
        property real opacity: 1.0
    }

    property JsonObject srTertiaryFocus: JsonObject {
        property string label: "Tertiary Focus"
        property list<var> gradient: [["overTertiaryContainer", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "tertiary"
        property string halftoneBackgroundColor: "overTertiaryContainer"
        property list<var> border: ["overBackground", 0]
        property string itemColor: "overTertiary"
        property real opacity: 1.0
    }

    property JsonObject srOverTertiary: JsonObject {
        property string label: "Over Tertiary"
        property list<var> gradient: [["overTertiary", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "tertiaryContainer"
        property string halftoneBackgroundColor: "overTertiary"
        property list<var> border: ["overTertiary", 0]
        property string itemColor: "tertiary"
        property real opacity: 1.0
    }

    property JsonObject srError: JsonObject {
        property string label: "Error"
        property list<var> gradient: [["error", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "overErrorContainer"
        property string halftoneBackgroundColor: "error"
        property list<var> border: ["error", 0]
        property string itemColor: "overError"
        property real opacity: 1.0
    }

    property JsonObject srErrorFocus: JsonObject {
        property string label: "Error Focus"
        property list<var> gradient: [["overBackground", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "error"
        property string halftoneBackgroundColor: "overErrorContainer"
        property list<var> border: ["overBackground", 0]
        property string itemColor: "overError"
        property real opacity: 1.0
    }

    property JsonObject srOverError: JsonObject {
        property string label: "Over Error"
        property list<var> gradient: [["overError", 0.0]]
        property string gradientType: "linear"
        property int gradientAngle: 0
        property real gradientCenterX: 0.5
        property real gradientCenterY: 0.5
        property real halftoneDotMin: 0.0
        property real halftoneDotMax: 2.0
        property real halftoneStart: 0.0
        property real halftoneEnd: 1.0
        property string halftoneDotColor: "errorContainer"
        property string halftoneBackgroundColor: "overError"
        property list<var> border: ["overError", 0]
        property string itemColor: "error"
        property real opacity: 1.0
    }
}
