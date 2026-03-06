#!/bin/bash

# SilkySnip Package Script
# Usage: ./package.sh

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$BUILD_DIR/release"
PKG_DIR="$BUILD_DIR/package"

# 1. Build the App
echo "🔨 Building Release App..."
"$SCRIPT_DIR/build.sh" release

# 2. Prepare for Packaging
mkdir -p "$PKG_DIR"
APP_PATH="$RELEASE_DIR/SilkySnip.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App not found at $APP_PATH"
    exit 1
fi

echo "📦 Packaging..."

# 3. Create Component Package
# This packages the .app bundle itself
pkgbuild --root "$APP_PATH" \
         --install-location "/Applications/SilkySnip.app" \
         --identifier "com.silkysnip.app" \
         --version "1.0" \
         "$PKG_DIR/SilkySnip_Component.pkg"

# 4. Create Distribution Package
# This creates the final user-facing installer
productbuild --distribution "$PROJECT_DIR/Scripts/distribution.xml" \
             --package-path "$PKG_DIR" \
             --resources "$PROJECT_DIR/Resources" \
             "$PKG_DIR/SilkySnip_Installer.pkg"

# 5. Cleanup
rm "$PKG_DIR/SilkySnip_Component.pkg"

echo "✅ Package created successfully!"
echo "📍 Installer: $PKG_DIR/SilkySnip_Installer.pkg"
open -R "$PKG_DIR/SilkySnip_Installer.pkg"
