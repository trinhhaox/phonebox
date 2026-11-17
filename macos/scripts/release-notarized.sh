#!/bin/bash
# Build PhoneBox for macOS (universal arm64 + x86_64), sign with Developer ID (cloud-managed through the
# Xcode account), notarize + staple, then pack a signed DMG.
# Usage: DEVELOPER_DIR=<Xcode>/Contents/Developer macos/scripts/release-notarized.sh
# Needs: xcodegen, an Apple account signed in to Xcode for team 4DU4BTV46U, and (for the DMG) the
# "Developer ID Application" identity in the keychain. No secrets live in this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEAM="${XCODE_NOTARIZE_TEAM:-4DU4BTV46U}"
DMG_IDENTITY="${DMG_SIGN_IDENTITY:-Developer ID Application: Trinh Hao (4DU4BTV46U)}"
OUT="${PHONEBOX_MAC_OUT:-/Volumes/XcodeExternal/SharedBuild/phonebox-mac}"
BUILD_DIR="${PHONEBOX_MAC_BUILD:-${TMPDIR:-/tmp}/phonebox-mac-build}"
APP_NAME="PhoneBox"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' PhoneBoxMac/Info.plist)"

echo "==> Generate project"
xcodegen generate >/dev/null

echo "==> Build Release (universal, hardened runtime)"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
xcodebuild -project PhoneBoxMac.xcodeproj -scheme PhoneBoxMac -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" -allowProvisioningUpdates build > "$BUILD_DIR/build.log" 2>&1 \
    || { tail -30 "$BUILD_DIR/build.log" >&2; exit 1; }
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
codesign --verify --deep --strict "$APP"

echo "==> Developer ID signing + notarization"
scripts/notarize-with-xcode.sh "$APP" "$TEAM"

echo "==> DMG"
mkdir -p "$OUT"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -format UDZO "$DMG"
codesign --force --timestamp --sign "$DMG_IDENTITY" "$DMG"
# The Xcode-account flow notarizes apps only, so the DMG goes through notarytool with a keychain profile
# (created once with: xcrun notarytool store-credentials phonebox-notary --apple-id <id> --team-id 4DU4BTV46U).
NOTARY_PROFILE="${NOTARY_PROFILE:-phonebox-notary}"
echo "==> Notarize DMG (profile $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
xcrun stapler staple "$DMG"
ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME-$VERSION-mac.zip"
rm -rf "$OUT/$APP_NAME.app"
ditto "$APP" "$OUT/$APP_NAME.app"

echo "==> Verify"
spctl -a -vvv -t exec "$OUT/$APP_NAME.app" 2>&1 | head -5
xcrun stapler validate "$OUT/$APP_NAME.app" 2>&1 | tail -2
codesign --verify --deep --strict --verbose=2 "$OUT/$APP_NAME.app" 2>&1 | tail -2
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | head -3
ls -la "$OUT"
