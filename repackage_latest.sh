#!/bin/bash
set -e

# Configuration
VERSION="2.1.0-r24"
BUILD="89"
APP_NAME="PingMonitor"
SRC_APP_PATH="./build/Debug/PingMonitor.app"
DEST_DMG_PATH="./PingMonitor-v${VERSION}.dmg"

echo "📦 Repackaging PingMonitor to v$VERSION (Build $BUILD)..."

# 1. Update Info.plist in the app bundle
INFO_PLIST="$SRC_APP_PATH/Contents/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    echo "📝 Updating Info.plist..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$INFO_PLIST"
else
    echo "❌ Error: $INFO_PLIST not found"
    exit 1
fi

# 2. Update Widget Info.plist if exists
WIDGET_PLIST="$SRC_APP_PATH/Contents/PlugIns/PingMonitorWidget.appex/Contents/Info.plist"
if [ -f "$WIDGET_PLIST" ]; then
    echo "📝 Updating Widget Info.plist..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$WIDGET_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$WIDGET_PLIST"
fi

# 3. Create DMG
echo "💿 Creating DMG..."
TEMP_DIR="./tmp_repackage"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/dmg_contents"

cp -R "$SRC_APP_PATH" "$TEMP_DIR/dmg_contents/"
cp "README.md" "$TEMP_DIR/dmg_contents/" 2>/dev/null || true
ln -s "/Applications" "$TEMP_DIR/dmg_contents/Applications"

rm -f "$DEST_DMG_PATH"
hdiutil create -volname "PingMonitor v$VERSION" -srcfolder "$TEMP_DIR/dmg_contents" -ov -format UDZO "$DEST_DMG_PATH"

rm -rf "$TEMP_DIR"

echo "✅ Success! Repackaged DMG created at $DEST_DMG_PATH"
