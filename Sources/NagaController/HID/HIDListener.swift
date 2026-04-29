import Foundation
import IOKit.hid

final class HIDListener {
    static let shared = HIDListener()
    private static let DIAGNOSTIC_VERSION = "2026-03-09-V4-MAP-DIAG"
    private var lastDPI: Int?

    private var manager: IOHIDManager
    private let queue = DispatchQueue(label: "HIDListener.queue")

    // Recent button presses from the Naga device (by logical button index 1..12)
    // Value is timestamp (seconds since reference)
    private var recentPressTimestamps: [Int: TimeInterval] = [:]
    // Consider a HID press "recent" within this time window (seconds)
    // Increased to account for scheduling/processing latency between HID and event tap
    private let recentWindow: TimeInterval = 1.00
    private let dpiUpCookie: IOHIDElementCookie = IOHIDElementCookie(0x26b)
    private let dpiDownCookie: IOHIDElementCookie = IOHIDElementCookie(0x26d)
    private var syntheticStates: [Int: Bool] = [:]
    private var lastButtonIndexForCookie: [UInt32: Int] = [:]
    
    private var learningCallback: ((UInt32, UInt32, IOHIDElementCookie, Int32) -> Void)?

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Restrict: match only known vendors; still filter by product name fallback in callback
        // Match ALL HID interfaces from these vendors
        // TEMP: Match EVERYTHING to find the missing Naga interfaces
        let matches: [[String: Any]] = [[:]] 
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard context != nil else { return }
            let vendor = HIDListener.vendorID(device: device) ?? -1
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "<unknown>"
            NSLog("[HID] Device plugged/matched: vendor=0x\(String(vendor, radix: 16)), product=\(product)")
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let this = Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue()
            this.handle(value: value)
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        IOHIDManagerRegisterInputReportCallback(manager, { (context, result, sender, type, reportID, report, reportLength) in
            guard let context = context, let sender = sender else { return }
            let this = Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue()
            this.handle(report: report, length: reportLength, id: reportID, from: sender)
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            NSLog("[HID] IOHIDManagerOpen failed: \(openResult)")
        } else {
            NSLog("[HID] Listener started. VERSION: \(HIDListener.DIAGNOSTIC_VERSION)")
            NSLog("[HID] Matching ALL devices for diagnostics + RAW reports enabled.")
            if let set = IOHIDManagerCopyDevices(manager) {
                let devices = (set as NSSet) as! Set<IOHIDDevice>
                for dev in devices {
                    let vendor = HIDListener.vendorID(device: dev) ?? -1
                    let product = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "<unknown>"
                    let _ = (IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String) ?? "<unknown>"
                    let usage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? -1
                    let usagePage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? -1
                    let ptr = Unmanaged.passUnretained(dev).toOpaque()
                    NSLog("[HID] DISCOVERY: [\(ptr)] product=\(product), vendor=0x\(String(vendor, radix: 16)), usage=0x\(String(usagePage, radix: 16)):0x\(String(usage, radix: 16))")
                }
            }
        }
    }

    private func record(buttonIndex: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        queue.sync {
            recentPressTimestamps[buttonIndex] = now
        }
    }

