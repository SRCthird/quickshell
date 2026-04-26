# Quickshell Shell

A customizable Wayland desktop quickshell build with **Quickshell**, **QtQuick**, and **QML/JavaScript**.

This project provides a unified desktop experience for Hyprland workflows, including a configurable bar, dock, notch, dashboard, lockscreen, desktop widgets, system tools, notifications, and a reactive JSON-based configuration system.

### Fork
Fork of https://github.com/Axenide/Ambxst/releases/tag/1.1.2

## Preview

<p align="center">
  <img src="/assets/screenshots/preview-1.png" width="48%" />
  <img src="/assets/screenshots/preview-2.png" width="48%" />
</p>

<p align="center">
  <img src="/assets/screenshots/preview-3.png" width="48%" />
  <img src="/assets/screenshots/preview-4.png" width="48%" />
</p>

<p align="center">
  <img src="/assets/screenshots/preview-5.png" width="48%" />
  <img src="/assets/screenshots/preview-6.png" width="48%" />
</p>

<p align="center">
  <img src="/assets/screenshots/preview-7.png" width="48%" />
  <img src="/assets/screenshots/preview-9.png" width="48%" />
</p>

## Features

- **Unified shell interface** with bar, dock, notch, overlays, OSD layers, and desktop widgets
- **Reactive JSON configuration** powered by `FileView` and `JsonAdapter`
- **Multi-monitor support** using `Variants` with `Quickshell.screens`
- **Dynamic theming** with shared colors, icons, sizing, and style utilities
- **Dashboard and launcher** for controls, search, clipboard, notes, assistant tools, and more
- **Workspace overview** with window-management helpers
- **Notification system** with popups and notification history
- **Lockscreen integration** using `WlSessionLock` and PAM authentication
- **Service layer** for compositor integration, power, network, battery, AI, visibility, and runtime state
- **Modular architecture** built from reusable QML primitives, backend scripts, and independent widgets

## Tech Stack

- **Framework:** QtQuick / Quickshell
- **Languages:** QML / JavaScript
- **Target workflow:** Hyprland-oriented Wayland setup

## Quickstart

Clone the repository into your Quickshell config directory:

```bash
git clone --depth 1 https://github.com/srcthird/quickshell \
    ~/.config/quickshell
````

Run the shell from the command line:

```bash
quickshell
```

Run it as a daemon:

```bash
quickshell -d
```

To start the shell automatically when Hyprland launches, add this to your `~/.config/hypr/hyprland.conf`:
```conf
exec-once = quickshell
```

### Important

When adding Quickshell to your Hyprland config, use `quickshell` instead of `qs`.

Using `qs` may prevent the `Exit Shell` and `Reload Shell` keybinds from working correctly.

## Project Layout

```text
./
├── assets/               # Wallpapers, presets, sounds, provider configs
├── config/               # Config-facing JavaScript files
│   └── *.js              # Config domain helpers
├── modules/
│   ├── config/           # Config singleton and JSON defaults
│   │   └── defaults/*.js # Default values for each config domain
│   ├── bar/              # Panel widgets: clock, systray, workspaces, indicators
│   ├── components/       # Reusable UI primitives and GLSL shaders
│   ├── corners/          # Rounded screen-corner overlay
│   ├── desktop/          # Desktop background and icon grid
│   ├── dock/             # Application dock
│   ├── frame/            # Screen border and glow effects
│   ├── globals/          # Global runtime state
│   ├── lockscreen/       # Session lock and PAM authentication
│   ├── notch/            # Dynamic island-style UI
│   ├── notifications/    # Notification popups and history
│   ├── services/         # Backend and integration singletons
│   ├── shell/            # Unified shell layers, reservation windows, and OSD
│   ├── theme/            # Colors, icons, and styling singletons
│   ├── tools/            # Screenshot, recording, mirror, and picker tools
│   └── widgets/          # Dashboard, launcher, overview, powermenu, presets, etc.
├── scripts/              # Python and Bash backends
└── shell.qml             # Main entry point
```

## Core Architecture

### Entry Point

The shell starts from `shell.qml`.

From there, `ShellRoot` creates shell layers for each connected display using:

```qml
Variants {
    model: Quickshell.screens
}
```

This allows the shell to automatically adapt to multi-monitor setups.

### Configuration System

Persistent configuration is managed by `modules/config/Config.qml`.

The configuration system uses `FileView` and `JsonAdapter` to keep JSON files on disk synchronized with reactive QML properties. This allows the shell to update dynamically when configuration values change.

### Runtime State

Temporary UI state is stored in:

```text
modules/globals/GlobalStates.qml
```

Use this for non-persistent state such as visibility flags, active UI surfaces, and other runtime-only values.

Persistent settings should remain in the configuration system instead of being stored in `shell.qml`.

### Services

The `modules/services/` directory contains the system integration layer.

Services handle compositor integration, state persistence, visibility coordination, power controls, network status, battery information, AI features, and other system-facing functionality.

### Theming

Shared visual styling lives in `modules/theme/`.

Important theme files include:

* `Colors.qml` — dynamic palette and color data
* `Styling.qml` — sizing, radii, font helpers, and shared style behavior
* `Icons.qml` — icon mapping and icon utilities

## Configuration

The shell is driven by JSON configuration domains managed through `Config.qml`.

When adding a new configuration key, define it in both:

* `modules/config/Config.qml`
* `modules/config/adapters/*.qml`

Common configuration domains include:

* `theme`
* `bar`
* `workspaces`
* `overview`
* `notch`
* `compositor`
* `performance`
* `weather`
* `desktop`
* `lockscreen`
* `prefix`
* `system`
* `dock`
* `ai`
* `binds`

This project assumes a Quickshell-based environment and is designed primarily around a Hyprland workflow.

## Customization

### Config Files

Most customization can be done through the shell’s JSON configuration files.

After saving changes, the shell should update automatically to reflect the new configuration.

### Settings UI

Configuration can also be opened from inside the shell using one of the following methods:

* Press `Super+Shift+C`
* Open the dashboard with `Super+D` and select the cog icon
* Run the IPC command:
```bash
qs ipc call system configs
```

### Presets

After customizing your configuration, it is recommended to save your setup as a preset in:

```text
assets/presets/
```

Saving a preset helps preserve your configuration and prevents it from being overwritten when switching to another preset.
