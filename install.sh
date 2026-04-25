#!/usr/bin/env bash
set -euo pipefail

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

if ! has_cmd git || ! has_cmd makepkg; then
  log_info "Installing git and base-devel..."
  sudo pacman -S --needed --noconfirm git base-devel
fi

AUR_HELPER=""

if has_cmd yay; then
  AUR_HELPER="yay"
elif has_cmd paru; then
  AUR_HELPER="paru"
else
  log_info "Installing yay..."

  YAY_TMP="$(mktemp -d)"
  trap 'rm -rf "$YAY_TMP"' EXIT

  git clone "https://aur.archlinux.org/yay.git" "$YAY_TMP"
  (
    cd "$YAY_TMP"
    makepkg -si --noconfirm
  )

  AUR_HELPER="yay"
fi

PKGS=(
  socat kitty tmux fuzzel network-manager-applet blueman
  pipewire wireplumber pavucontrol easyeffects ffmpeg x264 playerctl
  qt6-base qt6-declarative qt6-wayland qt6-svg qt6-tools qt6-imageformats qt6-multimedia qt6-shadertools
  libwebp libavif syntax-highlighting breeze-icons hicolor-icon-theme
  brightnessctl ddcutil fontconfig grim slurp imagemagick jq sqlite upower
  wl-clipboard wlsunset wtype zbar glib2 python-pipx zenity inetutils power-profiles-daemon
  python312 libnotify
  tesseract tesseract-data-eng tesseract-data-spa tesseract-data-jpn
  tesseract-data-chi_sim tesseract-data-chi_tra tesseract-data-kor tesseract-data-lat
  ttf-roboto ttf-roboto-mono ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji
  ttf-nerd-fonts-symbols
  matugen gpu-screen-recorder wl-clip-persist mpvpaper gradia
  quickshell ttf-phosphor-icons ttf-league-gothic adw-gtk-theme
)

log_info "Installing dependencies with $AUR_HELPER..."

if [[ ${#PKGS[@]} -gt 0 ]]; then
  "$AUR_HELPER" -S --needed --noconfirm "${PKGS[@]}"
else
  log_info "All packages already installed"
fi
