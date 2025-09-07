import Foundation
import Carbon.HIToolbox

enum KeyCodeMapper {
    // US ANSI keyboard row for 1-0-=-=
    // 1..0, -, = correspond to kVK_ANSI_1.. etc
    private static let mapping: [CGKeyCode: Int] = [
        CGKeyCode(kVK_ANSI_1): 1,
        CGKeyCode(kVK_ANSI_2): 2,
        CGKeyCode(kVK_ANSI_3): 3,
        CGKeyCode(kVK_ANSI_4): 4,
        CGKeyCode(kVK_ANSI_5): 5,
        CGKeyCode(kVK_ANSI_6): 6,
        CGKeyCode(kVK_ANSI_7): 7,
        CGKeyCode(kVK_ANSI_8): 8,
        CGKeyCode(kVK_ANSI_9): 9,
        CGKeyCode(kVK_ANSI_0): 10,
        CGKeyCode(kVK_ANSI_Minus): 11,
        CGKeyCode(kVK_ANSI_Equal): 12
    ]

    static func buttonIndex(for keyCode: CGKeyCode) -> Int? {
        return mapping[keyCode]
    }
}
