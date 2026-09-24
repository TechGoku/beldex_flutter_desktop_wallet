#!/usr/bin/env bash
# Builds a .deb from the Linux release bundle.
#
#   flutter build linux --release
#   BELDEX_BIN_DIR=/path/to/beldex/bin linux/packaging/build_deb.sh [out_dir]
#
# BELDEX_BIN_DIR must hold the Linux beldexd and beldex-wallet-rpc (they are
# copied into the bundle's bin/); if unset, bin/ must already be in the bundle.
# Needs dpkg-deb, fakeroot and python3-pil.
set -euo pipefail

cd "$(dirname "$0")/../.."
PKG=beldex-flutter-wallet
APPID=io.beldex.beldex_wallet
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
BUNDLE=build/linux/x64/release/bundle
OUT=${1:-build/deb}

[ -x "$BUNDLE/beldex_wallet" ] || { echo "Run 'flutter build linux --release' first" >&2; exit 1; }
if [ -n "${BELDEX_BIN_DIR:-}" ]; then
  mkdir -p "$BUNDLE/bin"
  cp "$BELDEX_BIN_DIR/beldexd" "$BELDEX_BIN_DIR/beldex-wallet-rpc" "$BUNDLE/bin/"
fi
for b in beldexd beldex-wallet-rpc; do
  [ -x "$BUNDLE/bin/$b" ] || { echo "Missing $BUNDLE/bin/$b (set BELDEX_BIN_DIR)" >&2; exit 1; }
done

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ROOT=$STAGE/${PKG}_${VERSION}_amd64
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/$PKG" "$ROOT/usr/bin" "$ROOT/usr/share/applications" \
  "$ROOT/usr/share/icons/hicolor/scalable/apps"

cp -a "$BUNDLE/." "$ROOT/opt/$PKG/"
ln -s "/opt/$PKG/beldex_wallet" "$ROOT/usr/bin/$PKG"

python3 - "$ROOT" "$APPID" <<'EOF'
import os, sys
from PIL import Image
root, appid = sys.argv[1:]
src = Image.open("assets/images/app_icon.png").convert("RGBA")
for s in (32, 48, 64, 128, 256, 512):
    d = f"{root}/usr/share/icons/hicolor/{s}x{s}/apps"
    os.makedirs(d, exist_ok=True)
    src.resize((s, s), Image.LANCZOS).save(f"{d}/{appid}.png")
EOF
cp assets/images/logo.svg "$ROOT/usr/share/icons/hicolor/scalable/apps/$APPID.svg"

# Named after the GTK application id so Wayland shells match the window to it.
cat > "$ROOT/usr/share/applications/$APPID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Beldex Wallet
GenericName=Cryptocurrency Wallet
Comment=Desktop wallet for Beldex (BDX)
Exec=/opt/$PKG/beldex_wallet
Icon=$APPID
Terminal=false
Categories=Finance;Network;
Keywords=beldex;bdx;wallet;crypto;
StartupWMClass=beldex_wallet
StartupNotify=true
EOF

find "$ROOT" -type d -exec chmod 0755 {} +
find "$ROOT" -type f -perm -u+x -exec chmod 0755 {} +
find "$ROOT" -type f ! -perm -u+x -exec chmod 0644 {} +

cat > "$ROOT/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)
Maintainer: Beldex <techgoku@beldex.io>
Homepage: https://github.com/TechGoku/beldex_flutter_desktop_wallet
Depends: libc6 (>= 2.34), libstdc++6, libgcc-s1, zlib1g, libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libatk1.0-0t64 | libatk1.0-0, libcairo2, libcairo-gobject2, libpango-1.0-0, libpangocairo-1.0-0, libgdk-pixbuf-2.0-0 | libgdk-pixbuf2.0-0, libharfbuzz0b, libfontconfig1, libepoxy0
Description: Beldex desktop wallet (Flutter)
 Desktop wallet for Beldex (BDX). Bundles beldexd and beldex-wallet-rpc;
 supports remote, local and local + remote nodes, send/receive with BNS
 names, subaddresses, contacts, master node staking and registration,
 BNS names, swaps, proofs and message signing.
EOF

mkdir -p "$OUT"
fakeroot dpkg-deb --build --root-owner-group -Zxz "$ROOT" "$OUT/${PKG}_${VERSION}_amd64.deb"
