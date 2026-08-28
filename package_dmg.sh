#!/bin/bash
set -e
# 打包本地 Debug 构建产物（不做版本递增）。
# 产物路径可用 APP_PATH 环境变量覆盖；默认取仓库内 build/ 下的 Debug 产物。
APP_PATH="${APP_PATH:-$(cd "$(dirname "$0")" && pwd)/build/Build/Products/Debug/PingMonitor.app}"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ PingMonitor.app not found at $APP_PATH"
    echo "   先执行: xcodebuild -scheme PingMonitor -configuration Debug -derivedDataPath ./build build"
    echo "   或指定: APP_PATH=/path/to/PingMonitor.app ./package_dmg.sh"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "Unknown")
echo "📦 Packaging PingMonitor v$VERSION..."

DMG_NAME="PingMonitor-v${VERSION}.dmg"
DMG_PATH="./$DMG_NAME"

TEMP_DIR="./tmp_dmg"
rm -rf "$TEMP_DIR"
DMG_CONTENTS_DIR="$TEMP_DIR/dmg_contents"
mkdir -p "$DMG_CONTENTS_DIR"

cp -R "$APP_PATH" "$DMG_CONTENTS_DIR/"
cp "README.md" "$DMG_CONTENTS_DIR/" 2>/dev/null || true
ln -s "/Applications" "$DMG_CONTENTS_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "PingMonitor v$VERSION" -srcfolder "$DMG_CONTENTS_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TEMP_DIR"

echo "✅ DMG created at $DMG_PATH"
