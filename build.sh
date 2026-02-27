#!/bin/bash

set -e

cd "$(dirname "$0")"

BUMP_TYPE="none"
for arg in "$@"; do
    if [ "$arg" == "--feature" ]; then BUMP_TYPE="feature"; fi
    if [ "$arg" == "--bug" ]; then BUMP_TYPE="bug"; fi
done

INFO_PLIST="PingMonitor/Info.plist"
WIDGET_PLIST="PingMonitorWidget/Info.plist"
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "2.1.0")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "68")

NEW_VERSION="$CURRENT_VERSION"
NEW_BUILD="$CURRENT_BUILD"

if [ "$BUMP_TYPE" == "feature" ]; then
    BASE=$(echo "$CURRENT_VERSION" | sed 's/r[0-9]*//')
    IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE"
    NEW_MINOR=$((MINOR + 1))
    NEW_VERSION="$MAJOR.$NEW_MINOR.0"
    NEW_BUILD=$((CURRENT_BUILD + 1))
elif [ "$BUMP_TYPE" == "bug" ]; then
    if [[ "$CURRENT_VERSION" == *r* ]]; then
        BASE_VERSION=${CURRENT_VERSION%%r*}
        R_NUM=${CURRENT_VERSION##*r}
        NEW_R=$((R_NUM + 1))
        NEW_VERSION="${BASE_VERSION}r${NEW_R}"
    else
        NEW_VERSION="${CURRENT_VERSION}r1"
    fi
    NEW_BUILD=$((CURRENT_BUILD + 1))
fi

if [ "$BUMP_TYPE" != "none" ]; then
    echo "📦 升级版本: $CURRENT_VERSION -> $NEW_VERSION (Build $NEW_BUILD)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$WIDGET_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$WIDGET_PLIST" 2>/dev/null || true
    
    sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" project.yml
    sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
else
    echo "📦 使用当前版本: $NEW_VERSION (Build $NEW_BUILD)"
fi

# 生成 Xcode 项目
echo "🔧 生成 Xcode 项目..."
xcodegen generate

# 清理并构建
echo "🚀 开始构建..."
rm -rf ~/Library/Developer/Xcode/DerivedData/PingMonitor-*

xcodebuild -scheme PingMonitor -configuration Release \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/PingMonitor \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    ONLY_ACTIVE_ARCH=NO

APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/PingMonitor/Build/Products/Release/PingMonitor.app"

# 重新签名：先签 widget 扩展（保留其 entitlements），再签主应用
echo "🔐 修复签名..."
WIDGET_PATH="$APP_PATH/Contents/PlugIns/PingMonitorWidget.appex"
if [ -d "$WIDGET_PATH" ]; then
    codesign --force -s - --entitlements PingMonitorWidget/PingMonitorWidget.entitlements "$WIDGET_PATH"
fi
codesign --force -s - --entitlements PingMonitor/PingMonitor.entitlements "$APP_PATH"

# 验证构建
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 构建失败"
    exit 1
fi

# 创建 DMG (带 Applications 快捷入口)
echo "💿 创建 DMG..."
DMG_NAME="PingMonitor-v${NEW_VERSION}.dmg"
DMG_PATH="$HOME/Desktop/$DMG_NAME"

# 创建临时文件夹结构
TEMP_DIR=$(mktemp -d)
DMG_CONTENTS_DIR="$TEMP_DIR/dmg_contents"
mkdir -p "$DMG_CONTENTS_DIR"

# 复制应用到临时目录
cp -R "$APP_PATH" "$DMG_CONTENTS_DIR/"
cp "README.md" "$DMG_CONTENTS_DIR/"

# 创建 Applications 符号链接
ln -s "/Applications" "$DMG_CONTENTS_DIR/Applications"

# 删除旧版本
rm -f "$DMG_PATH"

# 创建 DMG
hdiutil create \
    -volname "PingMonitor v$NEW_VERSION (拖动到 Applications 安装)" \
    -srcfolder "$DMG_CONTENTS_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# 清理临时文件夹
rm -rf "$TEMP_DIR"

# 验证结果
if [ -f "$DMG_PATH" ]; then
    echo ""
    echo "✅ 构建成功!"
    echo "📁 输出位置: $DMG_PATH"
    echo "📊 文件大小: $(du -h "$DMG_PATH" | cut -f1)"
    echo ""
    echo "💡 安装方法:"
    echo "   1. 打开 DMG 文件"
    echo "   2. 将 PingMonitor 拖动到 Applications 文件夹"
    echo "   3. 或点击右下角快捷入口直接打开 Applications"
    ls -lh "$DMG_PATH"
else
    echo "❌ DMG 创建失败"
    exit 1
fi
