# Using NagaController

## Set up the app

1. Open NagaController.
2. In macOS System Settings, allow the app under Privacy & Security → Accessibility and Input Monitoring.
3. Quit and reopen the app after granting access.
4. Click its menu bar icon and enable **Enable remapping (blocks original keys)**.
5. Open **Configure mappings…**.

Saving a mapping does not turn remapping on. If a button still types a number, check the switch in the menu bar first. If access was just granted, restart the app.

## Before you start: reset the mouse's on-board profile

The Naga stores its own button assignments in the mouse. If you ever remapped buttons in Razer Synapse on Windows, those assignments stay active over Bluetooth on the Mac and NagaController will not see the buttons it expects (a side button may type `w`, or act as a middle click). If some buttons do nothing in NagaController, connect the mouse to a Windows machine, open Synapse, reset the on-board profile to defaults, then reconnect it to the Mac. NagaController cannot change the on-board profile itself; Razer only exposes that protocol over USB, never over Bluetooth.

## Assign a shortcut

Select a profile, click **Configure** on a button card, and choose the **Key** tab. Click the capture box and press the shortcut you want (for example ⌘C for Copy), or pick one from **Quick Presets…**. The presets also include bare modifier keys, so a side button can act as Shift or Command on its own. Click **Save**.

The **Label / Description** field is only a label. Naming an action "Paste" does not make it paste: the shortcut must be ⌘V.

The other tabs are **App** (open an application), **Cmd** (run a shell command), **Text** (type a snippet), **Profile** (switch profiles, see below), **macOS** (media keys, volume, brightness, Mission Control, Show Desktop) and **Hypershift** (see below).

The trash icon on a card clears that button's mapping.

## Switch profiles with mouse buttons

Create your profiles under **Manage Profiles**. Configure a button, choose the **Profile** tab, select the target profile, and save. Pressing the button switches the active profile immediately; the mapping window and the menu bar title show the new profile.

For example:

| Button | Target profile |
| --- | --- |
| 10 | General |
| 11 | VS Code |
| 12 | Codex |

Set these buttons in every profile you want to switch from. They are not global. You can duplicate a profile to keep the same switching buttons.

Switching a profile changes the button mappings; it does not open or focus an application. Automatic switching based on the active application is not implemented.

## Hypershift: a second layer of mappings

Hypershift gives every button a second action while a chosen button is held or toggled, like Fn on a keyboard.

1. Configure the button you want as the Hypershift key, choose the **Hypershift** tab, and pick **Hold to Activate** or **Click to Toggle**. Save.
2. In the mapping window, turn on the **Hypershift** toggle in the top bar. It turns green and the cards now show the Hypershift layer, which starts empty.
3. Configure the buttons you want on that layer as usual. The editor also has a **Standard Layer / Hypershift Layer** switch at the top, so you can edit both layers of a button in one place.

While Hypershift is active, buttons without a Hypershift mapping fall back to their standard mapping. In toggle mode, holding the Hypershift button for longer than half a second always turns Hypershift off, in case you lose track of its state.

## DPI buttons

The two buttons behind the scroll wheel appear as **DPI Up** and **DPI Down** in the mapping window. They can be mapped like any other button, with one catch.

### Out of the box: mapped action plus a DPI change

With the mouse at its default on-board profile, pressing a DPI button changes the mouse's sensitivity in the mouse itself, and NagaController runs your mapped action as well. Blocking the original keys cannot stop the sensitivity change, because it happens in the mouse firmware, not on the Mac. NagaController actually detects these presses by watching the DPI change, so the first press after launching the app or reconnecting the mouse only records the current DPI and fires nothing.

### Recommended: reassign the DPI buttons in Synapse, then learn them

To use the DPI buttons purely as extra buttons, give them a keyboard key in the on-board profile and let NagaController learn that key. Tested on a Naga V2 HyperSpeed over Bluetooth:

1. Connect the mouse to a Windows computer with its 2.4 GHz receiver and open Razer Synapse.
2. Assign **F16** to DPI Up and **F17** to DPI Down under **Keyboard Function**. F13 and F14 also work, but macOS treats F14 and F15 as brightness keys, so they dim or brighten the screen whenever NagaController is not running. F16 through F19 have no default function on a Mac.
3. Quit Synapse, power the mouse off and on, and reconnect it to the Mac over Bluetooth. The DPI buttons no longer change sensitivity.
4. In NagaController, click **Configure** on the **DPI Up** card, then **Learn Hardware Trigger…** at the bottom of the editor, and press DPI Up on the mouse within a second. The **Trigger:** label changes from "(Default)" to the learned key code. Choose an action and save. Repeat for **DPI Down**.

The learned trigger is tied to the mouse, so the same F-key on a keyboard is left alone. Once learned, NagaController blocks the key and runs your action, so nothing leaks through to other apps.

### Alternative: Back/Forward without NagaController

If all you want from the DPI buttons is browser Back and Forward, assign **Mouse Button 4** and **Mouse Button 5** under **Mouse Function** in Synapse instead, test the direction rather than trusting the numbers, and leave DPI Up and DPI Down unmapped in NagaController. Do not combine this with a NagaController mapping: the app only blocks keyboard events, so a mapped Back/Forward button would run both your action and the browser navigation.

Razer's [button mapping instructions](https://mysupport.razer.com/app/answers/detail/a_id/6400/) mention keeping Synapse running. On the tested mouse the on-board assignments kept working over Bluetooth with Synapse closed, but check the behavior on your own mouse and firmware before relying on it.

## Learn Hardware Trigger for other mice

**Learn Hardware Trigger…** is not limited to the DPI buttons. Any button card can learn a trigger from any mouse whose buttons send a distinct signal, which is how NagaController can support Razer mice other than the Naga. It works best when the button sends a keystroke; buttons that send only a mouse click can currently be learned for the DPI Up and DPI Down cards, but not for the twelve side button cards. Clear a learned trigger with the small ⓧ next to the **Trigger:** label.

## Updates and saved settings

The app stores profiles in `~/Library/Application Support/NagaController/profiles.json`. Back up this file before changing builds.

An ad-hoc signed development build needs permissions again after every rebuild, because macOS ties the permission to the exact binary. Reset the stale entries and add the app again:

```bash
tccutil reset Accessibility com.example.NagaController && tccutil reset ListenEvent com.example.NagaController
```

A green permission label alone does not confirm that button interception is working: test a mapped button on selected text.

The app does not set up login startup automatically.
