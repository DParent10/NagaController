import Cocoa

final class SegmentedMeterView: NSView {
    var activeSegments: Int = 0 { didSet { needsDisplay = true } }
    var activeColor: NSColor = .systemGreen { didSet { needsDisplay = true } }
    let totalSegments: Int

    init(totalSegments: Int) {
        self.totalSegments = totalSegments
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "Live device status"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard totalSegments > 0 else { return }

        let gap: CGFloat = 2
        let segmentWidth = (bounds.width - gap * CGFloat(totalSegments - 1)) / CGFloat(totalSegments)
        let segmentHeight = min(bounds.height, 8)
        let y = (bounds.height - segmentHeight) / 2

        for index in 0..<totalSegments {
            let x = CGFloat(index) * (segmentWidth + gap)
            let rect = NSRect(x: x, y: y, width: segmentWidth, height: segmentHeight)
            let color = index < activeSegments
                ? activeColor.withAlphaComponent(0.95)
                : NSColor.white.withAlphaComponent(0.16)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}
