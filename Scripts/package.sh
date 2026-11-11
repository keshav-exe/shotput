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

SIGNER="$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority/ { print $2; exit }')"
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

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Shotput $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGING"
case "$SIGNER" in
    "Developer ID Application"*) codesign --force --timestamp --sign "$SIGNER" "$DMG" ;;
esac
notarize "$DMG" "$DMG"

(cd build && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > checksums.txt)
echo "Packaged $ZIP and $DMG (signed by ${SIGNER:-ad-hoc})"
if [ ${#NOTARY_AUTH[@]} -gt 0 ]; then spctl --assess --type open --context context:primary-signature -v "$DMG" || true; fi
cat build/checksums.txt
