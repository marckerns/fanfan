#!/bin/bash
# Build, sign, and notarize fanfan for public distribution.
#
# Requirements (one-time setup):
#   1. "Developer ID Application" cert in your keychain.
#      Verify: security find-identity -v -p codesigning
#   2. notarytool credentials stored under a keychain profile name.
#      Create with:
#        xcrun notarytool store-credentials "fanfan-notarize" \
#          --apple-id <email> --team-id 8FUPL8QHFH --password <app-specific-pw>
#
# Usage: ./scripts/build-release.sh [version]
#   e.g. ./scripts/build-release.sh 0.1.0

set -euo pipefail

VERSION=${1:-"0.1.0"}
APP_NAME="fanfan"
TARGET_NAME="fanfan"
TEAM_ID="8FUPL8QHFH"
SIGN_IDENTITY="Developer ID Application: HAOBIN WU (${TEAM_ID})"
NOTARY_PROFILE="${NOTARY_PROFILE:-fanfan-notarize}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/release-build"
RELEASE_DIR="$PROJECT_DIR/releases"
ENTITLEMENTS="$PROJECT_DIR/fanfan/Resources/fanfan.entitlements"
DAEMON_SRC_DIR="$PROJECT_DIR/tools/fanfan-smcd"
DAEMON_BUNDLED="$PROJECT_DIR/fanfan/Resources/fanfan-smcd"

ARCHIVE_NAME="${APP_NAME}-v${VERSION}-macos"

# --- preflight ---------------------------------------------------------------

echo "🔍 Preflight checks"

if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "❌ Signing identity not found in keychain: $SIGN_IDENTITY"
    echo "   Run: security find-identity -v -p codesigning"
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "❌ notarytool profile '$NOTARY_PROFILE' not found."
    echo "   Create with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "      --apple-id <email> --team-id $TEAM_ID --password <app-specific-pw>"
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ Missing entitlements file: $ENTITLEMENTS"
    exit 1
fi

echo "   ✓ signing identity ready"
echo "   ✓ notarytool profile '$NOTARY_PROFILE'"
echo "   ✓ entitlements file present"

# --- daemon ------------------------------------------------------------------

echo ""
echo "🛠  Rebuilding privileged daemon"
make -C "$DAEMON_SRC_DIR" clean >/dev/null
make -C "$DAEMON_SRC_DIR" >/dev/null

# Refresh the bundled copy Xcode picks up as a resource.
cp "$DAEMON_SRC_DIR/fanfan-smcd" "$DAEMON_BUNDLED"
echo "   ✓ refreshed $DAEMON_BUNDLED"

# --- build -------------------------------------------------------------------

echo ""
echo "🔨 Building $APP_NAME v$VERSION (Release)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

cd "$PROJECT_DIR"
xcodebuild \
    -project fanfan.xcodeproj \
    -scheme "$TARGET_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    clean build \
    > "$BUILD_DIR/xcodebuild.log" 2>&1 || {
        echo "❌ xcodebuild failed. Last 30 lines of log:"
        tail -30 "$BUILD_DIR/xcodebuild.log"
        exit 1
    }

BUILT_APP=$(find "$BUILD_DIR/Build/Products/Release" -maxdepth 2 -name "${TARGET_NAME}.app" -type d | head -n 1)
if [ ! -d "$BUILT_APP" ]; then
    echo "❌ Built app not found under $BUILD_DIR"
    exit 1
fi

RELEASE_APP="$RELEASE_DIR/${APP_NAME}.app"
rm -rf "$RELEASE_APP"
cp -R "$BUILT_APP" "$RELEASE_APP"
echo "   ✓ staged: $RELEASE_APP"

# --- sign --------------------------------------------------------------------

echo ""
echo "✍️  Code-signing with Developer ID"

# Inner-most first: the daemon binary inside Contents/Resources.
DAEMON_IN_APP="$RELEASE_APP/Contents/Resources/fanfan-smcd"
if [ -f "$DAEMON_IN_APP" ]; then
    codesign --force --timestamp --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$DAEMON_IN_APP"
    echo "   ✓ signed daemon"
else
    echo "⚠️  daemon binary not found in app bundle — Xcode resource copy may have changed"
fi

# Then the app itself with hardened runtime + entitlements.
codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$RELEASE_APP"
echo "   ✓ signed app"

echo ""
echo "🔎 Verifying signature"
codesign --verify --deep --strict --verbose=2 "$RELEASE_APP" 2>&1 | tail -3

# --- notarize ----------------------------------------------------------------

echo ""
echo "📤 Submitting to Apple notary service (this takes minutes)"

NOTARIZE_ZIP="$BUILD_DIR/${ARCHIVE_NAME}-notarize.zip"
ditto -c -k --keepParent "$RELEASE_APP" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m

echo ""
echo "📎 Stapling notarization ticket"
xcrun stapler staple "$RELEASE_APP"
xcrun stapler validate "$RELEASE_APP"

echo "🛡  Gatekeeper assessment"
spctl --assess --type execute --verbose=2 "$RELEASE_APP" 2>&1 || {
    echo "⚠️  spctl assessment did not pass — investigate before shipping."
    exit 1
}

# --- package -----------------------------------------------------------------

echo ""
echo "📦 Packaging signed + stapled artifacts"

cd "$RELEASE_DIR"
rm -f "${ARCHIVE_NAME}.zip" "${ARCHIVE_NAME}.zip.sha256"
rm -f "${ARCHIVE_NAME}.dmg" "${ARCHIVE_NAME}.dmg.sha256"

# Final zip uses ditto so xattrs / metadata survive the round-trip.
ditto -c -k --keepParent "${APP_NAME}.app" "${ARCHIVE_NAME}.zip"
shasum -a 256 "${ARCHIVE_NAME}.zip" > "${ARCHIVE_NAME}.zip.sha256"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "${APP_NAME}.app" \
    -ov -format UDZO \
    "${ARCHIVE_NAME}.dmg" >/dev/null
shasum -a 256 "${ARCHIVE_NAME}.dmg" > "${ARCHIVE_NAME}.dmg.sha256"

echo ""
echo "✨ Release build complete"
echo "📍 $RELEASE_DIR"
ls -lh "$RELEASE_DIR" | grep -E "${ARCHIVE_NAME}\.(zip|dmg|sha256)" | awk '{print "   " $9, "("$5")"}'
echo ""
echo "Next: upload zip + dmg + .sha256 files to GitHub Releases."
