import XCTest
import CoreGraphics
@testable import NagaController

final class PhysicalModifierTests: XCTestCase {
    func testHeldShiftIsMergedIntoMappedKeyDown() {
        // Issue #22: "a" mapped to a button, Shift held on the keyboard, expect Shift+A.
        let flags = ButtonMapper.keyDownFlags(mapping: [], physical: .maskShift)
        XCTAssertTrue(flags.contains(.maskShift))
    }

    func testMappingModifiersArePreserved() {
        let flags = ButtonMapper.keyDownFlags(mapping: .maskCommand, physical: .maskShift)
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
    }

    func testOnlyRealModifiersPassThrough() {
        // Caps Lock, numeric-pad and non-coalesced bits in the HID state must not leak.
        let noise: CGEventFlags = [.maskAlphaShift, .maskNumericPad, .maskNonCoalesced]
        XCTAssertEqual(ButtonMapper.keyDownFlags(mapping: [], physical: noise), [])
        XCTAssertEqual(ButtonMapper.keyDownFlags(mapping: [], physical: noise.union(.maskControl)), .maskControl)
    }
}
