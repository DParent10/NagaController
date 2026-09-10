import Cocoa

enum UIStyle {
    static var razerGreen: NSColor {
        // Slightly more vibrant/readable green for accessibility
        return NSColor(calibratedRed: 0x44/255.0, green: 0xFF/255.0, blue: 0x2C/255.0, alpha: 1.0)
    }
    
    static var razerGreenMuted: NSColor {
        return NSColor(calibratedRed: 0x44/255.0, green: 0xD6/255.0, blue: 0x2C/255.0, alpha: 0.1)
    }
    
    static var backgroundDark: NSColor {
        return NSColor(white: 0.08, alpha: 1.0)
    }

    static func makeCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1.0
        box.cornerRadius = 12
        box.fillColor = NSColor.white.withAlphaComponent(0.06)
        box.borderColor = NSColor.white.withAlphaComponent(0.15)
        box.translatesAutoresizingMaskIntoConstraints = false
        
        // Slightly softer shadow
        box.wantsLayer = true
        box.layer?.shadowColor = NSColor.black.cgColor
        box.layer?.shadowOpacity = 0.5
        box.layer?.shadowOffset = CGSize(width: 0, height: -2)
        box.layer?.shadowRadius = 8
        
        return box
    }
    
    static func makeGlassyView() -> NSVisualEffectView {
        let vev = NSVisualEffectView()
        vev.blendingMode = .withinWindow
        // Use a more opaque, darker material for better contrast
        vev.material = .hudWindow
        vev.state = .active
        vev.wantsLayer = true
        vev.layer?.cornerRadius = 14
        return vev
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
        b.layer?.cornerRadius = 10
        b.layer?.backgroundColor = razerGreen.cgColor
        b.contentTintColor = .black
        b.font = .systemFont(ofSize: 13, weight: .bold)
        b.imageHugsTitle = true
        
        // Solid appearance, less glow distraction
        b.layer?.shadowColor = razerGreen.withAlphaComponent(0.3).cgColor
        b.layer?.shadowOpacity = 1.0
        b.layer?.shadowOffset = .zero
        b.layer?.shadowRadius = 4
    }

    static func styleSecondaryButton(_ b: NSButton) {
        b.isBordered = false
        b.bezelStyle = .rounded
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        b.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        b.layer?.borderWidth = 1.0
        b.contentTintColor = .white
        b.font = .systemFont(ofSize: 13, weight: .bold)
        b.imageHugsTitle = true
    }

    static func styleDangerButton(_ b: NSButton) {
        b.isBordered = false
        b.bezelStyle = .rounded
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        b.layer?.backgroundColor = NSColor.systemRed.cgColor
        b.contentTintColor = .white
        b.font = .systemFont(ofSize: 13, weight: .bold)
        b.imageHugsTitle = true
        
        b.layer?.shadowColor = NSColor.systemRed.withAlphaComponent(0.3).cgColor
        b.layer?.shadowOpacity = 1.0
        b.layer?.shadowRadius = 4
        b.layer?.shadowOffset = .zero
    }
}
