import Quickshell.Io

JsonAdapter {
    property JsonObject shell: JsonObject {
        property JsonObject launcher: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "Super_L"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell launcher"
            property string flags: "r"
        }

        property JsonObject dashboard: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "D"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell dashboard"
            property string flags: ""
        }

        property JsonObject assistant: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "A"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell assistant"
            property string flags: ""
        }

        property JsonObject clipboard: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "V"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell clipboard"
            property string flags: ""
        }

        property JsonObject emoji: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "PERIOD"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell emoji"
            property string flags: ""
        }

        property JsonObject notes: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "N"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell notes"
            property string flags: ""
        }

        property JsonObject tmux: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "T"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell tmux"
            property string flags: ""
        }

        property JsonObject wallpapers: JsonObject {
            property list<string> modifiers: ["SUPER"]
            property string key: "COMMA"
            property string dispatcher: "exec"
            property string argument: "qs ipc call shell wallpapers"
            property string flags: ""
        }

        property JsonObject system: JsonObject {
            property JsonObject config: JsonObject {
                property list<string> modifiers: ["SUPER", "SHIFT"]
                property string key: "C"
                property string dispatcher: "exec"
                property string argument: "qs ipc call shell controls"
                property string flags: ""
            }

            property JsonObject lockscreen: JsonObject {
                property list<string> modifiers: ["SUPER"]
                property string key: "L"
                property string dispatcher: "exec"
                property string argument: "loginctl lock-session"
                property string flags: ""
            }

            property JsonObject overview: JsonObject {
                property list<string> modifiers: ["SUPER"]
                property string key: "TAB"
                property string dispatcher: "exec"
                property string argument: "qs ipc call system overview"
                property string flags: ""
            }

            property JsonObject powermenu: JsonObject {
                property list<string> modifiers: ["SUPER"]
                property string key: "ESCAPE"
                property string dispatcher: "exec"
                property string argument: "qs ipc call system powermenu"
                property string flags: ""
            }

            property JsonObject tools: JsonObject {
                property list<string> modifiers: ["SUPER"]
                property string key: "S"
                property string dispatcher: "exec"
                property string argument: "qs ipc call system tools"
                property string flags: ""
            }

            property JsonObject screenshot: JsonObject {
                property list<string> modifiers: ["SUPER", "SHIFT"]
                property string key: "S"
                property string dispatcher: "exec"
                property string argument: "qs ipc call system screenshot"
                property string flags: ""
            }

            property JsonObject screenrecord: JsonObject {
                property list<string> modifiers: ["SUPER", "SHIFT"]
                property string key: "R"
                property string dispatcher: "exec"
                property string argument: "qs ipc call system screenrecord"
                property string flags: ""
            }

            property JsonObject lens: JsonObject {
                property list<string> modifiers: ["SUPER", "SHIFT"]
                property string key: "A"
                property string dispatcher: "exec"
                property string argument: "qs ipc call system lens"
                property string flags: ""
            }

            property JsonObject reload: JsonObject {
                property list<string> modifiers: ["SUPER", "ALT"]
                property string key: "B"
                property string dispatcher: "exec"
                property string argument: "pkill quickshell && quickshell -d"
                property string flags: ""
            }

            property JsonObject quit: JsonObject {
                property list<string> modifiers: ["SUPER", "CTRL", "ALT"]
                property string key: "B"
                property string dispatcher: "exec"
                property string argument: "pkill quickshell"
                property string flags: ""
            }
        }
    }
    property list<var> custom: [
        {
          "name": "Close Window",
          "keys": [{ "modifiers": ["SUPER"], "key": "C" }],
          "actions": [{ "dispatcher": "killactive", "argument": "", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Workspace navigation
        {
          "name": "Workspace 1",
          "keys": [{ "modifiers": ["SUPER"], "key": "1" }],
          "actions": [{ "dispatcher": "workspace", "argument": "1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 2",
          "keys": [{ "modifiers": ["SUPER"], "key": "2" }],
          "actions": [{ "dispatcher": "workspace", "argument": "2", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 3",
          "keys": [{ "modifiers": ["SUPER"], "key": "3" }],
          "actions": [{ "dispatcher": "workspace", "argument": "3", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 4",
          "keys": [{ "modifiers": ["SUPER"], "key": "4" }],
          "actions": [{ "dispatcher": "workspace", "argument": "4", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 5",
          "keys": [{ "modifiers": ["SUPER"], "key": "5" }],
          "actions": [{ "dispatcher": "workspace", "argument": "5", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 6",
          "keys": [{ "modifiers": ["SUPER"], "key": "6" }],
          "actions": [{ "dispatcher": "workspace", "argument": "6", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 7",
          "keys": [{ "modifiers": ["SUPER"], "key": "7" }],
          "actions": [{ "dispatcher": "workspace", "argument": "7", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 8",
          "keys": [{ "modifiers": ["SUPER"], "key": "8" }],
          "actions": [{ "dispatcher": "workspace", "argument": "8", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 9",
          "keys": [{ "modifiers": ["SUPER"], "key": "9" }],
          "actions": [{ "dispatcher": "workspace", "argument": "9", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Workspace 10",
          "keys": [{ "modifiers": ["SUPER"], "key": "0" }],
          "actions": [{ "dispatcher": "workspace", "argument": "10", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Move window to workspace
        {
          "name": "Move to Workspace 1",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "1" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 2",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "2" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "2", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 3",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "3" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "3", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 4",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "4" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "4", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 5",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "5" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "5", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 6",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "6" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "6", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 7",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "7" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "7", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 8",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "8" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "8", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 9",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "9" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "9", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Workspace 10",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "0" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "10", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Workspace scroll/keys
        {
          "name": "Previous Occupied Workspace (Scroll)",
          "keys": [{ "modifiers": ["SUPER"], "key": "mouse_down" }],
          "actions": [{ "dispatcher": "workspace", "argument": "e-1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Next Occupied Workspace (Scroll)",
          "keys": [{ "modifiers": ["SUPER"], "key": "mouse_up" }],
          "actions": [{ "dispatcher": "workspace", "argument": "e+1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Previous Occupied Workspace",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "Z" }],
          "actions": [{ "dispatcher": "workspace", "argument": "e-1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Next Occupied Workspace",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "X" }],
          "actions": [{ "dispatcher": "workspace", "argument": "e+1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Previous Workspace",
          "keys": [{ "modifiers": ["SUPER"], "key": "Z" }],
          "actions": [{ "dispatcher": "workspace", "argument": "-1", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Next Workspace",
          "keys": [{ "modifiers": ["SUPER"], "key": "X" }],
          "actions": [{ "dispatcher": "workspace", "argument": "+1", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Window drag/resize
        {
          "name": "Drag Window",
          "keys": [{ "modifiers": ["SUPER"], "key": "mouse:272" }],
          "actions": [{ "dispatcher": "movewindow", "argument": "", "flags": "m", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Drag Resize Window",
          "keys": [{ "modifiers": ["SUPER"], "key": "mouse:273" }],
          "actions": [{ "dispatcher": "resizewindow", "argument": "", "flags": "m", "layouts": [] }],
          "enabled": true
        },

        // Media controls
        {
          "name": "Play/Pause",
          "keys": [{ "modifiers": [], "key": "XF86AudioPlay" }],
          "actions": [{ "dispatcher": "exec", "argument": "playerctl play-pause", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Previous Track",
          "keys": [{ "modifiers": [], "key": "XF86AudioPrev" }],
          "actions": [{ "dispatcher": "exec", "argument": "playerctl previous", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Next Track",
          "keys": [{ "modifiers": [], "key": "XF86AudioNext" }],
          "actions": [{ "dispatcher": "exec", "argument": "playerctl next", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Media Play/Pause",
          "keys": [{ "modifiers": [], "key": "XF86AudioMedia" }],
          "actions": [{ "dispatcher": "exec", "argument": "playerctl play-pause", "flags": "l", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Stop Playback",
          "keys": [{ "modifiers": [], "key": "XF86AudioStop" }],
          "actions": [{ "dispatcher": "exec", "argument": "playerctl stop", "flags": "l", "layouts": [] }],
          "enabled": true
        },

        // Volume controls
        {
          "name": "Volume Up",
          "keys": [{ "modifiers": [], "key": "XF86AudioRaiseVolume" }],
          "actions": [{ "dispatcher": "exec", "argument": "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%+", "flags": "le", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Volume Down",
          "keys": [{ "modifiers": [], "key": "XF86AudioLowerVolume" }],
          "actions": [{ "dispatcher": "exec", "argument": "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%-", "flags": "le", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Mute Audio",
          "keys": [{ "modifiers": [], "key": "XF86AudioMute" }],
          "actions": [{ "dispatcher": "exec", "argument": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "flags": "le", "layouts": [] }],
          "enabled": true
        },

        // Brightness controls
        {
          "name": "Brightness Up",
          "keys": [{ "modifiers": [], "key": "XF86MonBrightnessUp" }],
          "actions": [{ "dispatcher": "exec", "argument": "qs ipc call brightness adjust +.05 \"\"", "flags": "le", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Brightness Down",
          "keys": [{ "modifiers": [], "key": "XF86MonBrightnessDown" }],
          "actions": [{ "dispatcher": "exec", "argument": "qs ipc call brightness adjust -.05 \"\"", "flags": "le", "layouts": [] }],
          "enabled": true
        },

        // Special keys
        {
          "name": "Calculator",
          "keys": [{ "modifiers": [], "key": "XF86Calculator" }],
          "actions": [{ "dispatcher": "exec", "argument": "notify-send \"Soon\"", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Special workspaces
        {
          "name": "Toggle Special Workspace",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "V" }],
          "actions": [{ "dispatcher": "togglespecialworkspace", "argument": "", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Move to Special Workspace",
          "keys": [{ "modifiers": ["SUPER", "ALT"], "key": "V" }],
          "actions": [{ "dispatcher": "movetoworkspace", "argument": "special", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Lid switch events
        {
          "name": "Lock on Lid Close",
          "keys": [{ "modifiers": [], "key": "switch:Lid Switch" }],
          "actions": [{ "dispatcher": "exec", "argument": "loginctl lock-session", "flags": "l", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Display Off on Lid Close",
          "keys": [{ "modifiers": [], "key": "switch:on:Lid Switch" }],
          "actions": [{ "dispatcher": "exec", "argument": "hyprctl dispatch dpms off", "flags": "l", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Display On on Lid Open",
          "keys": [{ "modifiers": [], "key": "switch:off:Lid Switch" }],
          "actions": [{ "dispatcher": "exec", "argument": "hyprctl dispatch dpms on", "flags": "l", "layouts": [] }],
          "enabled": true
        },

        // Window focus
        {
          "name": "Focus Up",
          "keys": [{ "modifiers": ["SUPER"], "key": "Up" }, { "modifiers": ["SUPER", "CTRL"], "key": "k" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "focus u", "flags": "", "layouts": ["scrolling"] }, { "dispatcher": "movefocus", "argument": "u", "flags": "", "layouts": ["dwindle", "master"] }],
          "enabled": true
        },
        {
          "name": "Focus Down",
          "keys": [{ "modifiers": ["SUPER"], "key": "Down" }, { "modifiers": ["SUPER", "CTRL"], "key": "j" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "focus d", "flags": "", "layouts": ["scrolling"] }, { "dispatcher": "movefocus", "argument": "d", "flags": "", "layouts": ["master", "dwindle"] }],
          "enabled": true
        },
        {
          "name": "Focus Left",
          "keys": [{ "modifiers": ["SUPER"], "key": "Left" }, { "modifiers": ["SUPER", "CTRL"], "key": "z" }, { "modifiers": ["SUPER", "CTRL"], "key": "h" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "focus l", "flags": "", "layouts": ["scrolling"] }, { "dispatcher": "movefocus", "argument": "l", "flags": "", "layouts": ["dwindle", "master"] }],
          "enabled": true
        },
        {
          "name": "Focus Right",
          "keys": [{ "modifiers": ["SUPER"], "key": "Right" }, { "modifiers": ["SUPER", "CTRL"], "key": "x" }, { "modifiers": ["SUPER", "CTRL"], "key": "l" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "focus r", "flags": "", "layouts": ["scrolling"] }, { "dispatcher": "movefocus", "argument": "r", "flags": "", "layouts": ["master", "dwindle"] }],
          "enabled": true
        },

        // Window movement
        {
          "name": "Move Window Left",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "Left" }, { "modifiers": ["SUPER", "SHIFT"], "key": "h" }],
          "actions": [{ "dispatcher": "movewindow", "argument": "l", "flags": "", "layouts": ["master", "dwindle"] }, { "dispatcher": "layoutmsg", "argument": "movewindowto l", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Window Right",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "Right" }, { "modifiers": ["SUPER", "SHIFT"], "key": "l" }],
          "actions": [{ "dispatcher": "movewindow", "argument": "r", "flags": "", "layouts": ["dwindle", "master"] }, { "dispatcher": "layoutmsg", "argument": "movewindowto r", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Window Up",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "Up" }, { "modifiers": ["SUPER", "SHIFT"], "key": "k" }],
          "actions": [{ "dispatcher": "movewindow", "argument": "u", "flags": "", "layouts": ["master", "dwindle"] }, { "dispatcher": "layoutmsg", "argument": "movewindowto u", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Window Down",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "Down" }, { "modifiers": ["SUPER", "SHIFT"], "key": "j" }],
          "actions": [{ "dispatcher": "movewindow", "argument": "d", "flags": "", "layouts": ["master", "dwindle"] }, { "dispatcher": "layoutmsg", "argument": "movewindowto d", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Window resize
        {
          "name": "Horizontal Resize +",
          "keys": [{ "modifiers": ["SUPER", "ALT"], "key": "Right" }, { "modifiers": ["SUPER", "ALT"], "key": "l" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "colresize +0.1", "flags": "", "layouts": ["scrolling"] }, { "dispatcher": "resizeactive", "argument": "50 0", "flags": "", "layouts": ["master", "dwindle"] }],
          "enabled": true
        },
        {
          "name": "Horizontal Resize -",
          "keys": [{ "modifiers": ["SUPER", "ALT"], "key": "Left" }, { "modifiers": ["SUPER", "ALT"], "key": "h" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "colresize -0.1", "flags": "", "layouts": ["scrolling"] }, { "dispatcher": "resizeactive", "argument": "-50 0", "flags": "", "layouts": ["master", "dwindle"] }],
          "enabled": true
        },
        {
          "name": "Vertical Resize +",
          "keys": [{ "modifiers": ["SUPER", "ALT"], "key": "Down" }, { "modifiers": ["SUPER", "ALT"], "key": "j" }],
          "actions": [{ "dispatcher": "resizeactive", "argument": "0 50", "flags": "", "layouts": [] }],
          "enabled": true
        },
        {
          "name": "Vertical Resize -",
          "keys": [{ "modifiers": ["SUPER", "ALT"], "key": "Up" }, { "modifiers": ["SUPER", "ALT"], "key": "k" }],
          "actions": [{ "dispatcher": "resizeactive", "argument": "0 -50", "flags": "", "layouts": [] }],
          "enabled": true
        },

        // Scrolling layout
        {
          "name": "Promote (Scrolling)",
          "keys": [{ "modifiers": ["SUPER", "ALT"], "key": "SPACE" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "promote", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Toggle Fit (Scrolling)",
          "keys": [{ "modifiers": ["SUPER", "CTRL"], "key": "SPACE" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "togglefit", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Toggle Full Column (Scrolling)",
          "keys": [{ "modifiers": ["SUPER", "SHIFT"], "key": "SPACE" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "colresize +conf", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Swap Column Left",
          "keys": [{ "modifiers": ["SUPER", "ALT", "CTRL"], "key": "Left" }, { "modifiers": ["SUPER", "ALT", "CTRL"], "key": "h" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "swapcol l", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Swap Column Right",
          "keys": [{ "modifiers": ["SUPER", "ALT", "CTRL"], "key": "Right" }, { "modifiers": ["SUPER", "ALT", "CTRL"], "key": "l" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "swapcol r", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },

        // Move column to workspace
        {
          "name": "Move Column To Workspace 1",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "1" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 1", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 2",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "2" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 2", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 3",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "3" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 3", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 4",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "4" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 4", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 5",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "5" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 5", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 6",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "6" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 6", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 7",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "7" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 7", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 8",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "8" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 8", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 9",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "9" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 9", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        },
        {
          "name": "Move Column To Workspace 10",
          "keys": [{ "modifiers": ["SUPER", "CTRL", "ALT"], "key": "0" }],
          "actions": [{ "dispatcher": "layoutmsg", "argument": "movecoltoworkspace 10", "flags": "", "layouts": ["scrolling"] }],
          "enabled": true
        }
    ]
}
