import Cocoa
import QuartzCore

final class GlassyBatteryView: NSView {
    // Battery level 0-100 (nil = unknown)
    var level: Int? { didSet { update(animated: true) } }

    private let glass = NSVisualEffectView()
    private let gradient = CAGradientLayer()
    private let backgroundLayer = CALayer()
    private let borderLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        // Glass background
        if #available(macOS 11.0, *) {
            glass.material = .hudWindow
        } else {
            glass.material = .popover
        }
        glass.blendingMode = .behindWindow
        glass.state = .active
        addSubview(glass)

        // Background tint (subtle) + border for edge definition
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        borderLayer.borderWidth = 0.5
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(borderLayer)

        // Gradient fill
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.masksToBounds = true
        layer?.addSublayer(gradient)

        update(animated: false)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        let r = bounds
        let radius = r.height / 2
        layer?.cornerRadius = radius
        backgroundLayer.frame = r
        backgroundLayer.cornerRadius = radius
        borderLayer.frame = r
        borderLayer.cornerRadius = radius

        // Width based on level
        let pct: CGFloat
        if let lvl = level { pct = max(0, min(100, CGFloat(lvl))) / 100.0 } else { pct = 0 }
        let w = max(0, r.width * pct)
        gradient.frame = CGRect(x: r.minX, y: r.minY, width: w, height: r.height)
        gradient.cornerRadius = radius
    }

    private func update(animated: Bool) {
        // Respect reduce transparency
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glass.isHidden = true
            backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        } else {
            glass.isHidden = false
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        }

        // Colors based on level
        let colors: [CGColor]
        let lvl = level ?? 0
        if lvl >= 60 {
            colors = [NSColor.systemGreen.withAlphaComponent(0.9).cgColor,
                      NSColor.systemGreen.withAlphaComponent(0.6).cgColor]
        } else if lvl >= 30 {
            colors = [NSColor.systemYellow.withAlphaComponent(0.9).cgColor,
                      NSColor.systemYellow.withAlphaComponent(0.6).cgColor]
        } else {
            colors = [NSColor.systemRed.withAlphaComponent(0.95).cgColor,
                      NSColor.systemRed.withAlphaComponent(0.7).cgColor]
        }
        if animated {
            let colorAnim = CABasicAnimation(keyPath: "colors")
            colorAnim.duration = 0.3
            colorAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(colorAnim, forKey: "colors")
        }
        gradient.colors = colors

        // Pulse when low
        if let l = level, l <= 20 {
            if gradient.animation(forKey: "pulse") == nil {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1.0
                a.toValue = 0.6
                a.autoreverses = true
                a.repeatCount = .infinity
                a.duration = 0.8
                gradient.add(a, forKey: "pulse")
            }
        } else {
            gradient.removeAnimation(forKey: "pulse")
        }

        // Animate width change
        if animated {
            let widthAnim = CABasicAnimation(keyPath: "bounds.size.width")
            widthAnim.duration = 0.3
            widthAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            widthAnim.fromValue = gradient.presentation()?.bounds.width
            widthAnim.toValue = nil // final will be applied in layout
            gradient.add(widthAnim, forKey: "width")
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}
