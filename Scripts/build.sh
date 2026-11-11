#!/bin/bash
# Builds build/Shotput.app. Pass --install to copy it to /Applications and launch it.
#
# Signing uses your first "Apple Development" identity, so macOS keeps the Screen Recording
# grant across rebuilds. Override with SHOTPUT_SIGN_IDENTITY, or set it to "-" for ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Shotput

APP="build/Shotput.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Shotput "$APP/Contents/MacOS/Shotput"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SHOTPUT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }')}"
codesign --force --options runtime --entitlements Resources/Shotput.entitlements --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x Shotput 2>/dev/null || true
    rm -rf /Applications/Shotput.app
    cp -R "$APP" /Applications/Shotput.app
    open /Applications/Shotput.app
    echo "Installed and launched /Applications/Shotput.app"
fi
