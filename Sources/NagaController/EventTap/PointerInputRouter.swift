import Foundation

/// HID identifies the physical device; CGEvent is where its native action can be
/// suppressed. Match one HID observation to one event, using hardware timestamps.
/// No CGEvent direction inference: Natural Scrolling may invert the pan delta.
struct PointerInputRouter {
    enum Kind: Equatable {
        case button(usage: UInt32, down: Bool)
        case horizontalScroll
    }
    struct Observation {
        let kind: Kind
        let timestamp: UInt64 // nanoseconds since boot
        let buttonIndex: Int
    }
    private var observations: [Observation] = []
    static let tolerance: UInt64 = 50_000_000

    mutating func record(_ observation: Observation) {
        observations.append(observation)
        // Bound storage even if a device sends HID data without CGEvents.
        if observations.count > 128 { observations.removeFirst(observations.count - 128) }
    }

    mutating func consume(kind: Kind, timestamp: UInt64) -> Int? {
        observations.removeAll { $0.timestamp < timestamp && timestamp - $0.timestamp > Self.tolerance }
        let matching = observations.indices.filter {
            let item = observations[$0]
            let distance = item.timestamp > timestamp ? item.timestamp - timestamp : timestamp - item.timestamp
            return item.kind == kind && distance <= Self.tolerance
        }
        guard let index = matching.min(by: {
            abs(Double(observations[$0].timestamp) - Double(timestamp)) < abs(Double(observations[$1].timestamp) - Double(timestamp))
        }) else { return nil }
        return observations.remove(at: index).buttonIndex
    }

    static func bindingIndex(bindings: [Int: HardwareBinding], usagePage: UInt32,
                             usage: UInt32, cookie: UInt32, value: Int32,
                             vendorID: Int, productID: Int) -> Int? {
        // Only mapped auxiliary buttons and signed horizontal pan are eligible.
        guard (usagePage == 9 && usage >= 3) || (usagePage == 12 && usage == 568 && value != 0) else { return nil }
        return bindings.keys.sorted().first { index in
            let b = bindings[index]!
            guard b.usagePage == usagePage, b.usage == usage,
                  b.vendorID == vendorID, b.productID == productID,
                  b.cookie == nil || b.cookie == cookie else { return false }
            if usagePage == 9 { return b.value == nil || b.value == 1 }
            guard let expected = b.value else { return true }
            return (expected < 0 && value < 0) || (expected > 0 && value > 0)
        }
    }
}
