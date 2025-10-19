import Cocoa

enum UIStyle {
    static var razerGreen: NSColor {
        return NSColor(calibratedRed: 0x44/255.0, green: 0xD6/255.0, blue: 0x2C/255.0, alpha: 1.0)
    }

    static func makeCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0.5
        box.cornerRadius = 12
        box.fillColor = .clear
        if #available(macOS 10.14, *) {
            box.borderColor = NSColor.white.withAlphaComponent(0.18)
        } else {
            box.borderColor = NSColor.white.withAlphaComponent(0.18)
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

    static func stylePrimaryButton(_ b: NSButton) {
        b.isBordered = false
        b.bezelStyle = .rounded
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = razerGreen.withAlphaComponent(0.9).cgColor
        b.contentTintColor = .white
    }

    static func styleSecondaryButton(_ b: NSButton) {
        b.isBordered = false
        b.bezelStyle = .rounded
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        b.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        b.layer?.borderWidth = 0.5
        if #available(macOS 10.14, *) {
            b.contentTintColor = NSColor.labelColor
        }
    }

    static func styleDangerButton(_ b: NSButton) {
        b.isBordered = false
        b.bezelStyle = .rounded
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        b.contentTintColor = .white
        b.layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        b.layer?.shadowOpacity = 1
        b.layer?.shadowRadius = 6
        b.layer?.shadowOffset = CGSize(width: 0, height: -1)
    }
}
