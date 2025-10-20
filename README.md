# NagaController

[![GitHub stars](https://img.shields.io/github/stars/DParent10/NagaController?style=social)](https://github.com/DParent10/NagaController)

A macOS menu bar app to remap the 12 side buttons of the Razer Naga V2 Hyperspeed. Intercepts the default 1–0–=– key events and maps them to actions like key sequences, app launching, and macros. Includes Bluetooth battery level display.

**[⬇️ Download Latest Release (v0.1.0)](https://github.com/DParent10/NagaController/releases/latest)**

## Features

- Remap Naga side buttons 1–12 to:
  - Key sequences
  - Launch applications
  - Simple macros
  - Profile switching
- Toggle remapping ON/OFF from the menu bar
- Configure mappings in a dedicated window
- Battery percentage display via Bluetooth (UUID 0x180F / 0x2A19)
- Modern dark UI with Razer-green accents

## Requirements

- macOS 13.0 or later
- Razer Naga V2 Hyperspeed (other Naga models may work; device matching by vendor/product name is included)
- Bluetooth enabled (for battery reporting)

## Installation

1. Download `NagaController-v0.1.0.dmg` from [Releases](https://github.com/DParent10/NagaController/releases/latest)
2. Open the DMG file
3. Drag `NagaController.app` to the Applications folder
4. Double-click `NagaController.app` to launch

### First run setup

1. Click the menu bar icon → turn ON "Enable remapping"
2. Click "Configure mappings…" to set actions for buttons 1–12

### Permissions

- **Accessibility**: System Settings → Privacy & Security → Accessibility → enable "NagaController"
- **Bluetooth (battery)**: System Settings → Privacy & Security → Bluetooth → allow "NagaController"
- **Tip**: Always launch the same `.app` you granted permissions to (avoid running other binaries) so permissions persist

## Known limitations

- Battery percentage works over Bluetooth (BLE) only; vendor 2.4GHz dongles typically don't expose battery via public APIs

## Supported Devices

- Razer Naga family, tested on: `Naga V2 Hyperspeed (Naga V2 HS)`
- Matching logic in `Sources/NagaController/HID/HIDListener.swift`:
  - Vendor IDs: `0x1532` (Razer) or `0x068e` (observed on some Naga V2 HS units)
  - OR product name contains `"naga"` (case-insensitive) as a fallback
- Regular keyboards are not remapped. Events are only blocked when a recent HID press from a matching Naga device is correlated with the event tap

## Troubleshooting

1. Grant Accessibility permissions (System Settings → Privacy & Security → Accessibility) and ensure the app is checked
2. Launch from Terminal to see diagnostics:
   ```bash
   ./NagaController.app/Contents/MacOS/NagaController
   ```
3. Turn ON "Enable remapping" in the menu bar popover
4. Expected logs:
   - Startup:
     - `[HID] Listener started (vendors: 0x68e, 0x1532; plus product contains 'naga')`
     - `[HID] Device matched: vendor=0x68e, product=Naga V2 HS` (your device may vary)
   - On side-button press:
     - `[HID] Press recorded: vendor=0x..., product=..., usage=0x1e, buttonIndex=1` (etc.)
   - On keyboard safety (non-Naga):
     - `[HID] Ignored keyboard usage from device: vendor=0x..., product=...`
5. If mouse buttons still type digits instead of your mapping:
   - Ensure remapping is enabled
   - Verify the Accessibility permission is granted
   - Paste the relevant `[HID] Device matched` and `[HID] Press recorded` lines into an issue so we can whitelist your device if needed

## Battery (Bluetooth)

NagaController can show your mouse battery percentage when the mouse is connected over Bluetooth (BLE). It uses the standard Battery Service (UUID `0x180F`) and Battery Level characteristic (`0x2A19`).

This does not work over the HyperSpeed 2.4GHz dongle — most vendor dongles do not expose battery via public APIs.

### How it works

- On launch, the app requests Bluetooth permission and then:
  - Tries `retrieveConnectedPeripherals(withServices: [0x180F])` to attach to already-connected devices
  - Falls back to scanning for devices that advertise `0x180F` or whose name contains "Razer"/"Naga"
- Once connected, it reads Battery Level and subscribes for updates
- The battery percentage is displayed in the menu bar title and in the popover. At 20% or lower, the popover label turns red and a local notification is shown

### Requirements

- System Settings → Privacy & Security → Bluetooth → allow "NagaController"
- Connect your mouse via Bluetooth and ensure it's awake

### If you see "Battery: —"

- Ensure the device is connected over Bluetooth (not via the HyperSpeed dongle)
- Wake the mouse (move/click) and re-open the popover
- Launch from Terminal to see BLE diagnostics

## Build from source

```bash
# Build release app bundle
bash Scripts/build_app.sh

# Run the app
./NagaController.app/Contents/MacOS/NagaController
```

### Create DMG for distribution

```bash
cd dmg-assets
./setup-app-icon-and-dmg-simple.sh
```

This creates a signed and notarized DMG installer.

## Project Structure

- `Sources/NagaController/` — App source code (Swift + AppKit)
- `Resources/` — Info.plist, default profiles
- `Scripts/` — Build helper scripts
- `Tests/` — Unit tests
- `dmg-assets/` — Icon, background, and DMG creation script

## Feedback

Issues and logs are welcome. If your Naga isn't detected, please include the `[HID]` lines from the app's console output.

## License

See [LICENSE](LICENSE) for details.
