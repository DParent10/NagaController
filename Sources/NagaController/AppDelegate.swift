import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let eventTapManager = EventTapManager.shared
    private var batteryObserver: NSObjectProtocol?
    private var profileObserver: NSObjectProtocol?
    private var didAlertLowBattery = false
    private var useEmojiInStatus = false
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure Accessibility permissions
        PermissionManager.shared.ensureAccessibilityPermission()

        // Load configuration (profiles, settings)
        ConfigManager.shared.load()

        // Start HID listener (filters Naga device presses)
        _ = HIDListener.shared

        // Start Bluetooth battery monitoring (BLE Battery Service 0x180F)
        BatteryMonitor.shared.start()

        // Status bar item (variable length to show %)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable autosaveName lets AppKit persist/restore this item's slot across
        // launches instead of treating it as a brand-new, position-less item every time,
        // which is the leading theory (see upstream #9 and #11) for why the item can
        // silently fail to render even when the menu bar has free space.
        statusItem.autosaveName = "NagaController.statusItem"
        if let button = statusItem.button {
            if let icon = NSImage(named: "MenuBar") {
                icon.isTemplate = true
                button.image = icon
                button.imagePosition = .imageLeading
            } else {
                // Fallback to an SF Symbol if available; else use emoji in the title
                if let sym = UIStyle.symbol("computermouse", size: 14, weight: .regular)
                    ?? UIStyle.symbol("mouse", size: 14, weight: .regular)
                    ?? UIStyle.symbol("battery.100", size: 14, weight: .regular) {
                    sym.isTemplate = true
                    button.image = sym
                    button.imagePosition = .imageLeading
                } else {
                    useEmojiInStatus = true
                }
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Popover content
        popover.behavior = .transient
        if #available(macOS 10.14, *) {
            popover.appearance = NSAppearance(named: .vibrantDark)
        }
        popover.contentViewController = MainViewController()

        // Notifications (low battery alerts)
        requestNotificationAuthorizationIfPossible()

        // Observe battery updates
        batteryObserver = NotificationCenter.default.addObserver(forName: BatteryMonitor.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleBatteryUpdate()
        }
        // Initialize status item text
        profileObserver = NotificationCenter.default.addObserver(
            forName: ConfigManager.profileDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)
        }
        updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)

        // The status item can silently fail to render — seen even with plenty of free
        // space in the menu bar, not just a full one. Check on every launch (not only the
        // first) and guarantee access via a real window if it's genuinely not on screen,
        // rather than relying on a one-shot alert that only ever fires once per install.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.verifyStatusItemVisibleOrFallback()
        }

        // Start event tap based on persisted setting
        let remapEnabled = ConfigManager.shared.getRemappingEnabled()
        eventTapManager.start(listenOnly: !remapEnabled)
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.stop()
        if let profileObserver { NotificationCenter.default.removeObserver(profileObserver) }
    }

    // Called when the already-running app is "opened" again — double-clicking it in
    // Finder, clicking a Dock icon, `open /Applications/NagaController.app`. Without this,
    // re-opening does nothing visible after the one-time first-launch popover has already
    // fired, which reads as "the app doesn't open."
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
        } else if !popover.isShown {
            togglePopover(nil)
        }
        return true
    }

    private func verifyStatusItemVisibleOrFallback() {
        if statusItem.isVisible, let button = statusItem.button, button.window?.isVisible == true {
            // The item is genuinely on screen. Show the popover once per install so
            // first-time users know where the app lives.
            let firstLaunchKey = "NagaController.didShowFirstLaunchPopover"
            if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
                UserDefaults.standard.set(true, forKey: firstLaunchKey)
                NSApp.activate(ignoringOtherApps: true)
                if !popover.isShown {
                    togglePopover(nil)
                }
            }
            return
        }
        // The status item didn't make it onto the menu bar. A process with no Dock icon
        // and no visible menu bar item has no reliable surface to present modal UI on, so
        // don't just show an alert and hope — guarantee a way in with a real window.
        activateFallbackWindow()
    }

    private func activateFallbackWindow() {
        NSLog("[MenuBar] Status item not visible after launch; opening fallback window.")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let controller = MainViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "NagaController"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)

        let alert = NSAlert()
        alert.messageText = "NagaController's menu bar icon didn't appear"
        alert.informativeText = "This can happen even when the menu bar has free space. Use this window instead — it stays reachable from the Dock while it's open, and NagaController goes back to running quietly in the background once you close it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let mainVC = popover.contentViewController as? MainViewController {
                mainVC.refreshPermissionStatuses()
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func handleBatteryUpdate() {
        let level = BatteryMonitor.shared.batteryLevel
        updateStatusItemBattery(level: level)
        guard let lvl = level else { return }
        if lvl <= 20 && !didAlertLowBattery {
            didAlertLowBattery = true
            let content = UNMutableNotificationContent()
            content.title = "Mouse battery low"
            content.body = "Your Naga battery is at \(lvl)%"
            let req = UNNotificationRequest(identifier: "naga.lowbattery", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
        if lvl >= 25 {
            didAlertLowBattery = false
        }
    }

    private func updateStatusItemBattery(level: Int?) {
        guard let button = statusItem.button else { return }
        let hasImage = (button.image != nil)
        let profile = ConfigManager.shared.currentProfileName
        if let lvl = level {
            button.title = (hasImage ? " " : "🖱️ ") + "\(lvl)% · \(profile)"
            button.toolTip = "Naga battery: \(lvl)% · Profile: \(profile)"
        } else {
            button.title = (hasImage ? " " : "🖱️ ") + profile
            button.toolTip = "Naga battery: — · Profile: \(profile)"
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === fallbackWindow else { return }
        fallbackWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func requestNotificationAuthorizationIfPossible() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] Skipping authorization; bundle identifier missing (likely running via swift run).")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
