#!/bin/bash

# Increment build number script
# This script will be run by Xcode as a Build Phase

plist="${PROJECT_DIR}/${INFOPLIST_FILE}"
echo "Current Plist Path: ${plist}"

if [ ! -f "$plist" ]; then
    echo "Info.plist not found at ${plist}"
    exit 0
fi

# Get current version
buildNumber=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist")
versionString=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist")

if [ -z "$buildNumber" ]; then
    buildNumber=0
fi

# Increment build number
newBuildNumber=$(($buildNumber + 1))

# Update CFBundleVersion
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $newBuildNumber" "$plist"

# Let's also dynamically update the Short Version String to be something like 1.0.X
# Assuming base version is X.Y, we'll extract that or just use the whole thing.
baseVersion=$(echo "$versionString" | cut -d. -f1-2)

# If it currently doesn't have a 3rd component, or if we want to force it to show the build number:
newVersionString="${baseVersion}.${newBuildNumber}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $newVersionString" "$plist"

echo "Updated Version: ${newVersionString} (${newBuildNumber})"
