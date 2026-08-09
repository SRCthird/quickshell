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

if [[ "${1:-}" == "--test" ]]; then
  echo "Checking packages in pacman repositories..."
  echo "----------------------------------------"

  for PKG in "${PKGS[@]}"; do
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

## ==============================================================================
## Manually install **self verified** versions of mpvpaper and ttf-phosphor-icons 
## ==============================================================================

if has_pkg "mpvpaper"; then
  log_info "mpvpaper already installed"
else
  log_info "Installing mpvpaper from source..."

  PKG_TMP="$(mktemp -d)"

  cat > "$PKG_TMP/PKGBUILD" <<'EOF'
# Contributor: Lex Black <autumn-wind@web.de>
pkgname=mpvpaper
pkgver=1.9
pkgrel=1
pkgdesc="video wallpaper program for wlroots based wayland compositors"
arch=('i686' 'x86_64')
url="https://github.com/GhostNaN/$pkgname"
license=('GPL3')
depends=('libmpv.so' 'libwayland-client.so' 'libwayland-egl.so')
makedepends=('meson' 'ninja' 'wayland-protocols')
optdepends=('socat: control via sockets')
source=(${pkgname}-${pkgver}.tar.gz::https://github.com/GhostNaN/mpvpaper/archive/${pkgver}.tar.gz)
b2sums=('6b3c148d812d068878ba3acdb48b1f6d376980de3bf7bf23204c906011fd0bb8c0ebbb10fd77de1fcb8b4e3c543a6b5a8f1db92e189b128ec44fdfefbfc4b9bf')

build() {
  arch-meson "$pkgname-$pkgver" build
  meson compile -C build
}

package() {
  meson install -C build --destdir "$pkgdir"

  install -vDm644 "$pkgname-$pkgver"/mpvpaper.man "$pkgdir"/usr/share/man/man1/${pkgname}.1
}
EOF

  (
    cd "$PKG_TMP"
    makepkg -si --noconfirm
  )

  rm -rf "$PKG_TMP"
fi

if has_pkg "ttf-phosphor-icons"; then
  log_info "ttf-phosphor-icons already installed"
else
  log_info "Building and installing ttf-phosphor-icons..."

  PKG_TMP="$(mktemp -d)"

  cat > "$PKG_TMP/PKGBUILD" <<'EOF'
# Maintainer : kStor2poche <kStor2poche [at] orange [dot] fr>
_fontname="phosphor-icons"
pkgname="ttf-${_fontname}"
pkgver="2.1.2"
pkgrel=1
pkgdesc="A flexible icon family for interfaces, diagrams, presentations — whatever, really."
arch=("any")
url="https://phosphoricons.com"
license=("MIT")

source=("${_fontname}-${pkgver}.zip"::"https://github.com/${_fontname}/web/archive/refs/tags/v${pkgver}.zip")
sha256sums=("166c6aa03a64692ed8401c40e51e3b66925d6ea6cbd4ae447699e88dc7c00e60")

package() {
    install -Dm644 "web-${pkgver}/src"/*/*.ttf -t "${pkgdir}/usr/share/fonts/TTF/"
    install -Dm644 "web-${pkgver}/LICENSE" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
EOF

  (
    cd "$PKG_TMP"
    makepkg -si --noconfirm
  )

  rm -rf "$PKG_TMP"
fi

log_info "Installing dependencies with pacman..."
sudo pacman -S --needed --noconfirm "${PKGS[@]}"
