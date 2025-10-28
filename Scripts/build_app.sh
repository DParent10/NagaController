#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
SCRATCH_DIR="$(mktemp -d /tmp/naga-build-XXXXXX)"
APP_NAME="NagaController"
APP_BUNDLE="$PROJECT_ROOT/$APP_NAME.app"
EXECUTABLE_PATH="$SCRATCH_DIR/release/$APP_NAME"

cleanup() {
  rm -rf "$SCRATCH_DIR"
}
trap cleanup EXIT

echo "Cleaning previous build artifacts..."
rm -rf "$BUILD_DIR" || true
swift package --package-path "$PROJECT_ROOT" clean >/dev/null 2>&1 || true

echo "Building for production..."
# Build release executable
swift build -c release --package-path "$PROJECT_ROOT" --scratch-path "$SCRATCH_DIR"

# Verify the executable was actually built
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "❌ Error: Build failed - executable not found at $EXECUTABLE_PATH"
  exit 1
fi

echo "Creating app bundle..."
# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Icons"

# Copy executable and resources
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$PROJECT_ROOT/Resources/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

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

echo "Code signing..."
# Ad-hoc codesign (helps TCC and launching)
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

# Remove quarantine attributes if present
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Build successful!"
echo "📦 App bundle: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"