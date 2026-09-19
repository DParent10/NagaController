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
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure Accessibility permissions
        PermissionManager.shared.ensureAccessibilityPermission()

        // Load configuration (profiles, settings)
        ConfigManager.shared.load()

        // Start HID listener (filters Naga device presses)
        _ = HIDListener.shared

        // Start Bluetooth battery monitoring (BLE Battery Service 0x180F)
        BatteryMonitor.shared.start()

        // Status bar item (variable length to show %). This is a bonus, convenient path
        // to the popover — but its rendering has been observed to silently fail even with
        // an autosaveName set and free space in the menu bar (see upstream #9 and #11),
        // and AppKit's own visibility flags (`isVisible`, `button.window?.isVisible`)
        // don't reliably reflect that failure either. Reachability must not depend on
        // this succeeding: the Dock icon and main window below are the guaranteed way in.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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

        // The app now always runs with a Dock icon (see Info.plist) instead of trying to
        // detect whether the status item rendered and guessing at a fallback. Show the
        // main window on launch so there's something on screen immediately, and rely on
        // the Dock icon for every future launch/reopen.
        showMainWindow()

        // Start event tap based on persisted setting
        let remapEnabled = ConfigManager.shared.getRemappingEnabled()
        eventTapManager.start(listenOnly: !remapEnabled)
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.stop()
        if let profileObserver { NotificationCenter.default.removeObserver(profileObserver) }
    }

    // Double-clicking the Dock icon, re-opening from Finder, or `open`-ing the app again
    // while it's already running should always bring the window back. This is the
    // guaranteed way in — it does not depend on the menu bar icon having rendered.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        let controller = MainViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "NagaController"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
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
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        mainWindow = nil
    }

    private func requestNotificationAuthorizationIfPossible() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] Skipping authorization; bundle identifier missing (likely running via swift run).")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
