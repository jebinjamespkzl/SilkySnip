#!/bin/bash

APP_NAME="SilkySnip"
APP_PATH="/Users/jebinjames/Library/Developer/Xcode/DerivedData/SilkySnip-atnsoejyukuwgdchkfsqbxrsxoxj/Build/Products/Release/SilkySnip.app"
DMG_NAME="SilkySnip_Installer.dmg"
VOL_NAME="SilkySnip Installer"
BG_IMG="installer_background_final.png"
SOURCE_FOLDER="SilkySnip_DMG_Source"

# Aggressive Cleanup
hdiutil detach "/Volumes/$VOL_NAME" -force 2>/dev/null || true
rm -rf "$SOURCE_FOLDER" "$DMG_NAME" "temp.dmg"
mkdir "$SOURCE_FOLDER"

# Copy App
cp -r "$APP_PATH" "$SOURCE_FOLDER/"

# Create Applications Link
ln -s /Applications "$SOURCE_FOLDER/Applications"

# Copy Background Image to a hidden folder .background
# mkdir "$SOURCE_FOLDER/.background"
# cp "$BG_IMG" "$SOURCE_FOLDER/.background/"

echo "Creating temporary DMG..."
hdiutil create -volname "$VOL_NAME" -srcfolder "$SOURCE_FOLDER" -ov -format UDRW "temp.dmg"

echo "Mounting temporary DMG..."
device=$(hdiutil attach -readwrite -noverify "temp.dmg" | grep "$VOL_NAME" | awk '{print $1}')

# Critical Sleep for mount to settle
sleep 5

echo "Applying View Options..."
echo "
   tell application \"Finder\"
     tell disk \"$VOL_NAME\"
           open
           delay 1
           
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           set the bounds of container window to {400, 100, 1000, 500}
           
           set theViewOptions to the icon view options of container window
           set arrangement of theViewOptions to not arranged
           set icon size of theViewOptions to 72
           
           # Use the .background folder path
           # Important: HFS path construction
           # set background picture of theViewOptions to file \".background:$BG_IMG\"
           
           # Position
           set position of item \"$APP_NAME\" of container window to {150, 190}
           set position of item \"Applications\" of container window to {450, 190}
           
           update without registering applications
           delay 2
           close
     end tell
   end tell
" | osascript

echo "Unmounting..."
hdiutil detach "$device" -force

echo "Creating final compressed DMG..."
hdiutil convert "temp.dmg" -format UDZO -o "$DMG_NAME"

rm "temp.dmg"
rm -rf "$SOURCE_FOLDER"

echo "Done! Created $DMG_NAME"
