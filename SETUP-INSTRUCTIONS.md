# Setup Instructions - App Icon & Custom DMG

## Files Included:

1. **AppIcon.png** - Your app icon (1024x1024)
2. **dmg-background.png** - Custom DMG installer background
3. **setup-app-icon-and-dmg.sh** - Automated setup script

## Quick Setup:

### Step 1: Copy files to your project

```bash
# Navigate to your NagaController project directory
cd ~/Documents/GitHub/NagaController

# Copy the files (adjust paths as needed)
cp /path/to/AppIcon.png .
cp /path/to/dmg-background.png .
cp /path/to/setup-app-icon-and-dmg.sh .

# Make the script executable
chmod +x setup-app-icon-and-dmg.sh
```

### Step 2: Run the setup script

```bash
./setup-app-icon-and-dmg.sh
```

This will:
- ✅ Convert your PNG icon to macOS .icns format
- ✅ Install the icon into your app bundle
- ✅ Create a beautiful DMG with custom background
- ✅ Sign and notarize everything automatically

### Step 3: Test the DMG

```bash
# Mount the DMG
open NagaController-v0.1.0.dmg
```

You should see:
- Your custom dark background with Razer green accents
- The NagaController app icon on the left
- Applications folder on the right
- Arrow showing drag-to-install

## Manual Method (if script fails):

### Convert icon to .icns:

```bash
# Create iconset
mkdir -p AppIcon.iconset

# Generate all sizes
for size in 16 32 128 256 512; do
    sips -z $size $size AppIcon.png --out AppIcon.iconset/icon_${size}x${size}.png
    sips -z $((size*2)) $((size*2)) AppIcon.png --out AppIcon.iconset/icon_${size}x${size}@2x.png
done

# Convert to .icns
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# Install into app
cp AppIcon.icns NagaController.app/Contents/Resources/
```

### Create DMG with background:

```bash
create-dmg \
  --volname "NagaController" \
  --volicon "AppIcon.icns" \
  --background "dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "NagaController.app" 180 170 \
  --app-drop-link 480 170 \
  "NagaController-v0.1.0.dmg" \
  "NagaController.app"
```

### Sign and notarize:

```bash
# Sign DMG
codesign --sign "Developer ID Application: Devin Parent (SUT6Y24T2J)" NagaController-v0.1.0.dmg

# Notarize
xcrun notarytool submit NagaController-v0.1.0.dmg --keychain-profile "notary-profile" --wait

# Staple
xcrun stapler staple NagaController-v0.1.0.dmg
```

## Result:

Your NagaController.app will now have:
- ✨ Custom Razer green mouse icon
- 🎨 Professional DMG installer with custom background
- 🔐 Fully signed and notarized
- 📦 Ready for distribution!

## Troubleshooting:

**Icon doesn't show in Finder:**
```bash
# Refresh icon cache
sudo rm -rf /Library/Caches/com.apple.iconservices.store
killall Finder
```

**DMG background doesn't appear:**
- Make sure dmg-background.png is exactly 660x400 pixels
- Try opening the DMG on a different Mac to verify it's not a cache issue

**Code signing fails:**
- Verify your certificate: `security find-identity -v -p codesigning`
- Make sure you're using the correct Team ID: SUT6Y24T2J
