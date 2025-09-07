import Foundation
import ApplicationServices
import Carbon.HIToolbox

// Minimal mapping for 1..0, -, = to button index 1..12
let nagaMapping: [CGKeyCode: Int] = [
    CGKeyCode(kVK_ANSI_1): 1,
    CGKeyCode(kVK_ANSI_2): 2,
    CGKeyCode(kVK_ANSI_3): 3,
    CGKeyCode(kVK_ANSI_4): 4,
    CGKeyCode(kVK_ANSI_5): 5,
    CGKeyCode(kVK_ANSI_6): 6,
    CGKeyCode(kVK_ANSI_7): 7,
    CGKeyCode(kVK_ANSI_8): 8,
    CGKeyCode(kVK_ANSI_9): 9,
    CGKeyCode(kVK_ANSI_0): 10,
    CGKeyCode(kVK_ANSI_Minus): 11,
    CGKeyCode(kVK_ANSI_Equal): 12
]

var gTap: CFMachPort?

func ensureAccessibilityPermission() -> Bool {
    let trusted = AXIsProcessTrusted()
    print("[TapTester] Accessibility trusted = \(trusted)")
    if !trusted {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        print("[TapTester] Prompted for Accessibility. Go to System Settings → Privacy & Security → Accessibility and enable 'TapTester' (or the hosting terminal if needed). Then re-run this tool.")
    }
    return trusted
}

private let tapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let block = (refcon?.assumingMemoryBound(to: Bool.self).pointee) ?? false
    if let idx = nagaMapping[keyCode], type == .keyDown {
        print("[TapTester] Detected Naga button \(idx) (keyCode=\(keyCode)). block=\(block)")
        if block {
            return nil
        }
    }
    return Unmanaged.passUnretained(event)
}

func runTap(block: Bool) {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let options: CGEventTapOptions = block ? .defaultTap : .listenOnly

    // Pass `block` as refcon so callback knows whether to return nil
    let shouldBlockPtr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
    shouldBlockPtr.initialize(to: block)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: options,
        eventsOfInterest: CGEventMask(mask),
        callback: tapCallback,
        userInfo: shouldBlockPtr
    ) else {
        print("[TapTester] Failed to create event tap. Are Accessibility permissions granted?")
        exit(1)
    }

    gTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    print("[TapTester] Running. Press side buttons now. Press Ctrl+C to exit.")
    CFRunLoopRun()
}

// MARK: - Main
let args = CommandLine.arguments
let shouldBlock = args.contains("--block")

if ensureAccessibilityPermission() {
    runTap(block: shouldBlock)
} else {
    // Prompt issued; exit so user can grant and re-run
    exit(2)
}
