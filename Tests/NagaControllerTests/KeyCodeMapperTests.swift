import XCTest
@testable import NagaController
import Carbon.HIToolbox

final class KeyCodeMapperTests: XCTestCase {
    func testMappings() {
        XCTAssertEqual(KeyCodeMapper.buttonIndex(for: CGKeyCode(kVK_ANSI_1)), 1)
        XCTAssertEqual(KeyCodeMapper.buttonIndex(for: CGKeyCode(kVK_ANSI_0)), 10)
        XCTAssertEqual(KeyCodeMapper.buttonIndex(for: CGKeyCode(kVK_ANSI_Minus)), 11)
        XCTAssertEqual(KeyCodeMapper.buttonIndex(for: CGKeyCode(kVK_ANSI_Equal)), 12)
    }
}