    func setLearningCallback(_ callback: ((UInt32, UInt32, IOHIDElementCookie, Int32) -> Void)?) {
        queue.sync {
            learningCallback = callback
        }
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let cookie = IOHIDElementGetCookie(element)
        let pressedValue = IOHIDValueGetIntegerValue(value)
        let scaledValue = IOHIDValueGetScaledValue(value, IOHIDValueScaleType(kIOHIDValueScaleTypePhysical))
        let pressed = pressedValue != 0 || abs(scaledValue) > 0.001
        
        // Ignore invalid usages often sent as padding or error states
        guard usage != 0xffffffff && usage != 0 else { return }

        let device = IOHIDElementGetDevice(element)
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "<unknown>"
        
        let ptr = Unmanaged.passUnretained(device).toOpaque()
        let isLearning = queue.sync { learningCallback != nil }
        let isNaga = HIDListener.isNagaDevice(device: device)

        // NUCLEAR LOGGING: Every non-movement event from EVERY device
        let isMovement = (usagePage == 0x01 && (usage == 0x30 || usage == 0x31 || usage == 0x38))
        if !isMovement {
            #if DEBUG
            let valStr = pressedValue != 0 ? "\(pressedValue)" : String(format: "%.3f", scaledValue)
            NSLog("[HID] NUCLEAR EVENT: [\(ptr)] pg=0x\(String(usagePage, radix: 16)), us=0x\(String(usage, radix: 16)), val=\(valStr), prod=\(product) (\(isNaga ? "NAGA" : "OTHER"))")
            #endif
        }

        if isMovement { return }

        // Only accept events from Naga devices (or any device if learning)
        guard isNaga || isLearning else { return }

        let activeVal = (abs(scaledValue) > 0.1) ? Int32(round(scaledValue)) : Int32(pressedValue)

        if usagePage != 0x07 {
            if pressed {
                queue.sync {
                    if let callback = learningCallback {
                        NSLog("[HID] LEARNING: Triggering callback for usagePage=0x\(String(usagePage, radix: 16)), usage=0x\(String(usage, radix: 16)), value=\(activeVal)")
                        callback(usagePage, usage, cookie, activeVal)
                        return
                    }
                }
            }

            // Support dynamic mappings for non-keyboard pages
            let buttonIndex = HIDListener.buttonIndex(forUsage: usage, usagePage: usagePage, cookie: UInt32(cookie), value: activeVal)
            
            if let targetIdx = buttonIndex {
                let remapping = ConfigManager.shared.getRemappingEnabled()
                if pressed {
                    record(buttonIndex: targetIdx)
                    NSLog("[HID] Mapped press for button \(targetIdx) (Remapping=\(remapping))")
                    
                    // Only handle synthetic events here for buttons that CANNOT be blocked by the EventTap (e.g. DPI buttons > 12)
                    // Otherwise, the EventTap will handle it to ensure the original key is blocked.
                    if remapping && targetIdx > 12 {
                        NSLog("[HID] Triggering synthetic event for non-interceptable button \(targetIdx)")
                        handleSynthetic(buttonIndex: targetIdx, pressed: true, rawValue: pressedValue)
                    }
                } else {
                    if remapping && targetIdx > 12 {
                        handleSynthetic(buttonIndex: targetIdx, pressed: false, rawValue: 0)
                    }
                }
            } else if pressed {
                 NSLog("[HID] No lookup for pg=0x\(String(usagePage, radix: 16)) us=0x\(String(usage, radix: 16)) val=\(activeVal) co=\(cookie)")
            }
            return
        }

        // Page 0x07 (Keyboard) handling
        guard pressed else { return }

        queue.sync {
            if let callback = learningCallback {
                NSLog("[HID] LEARNING (KBD): Triggering callback for usagePage=0x\(String(usagePage, radix: 16)), usage=0x\(String(usage, radix: 16)), value=\(pressedValue)")
                callback(usagePage, usage, cookie, Int32(pressedValue))
            }
        }
        if isLearning { return }

        // Only accept events from Naga devices to avoid remapping real keyboards
        guard isNaga else { return }

        if let buttonIndex = HIDListener.buttonIndex(forUsage: usage, usagePage: usagePage, cookie: UInt32(cookie), value: Int32(pressedValue)) {
            // Record timestamp for the EventTap to see and block
            record(buttonIndex: buttonIndex)
            NSLog("[HID] Mapped Keyboard press for button \(buttonIndex)")
        }
    }

    private func handleSynthetic(buttonIndex: Int, pressed: Bool, rawValue: Int) {
        let previous = queue.sync { syntheticStates[buttonIndex] ?? false }
        if previous == pressed { return }

        if pressed {
            record(buttonIndex: buttonIndex)
        }

        queue.sync { syntheticStates[buttonIndex] = pressed }

        if pressed {
            NSLog("[HID] Synthetic press captured for button \(buttonIndex) (raw=0x\(String(rawValue, radix: 16)))")
            if ConfigManager.shared.getRemappingEnabled() {
                ButtonMapper.shared.handlePress(buttonIndex: buttonIndex)
            }
        } else {
            NSLog("[HID] Synthetic release captured for button \(buttonIndex)")
            if ConfigManager.shared.getRemappingEnabled() {
                ButtonMapper.shared.handleRelease(buttonIndex: buttonIndex)
            }
        }
    }

