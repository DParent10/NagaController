import XCTest
@testable import NagaController

final class ImportSafetyTests: XCTestCase {
    func testCountsShellCommandsAcrossStandardAndHypershiftLayers() {
        let file = ProfilesFile(
            profiles: [
                "Default": Profile(
                    buttons: [
                        "1": ButtonAction(type: "systemCommand", keys: nil, description: nil, path: nil, command: "rm -rf ~/Desktop", text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil),
                        "2": ButtonAction(type: "keySequence", keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil, path: nil, command: nil, text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil)
                    ],
                    hardwareBindings: nil,
                    hypershiftMappings: [
                        "1": ButtonAction(type: "systemCommand", keys: nil, description: nil, path: nil, command: "open /Applications", text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil)
                    ]
                )
            ],
            settings: nil
        )
        XCTAssertEqual(ConfigManager.countShellCommandActions(in: file), 2)
    }

    func testProfileWithoutShellCommandsCountsZero() {
        let file = ProfilesFile(
            profiles: [
                "Default": Profile(
                    buttons: ["1": ButtonAction(type: "keySequence", keys: [KeyStroke(key: "v", modifiers: ["cmd"])], description: nil, path: nil, command: nil, text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil)],
                    hardwareBindings: nil,
                    hypershiftMappings: nil
                )
            ],
            settings: nil
        )
        XCTAssertEqual(ConfigManager.countShellCommandActions(in: file), 0)
    }
}
