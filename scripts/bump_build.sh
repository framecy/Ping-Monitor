#!/bin/bash

# Configuration
# Use absolute paths if possible, or paths relative to project root
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$PROJECT_ROOT/PingMonitor/Info.plist"
WIDGET_PLIST="$PROJECT_ROOT/PingMonitorWidget/Info.plist"
PROJECT_FILE="$PROJECT_ROOT/project.yml"

# Check if we should skip
if [ "$SKIP_VERSION_BUMP" == "1" ]; then
    echo "⏭ Skipping version bump (SKIP_VERSION_BUMP=1)"
    exit 0
fi

# Get current version and build
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null)
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST" 2>/dev/null)

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not read CFBundleShortVersionString from $INFO_PLIST"
    exit 1
fi

BUMP_TYPE="build"
for arg in "$@"; do
    if [ "$arg" == "--feature" ]; then BUMP_TYPE="feature"; fi
    if [ "$arg" == "--bug" ]; then BUMP_TYPE="bug"; fi
done

# Default: increment build number only
NEW_VERSION="$CURRENT_VERSION"
NEW_BUILD=$((CURRENT_BUILD + 1))

if [ "$BUMP_TYPE" == "feature" ]; then
    # e.g., 2.1.2-R2 -> 2.2.0
    BASE=$(echo "$CURRENT_VERSION" | sed -E 's/(-R[0-9]+|r[0-9]+)//')
    IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE"
    NEW_MINOR=$((MINOR + 1))
    NEW_VERSION="$MAJOR.$NEW_MINOR.0"
elif [ "$BUMP_TYPE" == "bug" ]; then
    # e.g., 2.1.2-R2 -> 2.1.2-R3
    if [[ "$CURRENT_VERSION" == *"-R"* ]]; then
        BASE_VERSION=${CURRENT_VERSION%%-R*}
        R_NUM=${CURRENT_VERSION##*-R}
        NEW_R=$((R_NUM + 1))
        NEW_VERSION="${BASE_VERSION}-R${NEW_R}"
    elif [[ "$CURRENT_VERSION" == *r* ]]; then
        BASE_VERSION=${CURRENT_VERSION%%r*}
        R_NUM=${CURRENT_VERSION##*r}
        NEW_R=$((R_NUM + 1))
        NEW_VERSION="${BASE_VERSION}r${NEW_R}"
    else
        NEW_VERSION="${CURRENT_VERSION}-R1"
    fi
fi

echo "📦 Bumping version: $CURRENT_VERSION ($CURRENT_BUILD) -> $NEW_VERSION ($NEW_BUILD)"

# Update Info.plists
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

if [ -f "$WIDGET_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$WIDGET_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$WIDGET_PLIST"
fi

# Update project.yml
if [ -f "$PROJECT_FILE" ]; then
    sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" "$PROJECT_FILE"
    sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJECT_FILE"
fi

echo "✅ Version updated to $NEW_VERSION ($NEW_BUILD)"
