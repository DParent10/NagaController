import XCTest
import Carbon.HIToolbox
@testable import NagaController

final class KeyboardLayoutTests: XCTestCase {
    func testPrintableClassification() {
        XCTAssertTrue(KeyboardLayout.isPrintable("x"))
        XCTAssertTrue(KeyboardLayout.isPrintable("7"))
        XCTAssertTrue(KeyboardLayout.isPrintable("-"))
        XCTAssertTrue(KeyboardLayout.isPrintable("="))
        XCTAssertFalse(KeyboardLayout.isPrintable(" "))
        XCTAssertFalse(KeyboardLayout.isPrintable("\r"))
        XCTAssertFalse(KeyboardLayout.isPrintable("\t"))
        XCTAssertFalse(KeyboardLayout.isPrintable(UnicodeScalar(0xF702)!)) // NSLeftArrowFunctionKey
    }

    func testCanonicalKeyStringPrefersCharacterForPrintableKeys() {
        // Physical key code 7 is "x" on QWERTY; on Dvorak the same position types "q".
        XCTAssertEqual(KeyStroke.canonicalKeyString(for: 7, characters: "q"), "q")
        XCTAssertEqual(KeyStroke.canonicalKeyString(for: 7, characters: "x"), "x")
        // Special keys still come from the table.
        XCTAssertEqual(KeyStroke.canonicalKeyString(for: UInt16(kVK_Return), characters: "\r"), "return")
        XCTAssertEqual(KeyStroke.canonicalKeyString(for: UInt16(kVK_LeftArrow), characters: "\u{F702}"), "left")
    }

    func testCurrentLayoutResolvesLetters() throws {
        // Layout-independent sanity: every layout can type "a" somewhere without Shift.
        let key = try XCTUnwrap(KeyboardLayout.shared.key(for: "a"))
        XCTAssertFalse(key.needsShift)
        XCTAssertEqual(KeyboardLayout.shared.key(for: "A"), key)
    }
}
