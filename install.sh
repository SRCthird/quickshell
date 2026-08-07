#!/usr/bin/env bash
set -euo pipefail

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

has_pkg() {
  pacman -Q "$1" >/dev/null 2>&1
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

PKGS=(
  socat kitty tmux fuzzel network-manager-applet blueman
  pipewire wireplumber pavucontrol easyeffects ffmpeg x264 playerctl
  qt6-base qt6-declarative qt6-wayland qt6-svg qt6-tools qt6-imageformats qt6-multimedia qt6-shadertools
  libwebp libavif syntax-highlighting breeze-icons hicolor-icon-theme
  brightnessctl ddcutil fontconfig grim slurp imagemagick jq sqlite upower
  wl-clipboard wlsunset wtype zbar glib2 zenity inetutils power-profiles-daemon
  libnotify tesseract tesseract-data-eng tesseract-data-spa tesseract-data-jpn
  tesseract-data-chi_sim tesseract-data-chi_tra tesseract-data-kor tesseract-data-lat
  ttf-roboto ttf-roboto-mono ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji
  ttf-nerd-fonts-symbols matugen gpu-screen-recorder wl-clip-persist satty
  quickshell ttf-nerd-fonts-symbols adw-gtk-theme
)

AUR_PKGS=(
  mpvpaper
)

if [[ "${1:-}" == "--test" ]]; then
  ALL_PKGS=("${PKGS[@]}")

  for PKG in "${AUR_PKGS[@]}"; do
    ALL_PKGS+=("${PKG%%@*}")
  done

  echo "Checking packages in pacman repositories..."
  echo "----------------------------------------"

  for PKG in "${ALL_PKGS[@]}"; do
    if pacman -Sp "$PKG" &>/dev/null; then
      echo -e "\033[92m[FOUND]\033[0m     $PKG is available in the repositories."
    else
      echo -e "\033[91m[NOT FOUND]\033[0m $PKG does NOT exist in the repositories."
    fi
  done

  return 0 2>/dev/null || exit 0
fi

log_info "Ensuring build dependencies are installed..."
sudo pacman -S --needed --noconfirm git base-devel

log_info "Installing dependencies from source..."

for PKG in "${AUR_PKGS[@]}"; do
  if has_pkg "$PKG"; then
    log_info "$PKG already installed"
    continue
  fi

  log_info "Installing $PKG..."

  PKG_TMP="$(mktemp -d)"

  git clone "https://aur.archlinux.org/${PKG}.git" "$PKG_TMP"

  (
    cd "$PKG_TMP"
    makepkg -si --noconfirm
  )

  rm -rf "$PKG_TMP"
done

log_info "Installing dependencies with pacman..."

sudo pacman -S --needed --noconfirm "${PKGS[@]}"
