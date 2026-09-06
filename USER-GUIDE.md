# Using NagaController

## Set up the app

1. Open NagaController.
2. In macOS System Settings, allow the app under Privacy & Security → Accessibility and Input Monitoring.
3. Quit and reopen the app after granting access.
4. Click its menu bar icon and enable **Enable remapping (blocks original keys)**.
5. Open **Configure mappings…**.

Saving a mapping does not turn remapping on. If a button still types a number, check the switch in the menu bar first. If access was just granted, restart the app.

## Assign a shortcut

Select a profile, click **Edit…** on a button, then choose **Key**. Enter a key such as `c` and select the Command modifier for Copy. Save the action, then use the main **Save** button to save your profiles to disk.

The description is only a label. For example, naming an action "Paste" does not make it paste: the shortcut must be Command+V.

## Switch profiles with mouse buttons

This requires the [profile-switch fix](https://github.com/DParent10/NagaController/pull/12). Older builds may save a Profile action without applying it when pressed.

Create your profiles under **Manage Profiles**. Edit a button, choose **Profile**, select the target profile, and save.

For example:

| Button | Target profile |
| --- | --- |
| 10 | General |
| 11 | VS Code |
| 12 | Codex |

Set these buttons in every profile you want to switch from. They are not global. You can duplicate a profile to keep the same switching buttons.

Switching a profile changes the button mappings; it does not open or focus an application. Automatic switching based on the active application is not implemented.

## DPI buttons and Back/Forward over Bluetooth

On our tested Naga V2 HyperSpeed, mapping DPI Up/Down in NagaController also left the mouse's built-in DPI change active. Blocking the original keys did not prevent the sensitivity change.

This setup worked on that mouse:

1. Connect the mouse to a Windows computer using its 2.4 GHz receiver.
2. In Razer Synapse, select the DPI buttons and assign Back/Forward under **Mouse Function**. The choices may be named **Mouse Button 4** and **Mouse Button 5**. Test the direction instead of relying on the number.
3. Quit Synapse and check both buttons again.
4. Power the mouse off and on, switch to Bluetooth, and test on the Mac.
5. If Back/Forward works without NagaController, leave DPI Up/Down unassigned in NagaController to avoid duplicate actions.

The user confirmed that the assignments continued to work over Bluetooth on their mouse. This is a tested setup, not a guarantee for every Razer model or firmware version.

Razer's [button mapping instructions](https://mysupport.razer.com/app/answers/detail/a_id/6400/) include a requirement to keep Synapse running. Check the behavior on your own mouse before relying on saved assignments.

## Updates and saved settings

The standard app stores profiles in `~/Library/Application Support/NagaController/profiles.json`. Back up this file before changing builds.

An ad-hoc signed development build may need permissions again after rebuilding. Use the same app copy and restart it after granting access. A green permission label alone does not confirm that button interception is working: test a mapped button on selected text.

The app does not set up login startup automatically.
