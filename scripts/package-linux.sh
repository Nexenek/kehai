#!/usr/bin/env bash
# package-linux.sh — tar up the Flutter Linux release bundle for sideloading
# by hand (no distro packaging, no store — see kb/roadmap.md: this app is
# used by exactly two people). Produces:
#
#   dist/kehai-linux-x64-<version>.tar.gz
#     kehai-linux-x64-<version>/
#       bundle/          the full `flutter build linux --release` output
#       install.sh       copies bundle/ to ~/.local/opt/kehai, writes a
#                         ~/.local/share/applications/kehai.desktop entry
#       uninstall.sh      removes both, leaves user data alone
#
# Usage: ./scripts/package-linux.sh   (run from repo root or scripts/)
#
# Assumes `flutter build linux --release` has already been run (this script
# does not build — keeps it fast to re-run while iterating on the packaging
# itself). Run app/tool/generate_tray_icon.py first if the icon changed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
BUNDLE_DIR="$APP_DIR/build/linux/x64/release/bundle"
DIST_DIR="$REPO_ROOT/dist"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "error: $BUNDLE_DIR not found — run 'flutter build linux --release' in app/ first" >&2
  exit 1
fi

VERSION=$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' "$APP_DIR/pubspec.yaml")
if [ -z "$VERSION" ]; then
  echo "error: could not read version from $APP_DIR/pubspec.yaml" >&2
  exit 1
fi

PKG_NAME="kehai-linux-x64-$VERSION"
STAGE_DIR="$DIST_DIR/$PKG_NAME"

echo "packaging $PKG_NAME from $BUNDLE_DIR"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -a "$BUNDLE_DIR" "$STAGE_DIR/bundle"

cat > "$STAGE_DIR/install.sh" <<'INSTALL_EOF'
#!/usr/bin/env bash
# install.sh — copies the Kehai bundle into ~/.local/opt/kehai and registers
# a desktop launcher at ~/.local/share/applications/kehai.desktop. User-scope
# only — no sudo, no system directories touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/opt/kehai"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/kehai.desktop"

if [ ! -d "$SCRIPT_DIR/bundle" ]; then
  echo "error: bundle/ not found next to install.sh — run this from the extracted tar.gz" >&2
  exit 1
fi

echo "installing Kehai to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
cp -a "$SCRIPT_DIR/bundle" "$INSTALL_DIR"

ICON_PATH="$INSTALL_DIR/data/flutter_assets/assets/icons/kehai_icon.png"
if [ ! -f "$ICON_PATH" ]; then
  echo "warning: expected icon not found at $ICON_PATH — launcher entry will have no icon" >&2
  ICON_PATH=""
fi

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Kehai
Comment=Kehai — feel closer, wherever you are
Exec=$INSTALL_DIR/couples_app
Icon=$ICON_PATH
Terminal=false
Categories=Network;Chat;
DESKTOP_EOF

chmod +x "$DESKTOP_FILE"

# Refresh the desktop database if the tool is around, so the launcher shows
# up immediately instead of after the next login.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "installed. Launch from your app menu (Kehai), or run:"
echo "  $INSTALL_DIR/couples_app"
echo
echo "Autostart: use the app's own tray menu toggle once it's running —"
echo "it re-points itself at wherever this was installed."
INSTALL_EOF
chmod +x "$STAGE_DIR/install.sh"

cat > "$STAGE_DIR/uninstall.sh" <<'UNINSTALL_EOF'
#!/usr/bin/env bash
# uninstall.sh — removes the installed bundle and desktop launcher. Leaves
# app data (server config, Tailscale, etc. — Kehai doesn't store anything
# under $INSTALL_DIR itself) untouched. No sudo.
set -euo pipefail

INSTALL_DIR="$HOME/.local/opt/kehai"
DESKTOP_FILE="$HOME/.local/share/applications/kehai.desktop"

if [ -d "$INSTALL_DIR" ]; then
  echo "removing $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
else
  echo "$INSTALL_DIR not found, skipping"
fi

if [ -f "$DESKTOP_FILE" ]; then
  echo "removing $DESKTOP_FILE"
  rm -f "$DESKTOP_FILE"
else
  echo "$DESKTOP_FILE not found, skipping"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

echo "uninstalled Kehai."
UNINSTALL_EOF
chmod +x "$STAGE_DIR/uninstall.sh"

mkdir -p "$DIST_DIR"
TARBALL="$DIST_DIR/$PKG_NAME.tar.gz"
tar -C "$DIST_DIR" -czf "$TARBALL" "$PKG_NAME"
rm -rf "$STAGE_DIR"

echo "wrote $TARBALL"
