#!/bin/bash
# Cadence release pipeline — build → sign → notarize → staple → DMG.
# Produces a DMG that installs on any Mac with zero Gatekeeper warnings.
# Runs entirely locally (no GitHub Actions needed).
#
# Prereqs (one-time, already done):
#   • A "Developer ID Application" certificate in the login keychain
#   • A notarytool keychain profile (Apple ID + Team ID) stored locally
#
# Signing identity is read from the environment so no personal identifiers
# live in the repo. Set these in your shell (or a gitignored .env.release):
#   export CADENCE_TEAM_ID="XXXXXXXXXX"
#   export CADENCE_SIGN_ID="Developer ID Application: Your Name (XXXXXXXXXX)"
#   export CADENCE_NOTARY_PROFILE="cadence-notary"
#
# Usage:  scripts/release.sh            # uses version from project.yml
#         scripts/release.sh 0.1.1      # override version

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# Pull local defaults if present (gitignored), then env overrides.
[ -f "$(dirname "$0")/../.env.release" ] && source "$(dirname "$0")/../.env.release"

TEAM_ID="${CADENCE_TEAM_ID:?Set CADENCE_TEAM_ID (see header)}"
SIGN_ID="${CADENCE_SIGN_ID:?Set CADENCE_SIGN_ID (see header)}"
NOTARY_PROFILE="${CADENCE_NOTARY_PROFILE:-cadence-notary}"
SCHEME="Cadence"
APP_NAME="Cadence"

VERSION="${1:-$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
DIST="$ROOT/dist"
DERIVED="$ROOT/build/ReleaseDerived"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
# Monotonic build number so Sparkle can always order two builds, even if the
# marketing version is reused during testing.
BUILD_NUMBER="${CADENCE_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

echo "▸ Cadence ${VERSION} — release build"
rm -rf "$DIST" "$DERIVED"
mkdir -p "$DIST"

ENTITLEMENTS="$ROOT/Cadence/Resources/Cadence.entitlements"

echo "▸ Regenerating project + building Release…"
xcodegen generate >/dev/null
# Build without injecting the debug get-task-allow entitlement; we re-sign below.
# MARKETING_VERSION is passed through so a version argument actually reaches
# the bundle. Previously it only renamed the DMG, and Info.plist hardcoded
# CFBundleShortVersionString=1.0 — so every release reported the same version.
# Sparkle compares that string to decide whether an update is newer, so auto
# update could never have fired.
xcodebuild -project Cadence.xcodeproj -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  clean build >/dev/null

APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "✗ Build produced no .app"; exit 1; }

echo "▸ Deep re-signing every nested binary (inside-out) with Developer ID + hardened runtime + timestamp…"
SIGN() { codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$@"; }

# Sparkle ships nested helper apps/XPC services that must each be signed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  V="$SPARKLE/Versions/B"
  [ -d "$V/XPCServices/Downloader.xpc" ] && SIGN "$V/XPCServices/Downloader.xpc"
  [ -d "$V/XPCServices/Installer.xpc" ]  && SIGN "$V/XPCServices/Installer.xpc"
  [ -e "$V/Autoupdate" ]                 && SIGN "$V/Autoupdate"
  [ -d "$V/Updater.app" ]                && SIGN "$V/Updater.app"
  SIGN "$SPARKLE"
fi

# Any other embedded frameworks (Sentry, etc.)
for FW in "$APP"/Contents/Frameworks/*.framework; do
  [ "$FW" = "$SPARKLE" ] && continue
  SIGN "$FW"
done

# Finally the main app, with entitlements (no get-task-allow).
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"

echo "▸ Verifying signature + hardened runtime…"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags.*runtime" | head -2
# Fail early if the debug entitlement survived
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  echo "✗ get-task-allow still present — aborting"; exit 1
fi

echo "▸ Packaging DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --sign "$SIGN_ID" --timestamp "$DMG"

echo "▸ Submitting to Apple for notarization (waits for result, ~2–5 min)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling approval ticket…"
xcrun stapler staple "$DMG"

echo "▸ Final Gatekeeper check (simulates a fresh Mac)…"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | head -3 || true
xcrun stapler validate "$DMG"

echo ""
echo "✅ Done → $DMG"
ls -lh "$DMG" | awk '{print "   size:", $5}'
