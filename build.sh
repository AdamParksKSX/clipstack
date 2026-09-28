#!/bin/zsh
# Builds ClipStack.app (release). Universal (arm64 + x86_64) when the
# toolchain supports it, otherwise native arch.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipStack"
BUILD_DIR=".build"
APP="$APP_NAME.app"

# Whether SwiftUI's @State compiles against the given SDK. Newer Command Line
# Tools SDKs (macOS 27+) make @State a macro whose SwiftUIMacros plugin only
# ships with Xcode, so on a CLT-only machine the default SDK can't build us.
swiftui_compiles() {
    print -r -- 'import SwiftUI
struct Probe: View { @State var n = 0; var body: some View { Text("\(n)") } }' |
        xcrun swiftc -typecheck -sdk "$1" -target "$(uname -m)-apple-macos13.0" - >/dev/null 2>&1
}

if [ -z "${SDKROOT:-}" ] && ! swiftui_compiles "$(xcrun --show-sdk-path)"; then
    # Newest installed SDK that works; symlinked aliases are skipped.
    for sdk in "$(xcode-select -p)"/SDKs/MacOSX[0-9]*.sdk(N/nOn); do
        if swiftui_compiles "$sdk"; then
            export SDKROOT="$sdk"
            echo "Default SDK can't compile SwiftUI here; using ${sdk:t}."
            break
        fi
    done
fi

echo "Building (release)…"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN="$BUILD_DIR/apple/Products/Release/ClipStack"
    echo "Built universal binary (arm64 + x86_64)."
else
    echo "Universal build unavailable; building native arch."
    BUILD_FLAGS=(-c release)
    # Some Command Line Tools releases can't initialise SwiftPM's default
    # build system ("Unknown error parsing property list"); the native one works.
    if ! swift build $BUILD_FLAGS 2>/dev/null; then
        BUILD_FLAGS+=(--build-system native)
        swift build $BUILD_FLAGS
    fi
    BIN="$(swift build $BUILD_FLAGS --show-bin-path)/ClipStack"
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
