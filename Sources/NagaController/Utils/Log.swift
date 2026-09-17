import Foundation

/// Verbose tracing for development. Off unless NAGA_DEBUG is set in the
/// environment, so a normal launch logs only errors and state changes rather
/// than a line per HID report.
///
///     NAGA_DEBUG=1 /Applications/NagaController.app/Contents/MacOS/NagaController
enum Log {
    static let verbose: Bool = ProcessInfo.processInfo.environment["NAGA_DEBUG"] != nil

    /// Autoclosure keeps the string out of the release path entirely.
    static func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        NSLog("%@", message())
    }
}
