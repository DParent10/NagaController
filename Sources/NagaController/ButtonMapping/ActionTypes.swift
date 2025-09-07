import Foundation

enum ActionType: Equatable {
    case keySequence(keys: [KeyStroke], description: String?)
    case application(path: String, description: String?)
    case systemCommand(command: String, description: String?)
    case macro(steps: [MacroStep], description: String?)
    case profileSwitch(profile: String, description: String?)
}

struct KeyStroke: Equatable, Codable {
    var key: String // e.g., "c", "v"
    var modifiers: [String] // e.g., ["cmd", "shift"]
}

struct MacroStep: Equatable, Codable {
    var type: String // "key", "text", "delay"
    var keyStroke: KeyStroke? = nil
    var text: String? = nil
    var delayMs: Int? = nil
}
