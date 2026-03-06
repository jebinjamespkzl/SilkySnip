#!/bin/bash

# SilkySnip Build Script
# Usage: ./build.sh [debug|release]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$PROJECT_DIR/build"

CONFIG="${1:-debug}"

# Capitalize config name
if [ "$CONFIG" == "release" ]; then
    XCODE_CONFIG="Release"
else
    XCODE_CONFIG="Debug"
fi

echo "🔨 Building SilkySnip ($XCODE_CONFIG)..."

# Check if xcodegen is installed
if command -v xcodegen &> /dev/null; then
    echo "📦 Generating Xcode project..."
    cd "$PROJECT_DIR"
    xcodegen generate
fi

# Check if xcodeproj exists
if [ ! -d "$PROJECT_DIR/SilkySnip.xcodeproj" ]; then
    echo "❌ Error: SilkySnip.xcodeproj not found. Please run 'xcodegen generate' first."
    echo "   Install xcodegen with: brew install xcodegen"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Build the project
# Build the project
XCODEBUILD_CMD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
if [ ! -f "$XCODEBUILD_CMD" ]; then
    XCODEBUILD_CMD="xcodebuild"
fi

"$XCODEBUILD_CMD" -project "$PROJECT_DIR/SilkySnip.xcodeproj" \
    -scheme SilkySnip \
    -configuration "$XCODE_CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    build

# Find the built app
# Find the built app more robustly
APP_PATH="$BUILD_DIR/Build/Products/$XCODE_CONFIG/SilkySnip.app"

if [ -d "$APP_PATH" ]; then
    echo "✅ Build successful!"
    echo "📍 App location: $APP_PATH"
    
    # Clear extended attributes (fixes "killed" on launch)
    xattr -cr "$APP_PATH"
    
    # Ad-hoc sign the application
    codesign -s - --force --deep "$APP_PATH"
    
    # Copy to build/release or build/debug
    OUTPUT_DIR="$BUILD_DIR/$CONFIG"
    mkdir -p "$OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR/SilkySnip.app"
    cp -R "$APP_PATH" "$OUTPUT_DIR/"
    
    echo "📦 Output: $OUTPUT_DIR/SilkySnip.app"
else
    # Fallback search if direct path fails
    APP_PATH=$(find "$BUILD_DIR" -name "SilkySnip.app" -type d | head -1)
    
    if [ -n "$APP_PATH" ]; then
        echo "✅ Build successful (via find)!"
        echo "📍 App location: $APP_PATH"
        
        xattr -cr "$APP_PATH"
        codesign -s - --force --deep "$APP_PATH"
        
        OUTPUT_DIR="$BUILD_DIR/$CONFIG"
        mkdir -p "$OUTPUT_DIR"
        rm -rf "$OUTPUT_DIR/SilkySnip.app"
        cp -R "$APP_PATH" "$OUTPUT_DIR/"
        
        echo "📦 Output: $OUTPUT_DIR/SilkySnip.app"
    else
        echo "❌ Build failed: Could not find SilkySnip.app in $BUILD_DIR"
        exit 1
    fi
fi
