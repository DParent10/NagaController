import Cocoa

enum UIStyle {
    static func makeCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderType = .noBorder
        box.cornerRadius = 12
        if #available(macOS 10.14, *) {
            box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(1.0)
        } else {
            box.fillColor = NSColor.windowBackgroundColor
        }
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    static func symbol(_ name: String, size: CGFloat = 16, weight: NSFont.Weight = .regular) -> NSImage? {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        return nil
    }
}
