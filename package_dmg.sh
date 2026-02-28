#!/bin/bash
set -e
APP_PATH="/Applications/PingMonitor.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ PingMonitor.app not found in /Applications"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "Unknown")
echo "📦 Packaging PingMonitor v$VERSION..."

DMG_NAME="PingMonitor-v${VERSION}.dmg"
DMG_PATH="$HOME/Desktop/$DMG_NAME"

TEMP_DIR=$(mktemp -d)
DMG_CONTENTS_DIR="$TEMP_DIR/dmg_contents"
mkdir -p "$DMG_CONTENTS_DIR"

cp -R "$APP_PATH" "$DMG_CONTENTS_DIR/"
cp "README.md" "$DMG_CONTENTS_DIR/" 2>/dev/null || true
ln -s "/Applications" "$DMG_CONTENTS_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "PingMonitor v$VERSION" -srcfolder "$DMG_CONTENTS_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TEMP_DIR"

echo "✅ DMG created at $DMG_PATH"
