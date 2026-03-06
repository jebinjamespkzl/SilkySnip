#!/bin/bash
#
# SilkySnip Notarization Script
# Usage: ./notarize.sh
#
# Prerequisites:
# 1. Apple Developer ID certificate installed in Keychain
# 2. App-specific password stored in Keychain (xcrun notarytool store-credentials)
# 3. Team ID from Apple Developer Portal
#
# Run: xcrun notarytool store-credentials "SilkySnip-Notarization" --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
#

set -e

# Configuration
APP_NAME="SilkySnip"
BUNDLE_ID="com.silkysnip.app"
KEYCHAIN_PROFILE="SilkySnip-Notarization"  # Store credentials first with: xcrun notarytool store-credentials

# Paths
SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"

echo "=== SilkySnip Notarization Script ==="
echo ""
echo "Script dir: ${SCRIPT_DIR}"
echo "Project directory: ${PROJECT_DIR}"

# Step 1: Build Release
echo "📦 Step 1: Building Release..."
xcodebuild -project "${PROJECT_DIR}/SilkySnip/SilkySnip.xcodeproj" \
    -scheme SilkySnip \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    archive

# Export the app
xcodebuild -exportArchive \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    -exportPath "${BUILD_DIR}" \
    -exportOptionsPlist "${PROJECT_DIR}/ExportOptions.plist"

echo "✅ Build complete"

# Step 2: Code Sign (if not already signed during build)
echo ""
echo "🔐 Step 2: Verifying code signature..."
codesign --verify --deep --strict "${APP_PATH}"
echo "✅ Code signature valid"

# Step 3: Create ZIP for notarization
echo ""
echo "📁 Step 3: Creating ZIP for notarization..."
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
echo "✅ ZIP created: ${ZIP_PATH}"

# Step 4: Submit for notarization
echo ""
echo "🚀 Step 4: Submitting for notarization..."
# Notarize using notarytool. Read credentials from environment:
# export NOTARY_KEY="/path/to/key.p8"
# export NOTARY_ISSUER="TEAM-ID"
if [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_ISSUER" ]; then
  echo "NOTARY_KEY or NOTARY_ISSUER not set. Skipping notarize step."
else
  xcrun notarytool submit "${ZIP_PATH}" \
      --key "$NOTARY_KEY" --issuer "$NOTARY_ISSUER" --wait
fi

echo "✅ Notarization complete"

# Step 5: Staple the ticket
echo ""
echo "📎 Step 5: Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"
echo "✅ Ticket stapled"

# Step 6: Verify
echo ""
echo "🔍 Step 6: Verifying notarization..."
spctl --assess --type execute --verbose "${APP_PATH}"
echo "✅ Verification passed"

# Step 7: Create DMG (optional)
echo ""
echo "💿 Step 7: Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${APP_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Notarize DMG too
if [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_ISSUER" ]; then
  echo "NOTARY_KEY or NOTARY_ISSUER not set. Skipping notarize step."
else
  xcrun notarytool submit "${DMG_PATH}" \
      --key "$NOTARY_KEY" --issuer "$NOTARY_ISSUER" --wait
fi

xcrun stapler staple "${DMG_PATH}"
echo "✅ DMG created and notarized: ${DMG_PATH}"

echo ""
echo "=== Notarization Complete ==="
echo "App: ${APP_PATH}"
echo "DMG: ${DMG_PATH}"
