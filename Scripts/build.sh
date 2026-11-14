#!/bin/bash
# Builds build/Shotput.app. Pass --install to copy it to /Applications and launch it.
#
# Signing prefers a "Developer ID Application" identity, the one notarized releases need, and
# falls back to "Apple Development", then ad-hoc. Keeping one identity means macOS keeps the
# Screen Recording grant across rebuilds. Override with SHOTPUT_SIGN_IDENTITY ("-" for ad-hoc).
#
# SHOTPUT_VERSION sets the version shown in About, for example 0.2.0. It defaults to the
# latest git tag, so local builds and release builds read the same.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${SHOTPUT_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${SHOTPUT_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

if [ "${SHOTPUT_UNIVERSAL:-0}" = "1" ]; then
    ARCHS=(--arch arm64 --arch x86_64)
else
    ARCHS=()
fi
swift build -c release --product Shotput ${ARCHS[@]+"${ARCHS[@]}"}
BINARY="$(swift build -c release --product Shotput ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Shotput"

APP="build/Shotput.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Shotput"
# Local symbols are only for debuggers; dropping them cuts the binary by about 60%. Crash
# reports still name Shotput's functions.
strip -x "$APP/Contents/MacOS/Shotput"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Translations. Every Resources/<language>.lproj goes into the bundle untouched, so adding a
# language is adding a folder and nothing else.
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

# Sparkle, for updates. SwiftPM leaves the framework next to the binary.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$(dirname "$BINARY")/Sparkle.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Shotput" 2>/dev/null || true

find_identity() { security find-identity -v -p codesigning | awk -v kind="$1" '$0 ~ kind { print $2; exit }'; }
IDENTITY="${SHOTPUT_SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
IDENTITY="${IDENTITY:-$(find_identity "Apple Development")}"
IDENTITY="${IDENTITY:--}"
# A secure timestamp is required for notarization. Ad-hoc signatures cannot carry one.
TIMESTAMP=(--timestamp)
[ "$IDENTITY" = "-" ] && TIMESTAMP=(--timestamp=none)
# Inside out: Sparkle's helpers, then the framework, then the app. The Downloader keeps its own
# entitlements, which give it, and only it, the network.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --options runtime "${TIMESTAMP[@]}" --sign "$IDENTITY" "$@"; }
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime "${TIMESTAMP[@]}" --entitlements Resources/Shotput.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER), signed by $(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority/ { print $2; exit }' || true)"

if [ "${1:-}" = "--install" ]; then
    pkill -x Shotput 2>/dev/null || true
    rm -rf /Applications/Shotput.app
    cp -R "$APP" /Applications/Shotput.app
    open /Applications/Shotput.app
    echo "Installed and launched /Applications/Shotput.app"
fi
