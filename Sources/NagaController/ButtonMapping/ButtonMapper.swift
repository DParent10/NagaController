import Cocoa
import Carbon.HIToolbox

final class ButtonMapper {
    static let shared = ButtonMapper()

    private var mapping: [Int: ActionType] = [:]
    private var hypershiftMapping: [Int: ActionType] = [:]
    private var hypershiftHolders: Set<Int> = []
    private var isHypershiftToggled: Bool = false
    private var lastHypershiftPressTime: CFAbsoluteTime = 0
    
    private var isHypershiftActive: Bool {
        return !hypershiftHolders.isEmpty || isHypershiftToggled
    }

    // Track active press-and-hold mappings (buttonIndex -> (keyCode, flags))
    private var activeHolds: [Int: (CGKeyCode, CGEventFlags)] = [:]
    
    // Track standalone modifiers held by mouse buttons (buttonIndex -> modifier flag)
    private var activeModifiers: [Int: CGEventFlags] = [:]
    
    var currentModifierFlags: CGEventFlags {
        var flags: CGEventFlags = []
        for f in activeModifiers.values {
            flags.insert(f)
        }
        return flags
    }

    // Allow external configuration to replace the mapping
    func updateMapping(_ newMapping: [Int: ActionType]) {
        self.mapping = newMapping
        NSLog("[Mapping] Updated mapping for \(newMapping.count) button(s)")
    }

    func updateHypershiftMapping(_ newMapping: [Int: ActionType]) {
        self.hypershiftMapping = newMapping
        NSLog("[Mapping] Updated hypershift mapping for \(newMapping.count) button(s)")
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
        // Handle hypershift button
        if let baseAction = mapping[buttonIndex], case .hypershift(let mode) = baseAction {
            if mode == .hold {
                hypershiftHolders.insert(buttonIndex)
                NSLog("[Mapping] Hypershift activated (physically held by button \(buttonIndex))")
            } else if mode == .toggle {
                isHypershiftToggled.toggle()
                NSLog("[Mapping] Hypershift toggled to \(isHypershiftToggled) by button \(buttonIndex)")
            }
            lastHypershiftPressTime = CFAbsoluteTimeGetCurrent()
            return
        }

        let actionToPerform: ActionType?
        if isHypershiftActive {
            if let hAction = hypershiftMapping[buttonIndex] {
                actionToPerform = hAction
                NSLog("[Mapping] Button \(buttonIndex) matched Hypershift mapping: \(hAction)")
            } else {
                actionToPerform = mapping[buttonIndex]
                NSLog("[Mapping] Button \(buttonIndex) fallback to Standard mapping (Hypershift active but no specific mapping): \(String(describing: actionToPerform))")
            }
        } else {
            actionToPerform = mapping[buttonIndex]
            NSLog("[Mapping] Button \(buttonIndex) Standard mapping: \(String(describing: actionToPerform))")
        }

        guard let action = actionToPerform else {
            NSLog("[Mapping] No action mapped for button \(buttonIndex).")
            return
        }
        
        switch action {
        case .keySequence(let keys, _):
            if let stroke = keys.first, keys.count == 1 {
                let keyCode = effectiveKeyCode(for: stroke)
                
                // NEW: Standalone modifier support (Shift, CMD, etc.)
                if let code = keyCode, let modFlag = modifierFlag(for: code), stroke.modifiers.isEmpty {
                    activeModifiers[buttonIndex] = modFlag
                    if let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) { // FlagsChanged is usually handled by virtualKey + flags
                        event.type = .flagsChanged
                        event.flags = currentModifierFlags
                        event.post(tap: .cghidEventTap)
                        NSLog("[Mapping] Modifier hold start: button \(buttonIndex) -> \(stroke.displayLabel), cumulative flags: \(event.flags)")
                    }
                    return
                }

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
        if let baseAction = mapping[buttonIndex], case .hypershift(let mode) = baseAction {
            if mode == .hold {
                hypershiftHolders.remove(buttonIndex)
                NSLog("[Mapping] Hypershift HELD -> Released. holders=\(hypershiftHolders.count)")
            }
            return
        }

        // Release standalone modifiers
        if let _ = activeModifiers.removeValue(forKey: buttonIndex) {
            // Find keycode from mapping if possible
            let action = isHypershiftActive ? (hypershiftMapping[buttonIndex] ?? mapping[buttonIndex]) : mapping[buttonIndex]
            if case .keySequence(let keys, _) = action, let stroke = keys.first, let code = effectiveKeyCode(for: stroke) {
                if let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
                    event.type = .flagsChanged
                    event.flags = currentModifierFlags
                    event.post(tap: .cghidEventTap)
                    NSLog("[Mapping] Modifier hold end: button \(buttonIndex) -> \(stroke.displayLabel), cumulative flags: \(event.flags)")
                }
            }
            return
        }
        
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
            ConfigManager.shared.setCurrentProfile(profile)
        case .hypershift(_):
            break
        case .mediaKey(let key, _):
            sendMediaKey(key)
        }
    }

    private func sendMediaKey(_ key: MediaKeyType) {
        // Handle non-media special OS keys using standard CGEvent emulation
        switch key {
        case .showDesktop:
            runShell("osascript -e 'tell application \"System Events\" to key code 103'")
            return
        case .missionControl:
            if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 160, keyDown: true) { eventDown.post(tap: .cghidEventTap) }
            if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 160, keyDown: false) { eventUp.post(tap: .cghidEventTap) }
            return
        default: break
        }

        // True NX_SYSDEFINED media keys
        let EV_KEY: Int16 = 8 // NX_SYSDEFINED
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00), // Key down magic flags
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: EV_KEY,
            data1: Int((key.rawValue << 16) | (0xa << 8)), // Key down
            data2: -1
        )
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00), // Key up magic flags
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: EV_KEY,
            data1: Int((key.rawValue << 16) | (0xb << 8)), // Key up
            data2: -1
        )

        keyDown?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
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

    private func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch Int(keyCode) {
        case kVK_Command: return .maskCommand
        case kVK_Shift: return .maskShift
        case kVK_Option: return .maskAlternate
        case kVK_Control: return .maskControl
        case kVK_Function: return .maskSecondaryFn
        default: return nil
        }
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
