#!/usr/bin/env bash
# Build OpenCode Desktop as a pacman package for Manjaro/Arch Linux
# Usage: ./scripts/build-manjaro.sh
# Produces: opencode-desktop-<version>-1-x86_64.pkg.tar.zst

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DESKTOP_DIR/../.." && pwd)"

VERSION=$(bun -e "console.log(require('$DESKTOP_DIR/package.json').version)")
ARCH=$(uname -m)

echo "Building OpenCode Desktop v${VERSION} for Manjaro Linux (${ARCH})"

echo ">> Checking bun dependencies..."
cd "$REPO_ROOT"
bun install --frozen-lockfile 2>/dev/null || bun install

echo ">> Building OpenCode CLI sidecar..."
cd "$REPO_ROOT/packages/opencode"
bun run build --single

echo ">> Copying sidecar binary..."
cd "$DESKTOP_DIR"
mkdir -p src-tauri/sidecars
cp ../opencode/dist/opencode-linux-x64/bin/opencode src-tauri/sidecars/opencode-cli-x86_64-unknown-linux-gnu

echo ">> Building Tauri desktop application..."
TAURI_ENV_TARGET_TRIPLE=x86_64-unknown-linux-gnu bun run tauri build --no-bundle

BINARY="$DESKTOP_DIR/src-tauri/target/release/OpenCode"
SIDECAR="$DESKTOP_DIR/src-tauri/sidecars/opencode-cli-x86_64-unknown-linux-gnu"

if [ ! -f "$BINARY" ]; then
  echo "ERROR: Build failed - binary not found at $BINARY"
  exit 1
fi

echo ">> Creating pacman package..."
PKG_DIR="$DESKTOP_DIR/src-tauri/target/release/bundle/pacman"
PKG_ROOT="$PKG_DIR/opencode-desktop-${VERSION}"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_ROOT/usr/bin"
mkdir -p "$PKG_ROOT/usr/share/applications"
mkdir -p "$PKG_ROOT/usr/share/icons/hicolor/32x32/apps"
mkdir -p "$PKG_ROOT/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$PKG_ROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$PKG_ROOT/usr/share/metainfo"

cp "$BINARY" "$PKG_ROOT/usr/bin/opencode-desktop"
cp "$SIDECAR" "$PKG_ROOT/usr/bin/opencode-cli"
chmod 755 "$PKG_ROOT/usr/bin/opencode-desktop"
chmod 755 "$PKG_ROOT/usr/bin/opencode-cli"

ICONS_DIR="$DESKTOP_DIR/src-tauri/icons/dev"
if [ -f "$ICONS_DIR/32x32.png" ]; then
  cp "$ICONS_DIR/32x32.png" "$PKG_ROOT/usr/share/icons/hicolor/32x32/apps/opencode-desktop.png"
fi
if [ -f "$ICONS_DIR/128x128.png" ]; then
  cp "$ICONS_DIR/128x128.png" "$PKG_ROOT/usr/share/icons/hicolor/128x128/apps/opencode-desktop.png"
fi
if [ -f "$ICONS_DIR/128x128@2x.png" ]; then
  cp "$ICONS_DIR/128x128@2x.png" "$PKG_ROOT/usr/share/icons/hicolor/256x256/apps/opencode-desktop.png"
fi

if [ -f "$DESKTOP_DIR/src-tauri/release/appstream.metainfo.xml" ]; then
  cp "$DESKTOP_DIR/src-tauri/release/appstream.metainfo.xml" "$PKG_ROOT/usr/share/metainfo/ai.opencode.opencode.metainfo.xml"
fi

cat > "$PKG_ROOT/usr/share/applications/opencode-desktop.desktop" << 'DESKTOP'
[Desktop Entry]
Name=OpenCode
Comment=The open source AI coding agent
Exec=opencode-desktop %U
Icon=opencode-desktop
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=OpenCode
MimeType=x-scheme-handler/opencode
Keywords=ai;coding;agent;development;
DESKTOP

cat > "$PKG_DIR/PKGBUILD" << PKGBUILD
pkgname=opencode-desktop
pkgver=${VERSION}
pkgrel=1
pkgdesc='The open source AI coding agent - Desktop Application'
arch=('x86_64')
url='https://github.com/cahlien/opencode'
license=('MIT')
depends=(
  'webkit2gtk-4.1'
  'gtk3'
  'libayatana-appindicator'
  'openssl'
  'libsoup3'
  'glib2'
  'cairo'
  'pango'
  'gdk-pixbuf2'
)
optdepends=(
  'xdg-utils: for xdg-open support'
)
provides=('opencode-desktop')
conflicts=('opencode-desktop-bin' 'opencode-desktop-git')
options=('!strip')

package() {
  cp -r "\$srcdir/../opencode-desktop-\${pkgver}/"* "\$pkgdir/"
}
PKGBUILD

cd "$PKG_DIR"
mkdir -p src
makepkg -f --nodeps --skipchecksums 2>&1

PKG_FILE=$(ls -1 opencode-desktop-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -n "$PKG_FILE" ]; then
  echo ""
  echo "========================================="
  echo "SUCCESS: Package built!"
  echo "Package: $PKG_DIR/$PKG_FILE"
  echo ""
  echo "Install with:"
  echo "  sudo pacman -U $PKG_DIR/$PKG_FILE"
  echo "========================================="
else
  echo "ERROR: Package file not found after makepkg"
  exit 1
fi
