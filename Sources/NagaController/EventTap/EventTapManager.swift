import Cocoa
import ApplicationServices
import Darwin

final class EventTapManager {
    static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Track buttons whose original number keyDown we intercepted so we can also intercept keyUp
    private var activeDownButtons: Set<Int> = []

    private(set) var isListeningOnly: Bool = true
    var isRemappingEnabled: Bool {
        get { return !isListeningOnly }
        set {
            let newListenOnly = !newValue
            if newListenOnly != isListeningOnly {
                start(listenOnly: newListenOnly)
            }
        }
    }

    private init() {}

    func start(listenOnly: Bool) {
        stop()
        isListeningOnly = listenOnly

        let mask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )

        var options: CGEventTapOptions = listenOnly ? .listenOnly : .defaultTap

        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: CGEventMask(mask),
            callback: EventTapManager.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        if tap == nil && !listenOnly {
            NSLog("[EventTap] Failed to create blocking event tap; falling back to listen-only. Enable Input Monitoring in System Settings.")
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
            NSLog("[EventTap] Failed to create event tap. Check permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[EventTap] Started (listenOnly=\(listenOnly)).")
        }
    }

    func stop() {
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

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if let buttonIndex = KeyCodeMapper.buttonIndex(for: keyCode) {
            if type == .keyDown {
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
                        ButtonMapper.shared.handlePress(buttonIndex: buttonIndex)
                        manager.activeDownButtons.insert(buttonIndex)
                        return nil
                    }
                }
            } else if type == .keyUp {
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
}
