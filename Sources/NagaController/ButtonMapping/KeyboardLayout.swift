import Foundation
import Carbon.HIToolbox

/// Resolves a printable character to the key that produces it on the *current* keyboard
/// layout. Mappings store the character the user recorded ("x"), not a physical key code,
/// because key codes are physical positions: code 7 types "x" on QWERTY and "q" on Dvorak.
/// Results are cached per input source and rebuilt when the user switches layouts.
final class KeyboardLayout {
    static let shared = KeyboardLayout()

    struct Key: Equatable {
        let code: CGKeyCode
        let needsShift: Bool
    }

    private var cache: [String: Key] = [:]
    private var cachedSourceID: String?

    /// Key producing `character` (a single printable character, case-insensitive) on the
    /// current layout, or nil if the layout cannot type it directly.
    func key(for character: String) -> Key? {
        let wanted = character.lowercased()
        guard wanted.count == 1 else { return nil }
        refreshIfNeeded()
        return cache[wanted]
    }

    private func refreshIfNeeded() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        let sourceID: String = {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }()
        if sourceID == cachedSourceID, !cache.isEmpty { return }

        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data

        var map: [String: Key] = [:]
        let keyboardType = UInt32(LMGetKbdType())
        // Unshifted pass first so lowercase letters win; shifted pass then adds the
        // characters only reachable with Shift (digits on AZERTY, symbols everywhere).
        let passes: [(modifiers: UInt32, shift: Bool)] = [
            (0, false),
            (UInt32((shiftKey >> 8) & 0xFF), true)
        ]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for pass in passes {
                for code in 0..<128 {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), pass.modifiers,
                                                keyboardType, UInt32(kUCKeyTranslateNoDeadKeysBit),
                                                &deadKeyState, chars.count, &length, &chars)
                    guard status == noErr, length == 1 else { continue }
                    let s = String(utf16CodeUnits: chars, count: 1)
                    guard let scalar = s.unicodeScalars.first,
                          KeyboardLayout.isPrintable(scalar) else { continue }
                    let lowered = s.lowercased()
                    if map[lowered] == nil {
                        map[lowered] = Key(code: CGKeyCode(code), needsShift: pass.shift)
                    }
                }
            }
        }
        cache = map
        cachedSourceID = sourceID
    }

    /// A character worth recording by value rather than by key code: letters, digits,
    /// punctuation and symbols. Excludes controls, whitespace and the private-use range
    /// AppKit uses for function/arrow keys (U+F700–U+F8FF).
    static func isPrintable(_ scalar: UnicodeScalar) -> Bool {
        if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return false }
        let c = Character(scalar)
        if c.isWhitespace || c.isNewline { return false }
        return c.isLetter || c.isNumber || c.isPunctuation || c.isSymbol
    }
}
