import Cocoa
import ApplicationServices
import Darwin

final class EventTapManager {
    static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Track buttons whose original number keyDown we intercepted so we can also intercept keyUp
    private var activeDownButtons: Set<Int> = []
    private var pointerGeneration = 0
    private var activePointerButtons: [UInt32: Int] = [:]

    // One physical wheel tilt emits a burst of pan reports. Reports arriving
    // within this gap belong to the same gesture, so one tilt performs one action.
    private var lastPanTimestamp: [Int: UInt64] = [:]
    private static let panGestureGapNanos: UInt64 = 150_000_000
    
    private var learningCallback: ((CGKeyCode) -> Void)?

    private(set) var isListeningOnly: Bool = true
    private init() {}

    func setLearningCallback(_ callback: ((CGKeyCode) -> Void)?) {
        learningCallback = callback
    }

    func start(listenOnly: Bool) {
        stop()
        isListeningOnly = listenOnly

        let mask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        NSLog("[EventTap] Starting with listenOnly=\(listenOnly). Remapping should be \(listenOnly ? "DISABLED (Listen Only)" : "ENABLED (Blocking)").")

        var options: CGEventTapOptions = .defaultTap
        if listenOnly {
            options = .listenOnly
        }

        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: CGEventMask(mask),
            callback: EventTapManager.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if tap == nil && !listenOnly {
            NSLog("[EventTap] CRITICAL: Failed to create blocking event tap; falling back to listen-only. Permissions missing?")
            options = .listenOnly
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: options,
                eventsOfInterest: CGEventMask(mask),
                callback: EventTapManager.eventCallback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
            isListeningOnly = true
            DispatchQueue.main.async { [weak self] in self?.promptForInputMonitoring() }
        }
        
        guard let tap = tap else {
            NSLog("[EventTap] FATAL: Failed to create any event tap.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[EventTap] Source added to runloop. Tap enabled.")
        }
    }

