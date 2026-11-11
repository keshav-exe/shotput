#!/bin/bash
# Cuts a release from this Mac: universal build, Developer ID signature, notarization, and a
# GitHub release with the .dmg, .zip, and checksums.
#
#   Scripts/release.sh 0.2.0
#
# One-time setup: save notary credentials in the keychain (uses an app-specific password from
# appleid.apple.com), then pass the profile name in NOTARY_PROFILE, which defaults to "shotput".
#   xcrun notarytool store-credentials shotput --apple-id you@example.com --team-id TEAMID
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: Scripts/release.sh <version>, for example 0.2.0}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
export NOTARY_PROFILE="${NOTARY_PROFILE:-shotput}"

[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "No notary credentials under '$NOTARY_PROFILE'. See the setup note at the top of this script." >&2
    exit 1
}

swift run shotput-dev editor "$(mktemp -d)/editor.png" >/dev/null
swift run shotput-dev overlay "$(mktemp -d)/overlay.png" >/dev/null
swift run shotput-dev settings "$(mktemp -d)/settings.png" >/dev/null

SHOTPUT_VERSION="$VERSION" SHOTPUT_UNIVERSAL=1 ./Scripts/build.sh
./Scripts/package.sh

git rev-parse "$TAG" >/dev/null 2>&1 || git tag -a "$TAG" -m "Shotput $VERSION"
git push origin "$TAG"
FLAGS=()
case "$TAG" in *-*) FLAGS=(--prerelease) ;; esac
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "build/Shotput-$VERSION.dmg" "build/Shotput-$VERSION.zip" build/checksums.txt --clobber
else
    gh release create "$TAG" ${FLAGS[@]+"${FLAGS[@]}"} --title "Shotput $VERSION" --generate-notes --verify-tag \
        "build/Shotput-$VERSION.dmg" "build/Shotput-$VERSION.zip" build/checksums.txt
fi
