#!/bin/bash

# NagaController - Setup App Icon and DMG with Custom Background
# Simplified version using create-dmg

set -e

echo "🎨 Setting up NagaController icon and DMG background..."

# Check if icon file exists
if [ ! -f "AppIcon.png" ]; then
    echo "❌ Error: AppIcon.png not found!"
    exit 1
fi

# Check if DMG background exists
if [ ! -f "dmg-background.png" ]; then
    echo "❌ Error: dmg-background.png not found!"
    exit 1
fi

echo "📦 Creating .iconset from PNG..."

# Create iconset directory
mkdir -p AppIcon.iconset

# Generate all required icon sizes
sips -z 16 16     AppIcon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     AppIcon.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   AppIcon.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   AppIcon.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   AppIcon.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 AppIcon.png --out AppIcon.iconset/icon_512x512@2x.png

echo "🔨 Converting to .icns format..."
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "📁 Installing icon into app bundle..."
cp AppIcon.icns NagaController.app/Contents/Resources/AppIcon.icns

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" NagaController.app/Contents/Info.plist 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" NagaController.app/Contents/Info.plist

echo "✅ App icon installed!"
rm -rf AppIcon.iconset

echo ""
echo "🎨 Creating DMG with custom background..."

# Sign the app first
codesign --force --deep --sign "Developer ID Application: Devin Parent (SUT6Y24T2J)" --options runtime NagaController.app

# Remove old DMG if exists
rm -f NagaController-v0.1.0.dmg

# Create DMG
# Note: Your embedded text in dmg-background.png will be the primary labels
# Finder labels may still appear but will be secondary/redundant
create-dmg \
  --volname "NagaController" \
  --volicon "AppIcon.icns" \
  --background "dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "NagaController.app" 180 170 \
  --hide-extension "NagaController.app" \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "NagaController-v0.1.0.dmg" \
  "NagaController.app" || {
    echo "Note: create-dmg may show errors but often succeeds anyway"
  }

# Check if DMG was created
if [ ! -f "NagaController-v0.1.0.dmg" ]; then
    echo "❌ DMG creation failed"
    exit 1
fi

echo "✅ DMG created successfully!"
echo ""
echo "🔐 Signing and notarizing DMG..."

# Sign the DMG
codesign --sign "Developer ID Application: Devin Parent (SUT6Y24T2J)" NagaController-v0.1.0.dmg

# Notarize the DMG
echo "Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit NagaController-v0.1.0.dmg --keychain-profile "notary-profile" --wait

# Staple the notarization
xcrun stapler staple NagaController-v0.1.0.dmg

echo ""
echo "✅ Done! Your signed and notarized DMG is ready:"
echo "   📦 NagaController-v0.1.0.dmg"
echo ""
echo "Your embedded text in the background will be the primary visual."
echo "Finder may still show small labels, but your styled text will stand out!"
echo ""
echo "Test it: open NagaController-v0.1.0.dmg"
