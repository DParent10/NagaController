# NagaController

A macOS menu bar app to remap the 12 side buttons of the Razer Naga V2 Hyperspeed. Intercepts the default 1-0-=- key events and maps them to actions like key sequences, app launching, and macros.

## Status
Phase 1: Core EventTap interception and basic mapping with a simple menu bar popover.

## Build
- Debug executable: `swift build`
- Run debug: `.build/debug/NagaController`
- Release app bundle: `Scripts/build_app.sh` → `NagaController.app`

Grant Accessibility permissions when prompted: System Settings → Privacy & Security → Accessibility.

## Structure
- `Sources/NagaController/` — App source code (Swift + AppKit)
- `Resources/` — Info.plist, default profiles
- `Scripts/` — Build helper scripts
- `Tests/` — Unit tests

## Notes
- Default mapping: 1=⌘C, 2=⌘V; others log only in Phase 1.
- Toggle remapping in the popover to block the original events.

## Supported Devices
- Razer Naga family, tested on: `Naga V2 Hyperspeed (Naga V2 HS)`.
- Matching logic in `Sources/NagaController/HID/HIDListener.swift`:
  - Vendor IDs: `0x1532` (Razer) or `0x068e` (observed on some Naga V2 HS units).
  - OR product name contains `"naga"` (case-insensitive) as a fallback.
- Regular keyboards are not remapped. Events are only blocked when a recent HID press from a matching Naga device is correlated with the event tap.

## Troubleshooting
1. Grant Accessibility permissions (System Settings → Privacy & Security → Accessibility) and ensure the app is checked.
2. Launch from Terminal to see diagnostics:
   ```bash
   ./NagaController.app/Contents/MacOS/NagaController
   ```
3. Turn ON "Enable remapping" in the menu bar popover.
4. Expected logs:
   - Startup:
     - `[HID] Listener started (vendors: 0x68e, 0x1532; plus product contains 'naga')`
     - `[HID] Device matched: vendor=0x68e, product=Naga V2 HS` (your device may vary)
   - On side-button press:
     - `[HID] Press recorded: vendor=0x..., product=..., usage=0x1e, buttonIndex=1` (etc.)
   - On keyboard safety (non-Naga):
     - `[HID] Ignored keyboard usage from device: vendor=0x..., product=...`
5. If mouse buttons still type digits instead of your mapping:
   - Ensure remapping is enabled.
   - Verify the Accessibility permission is granted.
   - Paste the relevant `[HID] Device matched` and `[HID] Press recorded` lines into an issue so we can whitelist your device if needed.

## Battery (Bluetooth)
- NagaController can show your mouse battery percentage when the mouse is connected over Bluetooth (BLE). It uses the standard Battery Service (UUID `0x180F`) and Battery Level characteristic (`0x2A19`).
- This does not work over the HyperSpeed 2.4GHz dongle — most vendor dongles do not expose battery via public APIs.

### How it works
- On launch, the app requests Bluetooth permission and then:
  - Tries `retrieveConnectedPeripherals(withServices: [0x180F])` to attach to already-connected devices.
  - Falls back to scanning for devices that advertise `0x180F` or whose name contains "Razer"/"Naga".
- Once connected, it reads Battery Level and subscribes for updates.
- The battery percentage is displayed in the menu bar title and in the popover. At 20% or lower, the popover label turns red and a local notification is shown.

### Requirements
- System Settings → Privacy & Security → Bluetooth → allow "NagaController".
- Connect your mouse via Bluetooth and ensure it’s awake.

### If you see "Battery: —"
- Ensure the device is connected over Bluetooth (not via the HyperSpeed dongle).
- Wake the mouse (move/click) and re-open the popover.
- Launch from Terminal to see BLE diagnostics.
