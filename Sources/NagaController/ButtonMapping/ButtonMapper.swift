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
    // buttonIndex -> (keyCode, flags sent on the key-down, the mapping's own modifiers)
    private var activeHolds: [Int: (code: CGKeyCode, sent: CGEventFlags, mapping: CGEventFlags)] = [:]
    
    // Track standalone modifiers held by mouse buttons (buttonIndex -> modifier flag)
    private var activeModifiers: [Int: CGEventFlags] = [:]
    
    var currentModifierFlags: CGEventFlags {
        var flags: CGEventFlags = []
        for f in activeModifiers.values {
            flags.insert(f)
        }
        return flags
    }

    /// Stamped into `eventSourceUserData` on every event this app synthesizes, so the
    /// event tap can tell them apart from the mouse's own keystrokes. Without this, a
    /// mapping whose output is one of the Naga's own keys (1-0, -, =, e.g. Cmd+1) was
    /// swallowed by our own tap as an auto-repeat of the button that triggered it.
    static let syntheticEventTag: Int64 = 0x4E41_4741 // "NAGA"

    // A private source keeps emitted shortcut modifiers out of the combined source.
    private let keyboardSource = CGEventSource(stateID: .privateState)

    static func modifierReleaseEvents(_ flags: CGEventFlags, physicalFlags: CGEventFlags) -> [CGEvent] {
        let keys: [(CGEventFlags, CGKeyCode)] = [(.maskCommand, 55), (.maskShift, 56),
                                                (.maskAlternate, 58), (.maskControl, 59)]
        return keys.compactMap { flag, code in
            guard flags.contains(flag), !physicalFlags.contains(flag),
                  let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                      virtualKey: code, keyDown: false) else { return nil }
            event.type = .flagsChanged
            event.flags = physicalFlags
            return event
        }
    }

    private func finishShortcut(_ flags: CGEventFlags) {
        for event in Self.modifierReleaseEvents(flags, physicalFlags: physicalModifierFlags) {
            post(event)
        }
    }

    /// Modifier bits that count as "held" for a mapped key. macOS tracks modifier state
    /// per device, so a Shift held on the keyboard is not applied to a keystroke we
    /// synthesize for a mouse button unless we merge it in ourselves (issue #22).
    private static let passthroughModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]

    static func keyDownFlags(mapping: CGEventFlags, physical: CGEventFlags) -> CGEventFlags {
        mapping.union(physical.intersection(passthroughModifiers))
    }

    /// Modifiers currently held on real devices. Inside this app the HID system state
    /// reported no Shift while the keyboard's Shift was down (seen on macOS 26 with the
    /// event tap active) whereas the combined session state did, so read both.
    var physicalModifierFlags: CGEventFlags {
        CGEventSource.flagsState(.hidSystemState).union(CGEventSource.flagsState(.combinedSessionState))
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: ButtonMapper.syntheticEventTag)
        event.post(tap: .cghidEventTap)
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
                Log.debug("[Mapping] Button \(buttonIndex) fallback to Standard mapping (Hypershift active but no specific mapping): \(String(describing: actionToPerform))")
            }
        } else {
            actionToPerform = mapping[buttonIndex]
            Log.debug("[Mapping] Button \(buttonIndex) Standard mapping: \(String(describing: actionToPerform))")
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
                        post(event)
                        Log.debug("[Mapping] Modifier hold start: button \(buttonIndex) -> \(stroke.displayLabel), cumulative flags: \(event.flags)")
                    }
                    return
                }

                let resolved = resolve(stroke)
                let flags = modifierFlags(from: stroke.modifiers).union(resolved?.extraFlags ?? [])
                if let code = resolved?.code, let eventDown = CGEvent(keyboardEventSource: keyboardSource, virtualKey: code, keyDown: true) {
                    let sent = Self.keyDownFlags(mapping: flags, physical: physicalModifierFlags)
                    eventDown.flags = sent
                    post(eventDown)
                    activeHolds[buttonIndex] = (code, sent, flags)
                    Log.debug("[Mapping] Hold start for button \(buttonIndex) -> key=\(stroke.displayLabel), flags=\(flags), sent=0x\(String(sent.rawValue, radix: 16))")
                } else {
                    // If no keycode, fallback to sending sequence taps to stay functional
                    for stroke in keys { sendKeyStroke(stroke, withPhysicalModifiers: true) }
                }
            } else {
                for stroke in keys { sendKeyStroke(stroke, withPhysicalModifiers: true) }
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
            } else if mode == .toggle {
                // Long-hold (> 0.5s) force-deactivates Hypershift, giving users an escape hatch.
                // Short taps still behave as normal toggle (on/off).
                let holdDuration = CFAbsoluteTimeGetCurrent() - lastHypershiftPressTime
                if holdDuration > 0.5, isHypershiftToggled {
                    isHypershiftToggled = false
                    NSLog("[Mapping] Hypershift TOGGLE force-deactivated via long hold (\(String(format: "%.2f", holdDuration))s)")
                }
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
                    post(event)
                    Log.debug("[Mapping] Modifier hold end: button \(buttonIndex) -> \(stroke.displayLabel), cumulative flags: \(event.flags)")
                }
            }
            return
        }
        
        if let hold = activeHolds.removeValue(forKey: buttonIndex) {
            if let eventUp = CGEvent(keyboardEventSource: keyboardSource, virtualKey: hold.code, keyDown: false) {
                // Mirror the key-down. A key-up carrying fewer modifiers than the user is
                // physically holding makes macOS treat those modifiers as released, so the
                // next mapped press lost a held Shift (issue #22 follow-up).
                eventUp.flags = hold.sent
                post(eventUp)
                finishShortcut(hold.mapping)
                Log.debug("[Mapping] Hold end for button \(buttonIndex)")
            }
        }
    }

    private func perform(action: ActionType) {
        switch action {
        case .keySequence(let keys, _):
            for stroke in keys {
                sendKeyStroke(stroke, withPhysicalModifiers: true)
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
        // Handle non-media special OS keys via native CGEvent emulation.
        // Both cases post a raw virtualKey down+up pair directly to the HID event tap,
        // avoiding shell subprocesses, AppleScript overhead, and sandbox restrictions.
        switch key {
        case .showDesktop:
            // Virtual key 103 = kVK_F11, the macOS default "Show Desktop" key.
            // Using CGEvent mirrors exactly what the previous osascript was doing
            // but without a shell process or permission friction.
            if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 103, keyDown: true) { post(eventDown) }
            if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 103, keyDown: false) { post(eventUp) }
            return
        case .missionControl:
            // Virtual key 160 = NX_KEYTYPE_MISSION_CONTROL mapped through the HID system.
            if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 160, keyDown: true) { post(eventDown) }
            if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 160, keyDown: false) { post(eventUp) }
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

        if let e = keyDown?.cgEvent { post(e) }
        if let e = keyUp?.cgEvent { post(e) }
    }

    private func sendKeyStroke(_ stroke: KeyStroke, withPhysicalModifiers: Bool = false) {
        // Map simple keys (letters) to key codes; limited for Phase 1
        guard let resolved = resolve(stroke) else { return }
        let keyCode = resolved.code
        let flags = modifierFlags(from: stroke.modifiers).union(resolved.extraFlags)

        let sent = withPhysicalModifiers
            ? Self.keyDownFlags(mapping: flags, physical: physicalModifierFlags)
            : flags

        // Key down
        if let eventDown = CGEvent(keyboardEventSource: keyboardSource, virtualKey: keyCode, keyDown: true) {
            eventDown.flags = sent
            post(eventDown)
        }
        // Key up mirrors the key-down (see handleRelease); synthetic modifiers are then
        // released explicitly by finishShortcut.
        if let eventUp = CGEvent(keyboardEventSource: keyboardSource, virtualKey: keyCode, keyDown: false) {
            eventUp.flags = sent
            post(eventUp)
            finishShortcut(flags)
        }
    }

    /// Key code for a stroke plus any flags the current layout needs to produce it.
    /// Single printable characters are resolved against the active keyboard layout so a
    /// mapping recorded as "x" types x on Dvorak too (issue #10); everything else uses the
    /// recorded key code or the static table.
    private func resolve(_ stroke: KeyStroke) -> (code: CGKeyCode, extraFlags: CGEventFlags)? {
        if stroke.key.count == 1, let key = KeyboardLayout.shared.key(for: stroke.key) {
            return (key.code, key.needsShift ? .maskShift : [])
        }
        if let code = stroke.keyCode {
            return (CGKeyCode(code), [])
        }
        return KeyStroke.keyCode(for: stroke.key).map { (CGKeyCode($0), []) }
    }

    private func effectiveKeyCode(for stroke: KeyStroke) -> CGKeyCode? {
        resolve(stroke)?.code
    }

    private func modifierFlags(from modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for m in modifiers.map({ $0.lowercased() }) {
            switch m {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
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
