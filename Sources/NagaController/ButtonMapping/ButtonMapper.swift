import Cocoa
import Carbon.HIToolbox

final class ButtonMapper {
    static let shared = ButtonMapper()

    // Temporary in-memory mapping for Phase 1
    // 1 -> Cmd+C, 2 -> Cmd+V, others log only
    private var mapping: [Int: ActionType] = [
        1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: "Copy"),
        2: .keySequence(keys: [KeyStroke(key: "v", modifiers: ["cmd"])], description: "Paste")
    ]

    // Track active press-and-hold mappings (buttonIndex -> (keyCode, flags))
    private var activeHolds: [Int: (CGKeyCode, CGEventFlags)] = [:]

    // Allow external configuration to replace the mapping
    func updateMapping(_ newMapping: [Int: ActionType]) {
        self.mapping = newMapping
        NSLog("[Mapping] Updated mapping for \(newMapping.count) button(s)")
    }

    func handle(buttonIndex: Int) {
        guard let action = mapping[buttonIndex] else {
            NSLog("[Mapping] No action mapped for button \(buttonIndex).")
            return
        }
        perform(action: action)
    }

    // Handle physical button press (down). For single-key mappings, send keyDown and remember for hold.
    func handlePress(buttonIndex: Int) {
        guard let action = mapping[buttonIndex] else {
            NSLog("[Mapping] No action mapped for button \(buttonIndex).")
            return
        }
        switch action {
        case .keySequence(let keys, _):
            if let stroke = keys.first, keys.count == 1 {
                let keyCode = effectiveKeyCode(for: stroke)
                let flags = modifierFlags(from: stroke.modifiers)
                if let code = keyCode, let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) {
                    eventDown.flags = flags
                    eventDown.post(tap: .cghidEventTap)
                    activeHolds[buttonIndex] = (code, flags)
                    NSLog("[Mapping] Hold start for button \(buttonIndex) -> key=\(stroke.displayLabel), flags=\(flags)")
                } else {
                    // If no keycode, fallback to sending sequence taps to stay functional
                    for stroke in keys { sendKeyStroke(stroke) }
                }
            } else {
                for stroke in keys { sendKeyStroke(stroke) }
            }
        default:
            perform(action: action)
        }
    }

    // Handle physical button release (up). If we are holding, send keyUp and clear state.
    func handleRelease(buttonIndex: Int) {
        if let (keyCode, flags) = activeHolds.removeValue(forKey: buttonIndex) {
            if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
                eventUp.flags = flags
                eventUp.post(tap: .cghidEventTap)
                NSLog("[Mapping] Hold end for button \(buttonIndex)")
            }
        }
    }

    private func perform(action: ActionType) {
        switch action {
        case .keySequence(let keys, _):
            for stroke in keys {
                sendKeyStroke(stroke)
            }
        case .application(let path, _):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .systemCommand(let command, _):
            runShell(command)
        case .textSnippet(let text, _):
            typeText(text)
        case .macro(let steps, _):
            runMacro(steps)
        case .profileSwitch(let profile, _):
            NSLog("[Mapping] Switch to profile: \(profile) (not implemented)")
        }
    }

    private func sendKeyStroke(_ stroke: KeyStroke) {
        // Map simple keys (letters) to key codes; limited for Phase 1
        guard let keyCode = effectiveKeyCode(for: stroke) else { return }

        let flags = modifierFlags(from: stroke.modifiers)

        // Key down
        if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            eventDown.flags = flags
            eventDown.post(tap: .cghidEventTap)
        }
        // Key up
        if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            eventUp.flags = flags
            eventUp.post(tap: .cghidEventTap)
        }
    }

    private func effectiveKeyCode(for stroke: KeyStroke) -> CGKeyCode? {
        if let code = stroke.keyCode {
            return CGKeyCode(code)
        }
        return KeyStroke.keyCode(for: stroke.key).map { CGKeyCode($0) }
    }

    private func modifierFlags(from modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for m in modifiers.map({ $0.lowercased() }) {
            switch m {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        return flags
    }

    private func runShell(_ command: String) {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-lc", command]
        do {
            try task.run()
        } catch {
            NSLog("[Mapping] Failed to run command: \(command) — error: \(error.localizedDescription)")
        }
    }

    func runMacro(_ steps: [MacroStep]) {
        for step in steps {
            switch step.type {
            case "key":
                if let ks = step.keyStroke { sendKeyStroke(ks) }
            case "text":
                if let text = step.text { pasteText(text) }
            case "delay":
                if let ms = step.delayMs { Thread.sleep(forTimeInterval: TimeInterval(ms) / 1000.0) }
            default:
                break
            }
        }
    }

    private func pasteText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Cmd+V
        sendKeyStroke(KeyStroke(key: "v", modifiers: ["cmd"]))
    }

    private func typeText(_ text: String) {
        for scalar in text.unicodeScalars {
            guard let keyStroke = KeyStroke.fromCharacter(scalar) else { continue }
            sendKeyStroke(keyStroke)
        }
    }
}
