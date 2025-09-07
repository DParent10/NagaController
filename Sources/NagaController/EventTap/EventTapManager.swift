import Cocoa
import ApplicationServices

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

        let options: CGEventTapOptions = listenOnly ? .listenOnly : .defaultTap

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: CGEventMask(mask),
            callback: EventTapManager.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
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
                    // Only remap/block if this keyDown correlates with a recent HID press
                    if HIDListener.shared.wasRecentPress(buttonIndex: buttonIndex) {
                        ButtonMapper.shared.handlePress(buttonIndex: buttonIndex)
                        manager.activeDownButtons.insert(buttonIndex)
                        // Block original event by returning nil
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
}
