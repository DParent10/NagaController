import Cocoa
import ApplicationServices

final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    func ensureAccessibilityPermission() {
        let trusted = isProcessTrusted()
        NSLog("[Permissions] Accessibility trusted = \(trusted)")
        guard !trusted else { return }
        let key = "hasPromptedAccessibility"
        let hasPrompted = UserDefaults.standard.bool(forKey: key)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !hasPrompted] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !hasPrompted { UserDefaults.standard.set(true, forKey: key) }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentAccessibilityAlertIfNeeded()
        }
    }

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func hasAccessibilityPermission() -> Bool {
        isProcessTrusted()
    }

    func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    func openAccessibilityPreferences() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringPreferences() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    private func presentAccessibilityAlertIfNeeded() {
        guard !isProcessTrusted() else { return }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "NagaController needs Accessibility permission to remap buttons.\n\nPlease add NagaController in:\nSystem Settings → Privacy & Security → Accessibility\n\nYou may need to restart the app after granting permission."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
