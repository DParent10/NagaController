#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
APP_NAME="NagaController"
APP_BUNDLE="$PROJECT_ROOT/$APP_NAME.app"
EXECUTABLE_PATH="$BUILD_DIR/release/$APP_NAME"

# Clean build cache (helps when build.db is corrupted)
swift package --package-path "$PROJECT_ROOT" clean || true
rm -rf "$BUILD_DIR" || true

# Build release executable
swift build -c release --package-path "$PROJECT_ROOT"

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Icons"

# Copy executable and resources
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$PROJECT_ROOT/Resources/"* "$APP_BUNDLE/Contents/Resources/" || true

# Create/merge Info.plist
if [[ -f "$PROJECT_ROOT/Resources/Info.plist" ]]; then
  cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
  cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.NagaController</string>
  <key>CFBundleName</key>
  <string>NagaController</string>
  <key>CFBundleExecutable</key>
  <string>NagaController</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>NagaController needs to send keyboard events for button remapping.</string>
</dict>
</plist>
PLIST
fi

# Ad-hoc codesign (helps TCC and launching)
codesign --force --deep --sign - "$APP_BUNDLE" || true

# Remove quarantine attributes if present
xattr -dr com.apple.quarantine "$APP_BUNDLE" || true

# Done
echo "Built: $APP_BUNDLE"
