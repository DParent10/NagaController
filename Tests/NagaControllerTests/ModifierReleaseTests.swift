import XCTest
import Cocoa
@testable import NagaController

final class ModifierReleaseTests: XCTestCase {
    func testCommandTabEndsWithCommandRelease() {
        let events = ButtonMapper.modifierReleaseEvents(.maskCommand, physicalFlags: [])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .flagsChanged)
        XCTAssertEqual(events.first?.getIntegerValueField(.keyboardEventKeycode), 55)
        XCTAssertEqual(events.first?.flags, [])
    }
    func testPhysicalKeyboardModifierIsNotReleased() {
        XCTAssertTrue(ButtonMapper.modifierReleaseEvents(.maskCommand, physicalFlags: .maskCommand).isEmpty)
    }
}
