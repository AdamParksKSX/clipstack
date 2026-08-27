#!/bin/zsh
# Builds ClipStack.app (release). Universal (arm64 + x86_64) when the
# toolchain supports it, otherwise native arch.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipStack"
BUILD_DIR=".build"
APP="$APP_NAME.app"

echo "Building (release)…"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN="$BUILD_DIR/apple/Products/Release/ClipStack"
    echo "Built universal binary (arm64 + x86_64)."
else
    echo "Universal build unavailable; building native arch."
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/ClipStack"
fi

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipStack"
cp Bundle/Info.plist "$APP/Contents/Info.plist"
if [ -f Bundle/AppIcon.icns ]; then
    cp Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "ClipMenu Dev"; then
    echo "Code signing with ClipMenu Dev certificate (stable identity)…"
    codesign --force --deep --sign "ClipMenu Dev" "$APP"
else
    echo "Code signing (ad hoc — permissions reset on each rebuild)…"
    codesign --force --deep --sign - "$APP"
fi

echo "Done: $(pwd)/$APP"
lipo -info "$APP/Contents/MacOS/ClipStack" 2>/dev/null || true
