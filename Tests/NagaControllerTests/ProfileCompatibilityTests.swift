import XCTest
@testable import NagaController

final class ProfileCompatibilityTests: XCTestCase {
    func testActualSavedProfileUsesSupportedActionsAndKeys() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/profiles.json")
        let file = try JSONDecoder().decode(ProfilesFile.self, from: Data(contentsOf: path))
        let profile = try XCTUnwrap(file.profiles["Naga Productivity"])
        XCTAssertEqual(profile.buttons.count, 12)
        XCTAssertEqual(profile.hypershiftMappings?.count, 11)
        for (index, action) in Array(profile.buttons) + Array(profile.hypershiftMappings ?? [:]) {
            switch action.type {
            case "keySequence":
                let strokes = try XCTUnwrap(action.keys, "Button \(index)")
                XCTAssertFalse(strokes.isEmpty)
                for stroke in strokes {
                    XCTAssertNotNil(stroke.keyCode ?? KeyStroke.keyCode(for: stroke.key), stroke.key)
                    for modifier in stroke.modifiers {
                        XCTAssertTrue(["cmd", "ctrl", "shift", "opt", "option", "alt"].contains(modifier))
                    }
                }
            case "mediaKey":
                XCTAssertNotNil(action.mediaKey.flatMap(MediaKeyType.init(rawValue:)), "Button \(index)")
            case "hypershift":
                XCTAssertEqual(action.mode, "toggle")
            default:
                XCTFail("Unexpected action \(action.type) at \(index)")
            }
        }
    }
}
