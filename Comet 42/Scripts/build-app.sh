#!/bin/zsh
# Builds "Comet 42.app" from the Swift package.
# Usage: Scripts/build-app.sh [--install] [--universal]
#   --universal   one binary for Apple silicon and Intel (slower; used for releases)
#   VERSION=1.2.0 BUILD_NUMBER=3 Scripts/build-app.sh   stamps the bundle version
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/Comet 42.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
INSTALL=false
UNIVERSAL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --universal) UNIVERSAL=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if $UNIVERSAL; then
    # One build per architecture, merged with lipo: multi-arch `swift build` needs full Xcode.
    for arch in arm64 x86_64; do
        swift build -c release --triple "$arch-apple-macosx26.0" --scratch-path "$ROOT/.build/$arch"
    done
    mkdir -p "$ROOT/build"
    BIN="$ROOT/build/Comet-universal"
    lipo -create -output "$BIN" "$ROOT/.build/arm64/release/Comet" "$ROOT/.build/x86_64/release/Comet"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/Comet"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Comet"

# The icon is drawn in code; regenerate the PNG only when the drawing script changes.
ICON_PNG="$ROOT/Resources/AppIcon-1024.png"
if [[ ! -f "$ICON_PNG" || "$ROOT/Scripts/make-icon.swift" -nt "$ICON_PNG" ]]; then
    mkdir -p "$ROOT/Resources"
    swift "$ROOT/Scripts/make-icon.swift" "$ICON_PNG"
fi
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
    sips -z $px $px "$ICON_PNG" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$ICON_PNG" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Comet 42</string>
    <key>CFBundleDisplayName</key><string>Comet 42</string>
    <key>CFBundleIdentifier</key><string>in.quantumleap.comet</string>
    <key>CFBundleExecutable</key><string>Comet</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>Free software under the GNU AGPL-3.0</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Comet 42 reads the text you select and pastes results back into the app you were using.</string>
</dict>
</plist>
PLIST

# A real (self-signed) identity keeps the Accessibility grant across rebuilds; ad hoc does not.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
    | awk '/"Comet Local Signing"/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
    codesign --force --deep --sign "$IDENTITY" --identifier in.quantumleap.comet "$APP"
    echo "Signed with Comet Local Signing"
else
    codesign --force --deep --sign - --identifier in.quantumleap.comet "$APP"
    echo "Signed ad hoc: re-grant Accessibility after every rebuild"
fi
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/Comet"))"

if $INSTALL; then
    mkdir -p "$HOME/Applications"
    pkill -x Comet 2>/dev/null || true
    # The bundle was "Comet.app" before the rename; never leave two copies installed.
    rm -rf "$HOME/Applications/Comet.app" "$HOME/Applications/Comet 42.app"
    cp -R "$APP" "$HOME/Applications/Comet 42.app"
    echo "Installed to ~/Applications/Comet 42.app"
fi
