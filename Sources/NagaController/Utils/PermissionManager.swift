import Cocoa
import ApplicationServices

final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    func ensureAccessibilityPermission() {
        let trusted = isProcessTrusted()
        NSLog("[Permissions] Accessibility trusted = \(trusted)")
        if !trusted {
            // Prompt the user to grant permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            // Show a non-intrusive alert guiding the user
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "NagaController needs Accessibility access to intercept and remap keys. Please open System Settings → Privacy & Security → Accessibility and enable NagaController. If you added the .app or the debug binary, quit and relaunch after granting."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
