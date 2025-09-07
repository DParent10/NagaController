import Foundation

final class MacroEngine {
    static let shared = MacroEngine()
    private init() {}

    func run(steps: [MacroStep]) {
        ButtonMapper.shared.runMacro(steps)
    }
}
