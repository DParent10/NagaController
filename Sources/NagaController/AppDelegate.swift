import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let eventTapManager = EventTapManager.shared
    private var batteryObserver: NSObjectProtocol?
    private var didAlertLowBattery = false
    private var useEmojiInStatus = false

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
        updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)

        // Start event tap based on persisted setting
        let remapEnabled = ConfigManager.shared.getRemappingEnabled()
        eventTapManager.start(listenOnly: !remapEnabled)
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.stop()
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
        if let lvl = level {
            button.title = (hasImage ? " " : "🖱️ ") + "\(lvl)%"
            button.toolTip = "Naga battery: \(lvl)%"
        } else {
            button.title = hasImage ? "" : "🖱️"
            button.toolTip = "Naga battery: —"
        }
    }

    private func requestNotificationAuthorizationIfPossible() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] Skipping authorization; bundle identifier missing (likely running via swift run).")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
