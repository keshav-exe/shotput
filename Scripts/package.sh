#!/bin/bash
# Packages build/Shotput.app for a GitHub release: build/Shotput-<version>.zip and .dmg, plus
# SHA-256 checksums. Run Scripts/build.sh first.
#
# Notarizes when credentials are available, so the download opens without a warning. Either:
#   NOTARY_PROFILE   a keychain profile saved once with `xcrun notarytool store-credentials`
# or, for CI:
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD (an app-specific password)
# Without them the package is still made, and macOS asks people to approve it on first open.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Shotput.app"
[ -d "$APP" ] || { echo "Run Scripts/build.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
ZIP="build/Shotput-$VERSION.zip"
DMG="build/Shotput-$VERSION.dmg"
rm -f "$ZIP" "$DMG" build/checksums.txt

SIGNER="$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority/ { print $2; exit }' || true)"
if [ -n "${NOTARY_PROFILE:-}" ]; then
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    NOTARY_AUTH=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
else
    NOTARY_AUTH=()
fi

notarize() {
    [ ${#NOTARY_AUTH[@]} -gt 0 ] || return 0
    case "$SIGNER" in
        "Developer ID Application"*) ;;
        *) echo "Skipping notarization: $APP is signed by '${SIGNER:-ad-hoc}', not Developer ID" >&2; return 0 ;;
    esac
    xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait
    xcrun stapler staple "$2"
}

ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP" "$APP"
# Re-zip so the stapled ticket travels with the download.
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"

# The installer window: Shotput on the left, Applications on the right, and the background's
# arrow between them. Finder lays it out from a script, so this needs a Mac with a desktop;
# without one (CI), the disk image is still made, just unstyled.
VOLUME="Shotput $VERSION"
STAGING="$(mktemp -d)"
RW="$(mktemp -u).dmg"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp Resources/Installer/background.png "$STAGING/.background/background.png"
cp Resources/AppIcon.icns "$STAGING/.VolumeIcon.icns"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -ov -format UDRW -fs HFS+ "$RW" >/dev/null 2>&1
rm -rf "$STAGING"

# awk reads to the end rather than exiting early, so hdiutil never writes into a closed pipe.
MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\// { mount = $NF } END { print mount }')"
SetFile -a C "$MOUNT" 2>/dev/null || true
if osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {240, 160, 900, 588}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Shotput.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then
    echo "Styled the installer window"
else
    echo "Could not style the installer window (Finder scripting unavailable); the disk image is plain" >&2
fi
chflags hidden "$MOUNT/.background" "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"
case "$SIGNER" in
    "Developer ID Application"*) codesign --force --timestamp --sign "$SIGNER" "$DMG" ;;
esac
notarize "$DMG" "$DMG"

(cd build && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > checksums.txt)
echo "Packaged $ZIP and $DMG (signed by ${SIGNER:-ad-hoc})"
if [ ${#NOTARY_AUTH[@]} -gt 0 ]; then spctl --assess --type open --context context:primary-signature -v "$DMG" || true; fi
cat build/checksums.txt