    func stop() {
        pointerGeneration += 1
        for index in activePointerButtons.values { ButtonMapper.shared.handleRelease(buttonIndex: index) }
        activePointerButtons.removeAll()
        lastPanTimestamp.removeAll()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let eventCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

        // If tap is disabled by timeout, re-enable
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Inject synthetic flags from mouse-held modifiers (standalone modifiers)
        let mouseMods = ButtonMapper.shared.currentModifierFlags
        if !mouseMods.isEmpty {
            // Apply mouse modifiers to this event (keyboard or mouse)
            event.flags = event.flags.union(mouseMods)
        }

        // Events we synthesized ourselves must never be re-interpreted as Naga presses.
        if event.getIntegerValueField(.eventSourceUserData) == ButtonMapper.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        if !manager.isListeningOnly, manager.deferMappedPointer(type: type, event: event) {
            return nil
        }

        // Only handle remapping/blocking logic for keyboard events
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        if type == .keyDown || type == .flagsChanged {
            if let callback = manager.learningCallback {
                callback(keyCode)
                // Don't returned nil; we want the key to be blocked if we are learning it?
                // Actually, if we are learning, we should probably block it so it doesn't do stuff in the background.
                return nil
            }
        }

        if let buttonIndex = manager.buttonIndex(for: keyCode) {
            let isDown: Bool
            if type == .flagsChanged {
                // If it's already in the set, this flagsChanged is a release
                isDown = !manager.activeDownButtons.contains(buttonIndex)
            } else {
                isDown = (type == .keyDown)
            }

            if isDown {
                // If we already intercepted this button's keyDown, block further keyDowns (e.g., auto-repeat)
                if manager.activeDownButtons.contains(buttonIndex) {
                    return nil
                }
                NSLog("[EventTap] Detected Naga button \(buttonIndex) (keyCode=\(keyCode)).")
                if !manager.isListeningOnly {
                    var recent = HIDListener.shared.wasRecentPress(buttonIndex: buttonIndex)
                    if !recent {
                        for _ in 0..<5 {
                            usleep(2000)
                            if HIDListener.shared.wasRecentPress(buttonIndex: buttonIndex) { recent = true; break }
                        }
                    }
                    if recent {
                        HIDListener.shared.consumeRecentPress(buttonIndex: buttonIndex)
                        ButtonMapper.shared.handlePress(buttonIndex: buttonIndex)
                        manager.activeDownButtons.insert(buttonIndex)
                        return nil
                    }
                }
            } else {
                // If we previously intercepted this button's keyDown, also block keyUp and send release
                if manager.activeDownButtons.contains(buttonIndex) {
                    manager.activeDownButtons.remove(buttonIndex)
                    if !manager.isListeningOnly {
                        ButtonMapper.shared.handleRelease(buttonIndex: buttonIndex)
                    }
                    return nil
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func deferMappedPointer(type: CGEventType, event: CGEvent) -> Bool {
        guard ConfigManager.shared.getRemappingEnabled() else { return false }
        let bindings = ConfigManager.shared.hardwareBindingsForCurrentProfile()
        let kind: PointerInputRouter.Kind
        if type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged {
            let usage = UInt32(event.getIntegerValueField(.mouseEventButtonNumber) + 1)
            if type == .otherMouseDragged { return activePointerButtons[usage] != nil }
            guard bindings.values.contains(where: { $0.usagePage == 9 && $0.usage == usage }) else { return false }
            kind = .button(usage: usage, down: type == .otherMouseDown)
        } else if type == .scrollWheel {
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
                  event.getIntegerValueField(.scrollWheelEventDeltaAxis2) != 0,
                  event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0,
                  bindings.values.contains(where: { $0.usagePage == 12 && $0.usage == 568 }) else { return false }
            kind = .horizontalScroll
        } else { return false }

        guard let original = event.copy() else { return false }
        let generation = pointerGeneration
        // HID and CGEvent callbacks run on this same loop. Sleeping here prevents
        // HID from arriving. Defer briefly instead and replay unmatched input.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            guard let self else { return }
            func replay() {
                original.setIntegerValueField(.eventSourceUserData, value: ButtonMapper.syntheticEventTag)
                original.post(tap: .cgSessionEventTap)
            }
            guard generation == self.pointerGeneration, !self.isListeningOnly,
                  ConfigManager.shared.getRemappingEnabled() else { replay(); return }
            let matched = HIDListener.shared.consumePointer(kind: kind, timestamp: original.timestamp)
            switch kind {
            case .button(let usage, let down):
                if down, let index = matched {
                    guard self.activePointerButtons[usage] == nil else { return }
                    self.activePointerButtons[usage] = index
                    ButtonMapper.shared.handlePress(buttonIndex: index)
                    NSLog("[Pointer] Suppressed native button down; performed slot=%d", index)
                } else if !down, let index = self.activePointerButtons.removeValue(forKey: usage) {
                    ButtonMapper.shared.handleRelease(buttonIndex: index)
                    NSLog("[Pointer] Suppressed native button up; released slot=%d", index)
                } else { replay() }
            case .horizontalScroll:
                guard let index = matched else { replay(); return }
                let now = original.timestamp
                if let previous = self.lastPanTimestamp[index],
                   now >= previous, now - previous < Self.panGestureGapNanos {
                    // Same tilt still streaming. Swallow it: acting again would
                    // repeat the action, replaying it would scroll the page.
                    self.lastPanTimestamp[index] = now
                    return
                }
                self.lastPanTimestamp[index] = now
                ButtonMapper.shared.handlePress(buttonIndex: index)
                ButtonMapper.shared.handleRelease(buttonIndex: index)
                NSLog("[Pointer] Suppressed native pan; performed slot=%d", index)
            }
        }
        return true
    }

    private func promptForInputMonitoring() {
        let alert = NSAlert()
        alert.messageText = "Enable Input Monitoring"
        alert.informativeText = "To block the original number keys, enable Input Monitoring for NagaController in System Settings → Privacy & Security → Input Monitoring."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    private func buttonIndex(for keyCode: CGKeyCode) -> Int? {
        // Check dynamic bindings first
        let dynamic = ConfigManager.shared.hardwareBindingsForCurrentProfile()
        for (idx, binding) in dynamic {
            if let code = binding.keyCode, code == UInt16(keyCode) {
                return idx
            }
        }
        // Fallback to static mapper
        return KeyCodeMapper.buttonIndex(for: keyCode)
    }
}
