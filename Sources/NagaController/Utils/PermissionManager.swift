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
    }

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
