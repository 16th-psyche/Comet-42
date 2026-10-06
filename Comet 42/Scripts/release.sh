#!/bin/zsh
# Packages a release: a Universal "Comet 42.app" as a .dmg and a .zip, plus SHA-256 checksums.
# Usage: Scripts/release.sh <version>      e.g. Scripts/release.sh 1.0.0
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
VERSION="${1:?Usage: Scripts/release.sh <version>}"
NAME="Comet-42-$VERSION-macOS-universal"
DIST="$ROOT/dist"
APP="$ROOT/build/Comet 42.app"

VERSION="$VERSION" BUILD_NUMBER="${BUILD_NUMBER:-1}" Scripts/build-app.sh --universal

rm -rf "$DIST" && mkdir -p "$DIST"

# zip: ditto keeps the bundle's signature and extended attributes intact, unlike `zip`.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

# dmg: the app beside an Applications shortcut, the usual drag-to-install window.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Comet 42 $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
    -ov "$DIST/$NAME.dmg"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "Release files in $DIST:"
ls -lh "$DIST" | awk 'NR > 1 {print "  " $5 "  " $9}'