    func wasRecentPress(buttonIndex: Int) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        return queue.sync {
            if let t = recentPressTimestamps[buttonIndex] {
                return (now - t) <= recentWindow
            }
            return false
        }
    }

    private var lastDPIDirection: UInt32 = 0 // 1 for UP, 2 for DOWN

    private func handle(report: UnsafePointer<UInt8>, length: Int, id: UInt32, from sender: UnsafeMutableRawPointer) {
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "<unknown>"
        
        if product.lowercased().contains("naga") {
            let bytes = UnsafeBufferPointer(start: report, count: length)
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            
            if id == 5 && length >= 5 {
                // Byte 3-4 is DPI (Big Endian)
                let currentDPI = (Int(report[3]) << 8) | Int(report[4])
                
                var usage: UInt32 = 0
                if let prev = lastDPI {
                    if currentDPI > prev {
                        usage = 0x01
                        lastDPIDirection = 0x01
                    } else if currentDPI < prev {
                        usage = 0x02
                        lastDPIDirection = 0x02
                    } else {
                        // Value hasn't changed! This happens when hitting DPI limits.
                        // We use the last known direction (sticky direction).
                        usage = lastDPIDirection
                    }
                }
                
                if usage != 0 {
                    let direction = (usage == 0x01 ? "UP" : "DOWN")
                    let atLimit = (currentDPI == lastDPI) ? "[LIMIT] " : ""
                    NSLog("[HID] DETECTED DPI \(atLimit)\(direction) (DPI=\(currentDPI))")
                    triggerVirtualButton(usagePage: 0xFF01, usage: usage)
                }
                
                lastDPI = currentDPI
            } else if id == 1 || id == 4 {
                NSLog("[HID] RAW REPORT: [ID=\(id)] Len=\(length), Data=\(hex)")
            }
        }
    }

    private func triggerVirtualButton(usagePage: UInt32, usage: UInt32) {
        queue.sync {
            if let callback = learningCallback {
                NSLog("[HID] VIRTUAL TRIGGER (Learning): pg=0x\(String(usagePage, radix: 16)) us=0x\(String(usage, radix: 16))")
                callback(usagePage, usage, IOHIDElementCookie(0xFFFF), 1)
                return
            }
        }
        
        if let buttonIndex = HIDListener.buttonIndex(forUsage: usage, usagePage: usagePage, cookie: 0xFFFF, value: 1) {
            handleSynthetic(buttonIndex: buttonIndex, pressed: true, rawValue: 1)
            handleSynthetic(buttonIndex: buttonIndex, pressed: false, rawValue: 0)
        }
    }

    func consumeRecentPress(buttonIndex: Int) {
        _ = queue.sync {
            recentPressTimestamps.removeValue(forKey: buttonIndex)
        }
    }

    private static func isNagaDevice(device: IOHIDDevice) -> Bool {
        let vendor = vendorID(device: device) ?? 0
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)?.lowercased() ?? ""
        return vendor == 0x1532 || vendor == 0x068e || vendor == 0x2442 /* Cooler Master */ || product.contains("naga")
    }

    private static func vendorID(device: IOHIDDevice) -> Int? {
        if let v = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int {
            return v
        }
        if let num = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber {
            return num.intValue
        }
        return nil
    }

    private static func buttonIndex(forUsage usage: UInt32, usagePage: UInt32, cookie: UInt32? = nil, value: Int32? = nil) -> Int? {
        if let binding = ConfigManager.shared.getHardwareBinding(forUsage: usage, usagePage: usagePage, cookie: cookie, value: value) {
            let index = ConfigManager.shared.getButtonIndex(forHardwareBinding: binding)
            if index == nil {
                NSLog("[HID] ERR: Found binding but no button index for binding: \(binding)")
            }
            return index
        }
        
        // Manual fallback for DPI buttons if not yet mapped in config
        if usagePage == 0x0C && usage == 0x238 {
            if value == 1 { return 13 }
            if value == -1 { return 14 }
        }
        
        // Page 0x07 (Keyboard) fallback for standard number keys if not in config
        if usagePage == 0x07 {
            switch usage {
            case 0x1e: return 1  // '1'
            case 0x1f: return 2  // '2'
            case 0x20: return 3  // '3'
            case 0x21: return 4  // '4'
            case 0x22: return 5  // '5'
            case 0x23: return 6  // '6'
            case 0x24: return 7  // '7'
            case 0x25: return 8  // '8'
            case 0x26: return 9  // '9'
            case 0x27: return 10 // '0'
            case 0x2d: return 11 // '-'
            case 0x2e: return 12 // '='
            default: break
            }
        }
        return nil
    }
}
