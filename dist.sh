#!/bin/zsh
# Builds ClipStack.app and packages it as a drag-to-install DMG in dist/.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "ClipStack.app/Contents/Info.plist")
STAGING="dist/dmg"
DMG="dist/ClipStack-$VERSION.dmg"

echo "Packaging $DMG…"
rm -rf dist
mkdir -p "$STAGING"
cp -R "ClipStack.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "ClipStack $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

# A zip alternative for people who prefer it (preserves code signature).
ditto -c -k --keepParent "ClipStack.app" "dist/ClipStack-$VERSION.zip"

echo "Done:"
ls -lh dist/