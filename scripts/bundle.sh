#!/bin/bash
# Builds CDesk.app into ./dist (or $DIST_DIR). Usage: scripts/bundle.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="${DIST_DIR:-dist}/CDesk.app"
REPO="${CDESK_REPO:-kalahroudi/cdesk}"
BRANCH="${CDESK_BRANCH:-main}"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$COMMIT" != "unknown" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then COMMIT="$COMMIT-dirty"; fi

swift build -c release --product CDesk
swift build -c release --product cdesk-mcp
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CDesk" "$APP/Contents/MacOS/CDesk"
cp "$BIN/cdesk-mcp" "$APP/Contents/MacOS/cdesk-mcp"

# App icon, drawn by the app itself so no image tools are needed.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN/CDesk" --write-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CDesk</string>
  <key>CFBundleDisplayName</key><string>CDesk</string>
  <key>CFBundleIdentifier</key><string>com.kalahroudi.cdesk</string>
  <key>CFBundleExecutable</key><string>CDesk</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CDeskCommit</key><string>$COMMIT</string>
  <key>CDeskRepo</key><string>$REPO</string>
  <key>CDeskBranch</key><string>$BRANCH</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>CDesk asks Terminal or iTerm to open a shell inside a container.</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Ad-hoc signed by default. With SIGN_IDENTITY set to a "Developer ID Application: ..." identity it is signed
# for distribution with the hardened runtime.
if [ "${SIGN_IDENTITY:--}" = "-" ]; then
  SIGN_FLAGS=(--force --sign -)
else
  SIGN_FLAGS=(--force --timestamp --options runtime --entitlements scripts/CDesk.entitlements --sign "$SIGN_IDENTITY")
fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/cdesk-mcp"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
