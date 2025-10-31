import Cocoa

final class MouseMappingView: NSView {
    var onEditButton: ((Int) -> Void)?

    private var buttonViews: [Int: NSButton] = [:]
    private var labelViews: [Int: NSTextField] = [:]
    private var hoverIndex: Int? { didSet { if oldValue != hoverIndex { needsDisplay = true; updateHoverBorders() } } }
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
        setupSubviews()
    }

    private func setupSubviews() {
        // Create 12 button hotspots and labels
        for i in 1...12 {
            let b = NSButton(title: "\(i)", target: self, action: #selector(buttonTapped(_:)))
            b.bezelStyle = .texturedRounded
            b.font = .systemFont(ofSize: 12, weight: .semibold)
            b.setButtonType(.momentaryPushIn)
            b.isBordered = true
            b.tag = i
            addSubview(b)
            buttonViews[i] = b

            let l = NSTextField(labelWithString: "")
            l.lineBreakMode = .byTruncatingTail
            l.font = .systemFont(ofSize: 12)
            l.toolTip = "Click to edit mapping for button \(i)"
            l.isSelectable = false
            l.isEditable = false
            l.drawsBackground = true
            if #available(macOS 10.14, *) {
                l.backgroundColor = NSColor.controlBackgroundColor
            } else {
                l.backgroundColor = NSColor.windowBackgroundColor
            }
            l.wantsLayer = true
            l.layer?.cornerRadius = 4
            l.layer?.masksToBounds = true
            l.tag = i
            addSubview(l)
            labelViews[i] = l
        }
        updateLabels()
    }

    override func layout() {
        super.layout()
        layoutButtonsAndLabels()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let opts: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .inVisibleRect]
        tracking = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var hit: Int?
        for (i, v) in buttonViews { if v.frame.contains(p) { hit = i; break } }
        if hit == nil {
            for (i, v) in labelViews { if v.frame.contains(p) { hit = i; break } }
        }
        hoverIndex = hit
    }

    private func layoutButtonsAndLabels() {
        let inset: CGFloat = 12
        let bodyRect = bounds.insetBy(dx: inset, dy: inset)

        // Left side: mouse body region occupies ~45% width
        let leftWidth = bodyRect.width * 0.45
        let leftRect = NSRect(x: bodyRect.minX, y: bodyRect.minY, width: leftWidth, height: bodyRect.height)

        // Right side (was labels). Labels are now placed inside leftRect to avoid crossover.

        // Arrange 3 columns x 4 rows on leftRect
        let cols = 3
        let rows = 4
        let btnW = max(24, leftRect.width / CGFloat(cols) - 12)
        let btnH = max(22, leftRect.height / CGFloat(rows) - 12)
        let slantPerRow: CGFloat = 10

        for i in 1...12 {
            let idx = i - 1
            let col = idx % 3 // 0..2, column order: 0=>1,4,7,10 ; 1=>2,5,8,11 ; 2=>3,6,9,12
            let row = idx / 3 // 0..3

            let x = leftRect.minX + CGFloat(col) * (leftRect.width / CGFloat(cols)) + ((leftRect.width / CGFloat(cols)) - btnW) / 2 + CGFloat(row) * slantPerRow
            let y = leftRect.maxY - CGFloat(row + 1) * (leftRect.height / CGFloat(rows)) + ((leftRect.height / CGFloat(rows)) - btnH) / 2
            if let b = buttonViews[i] {
                b.frame = NSRect(x: x, y: y, width: btnW, height: btnH)
            }
        }

        // Place labels directly to the right of each button within the leftRect
        for i in 1...12 {
            guard let b = buttonViews[i], let l = labelViews[i] else { continue }
            let lx = min(b.frame.maxX + 8, leftRect.maxX - 80)
            let lw = max(60, leftRect.maxX - lx - 8)
            let ly = b.frame.midY - 10
            l.frame = NSRect(x: lx, y: ly, width: lw, height: 20)
            if l.gestureRecognizers.isEmpty {
                let gr = NSClickGestureRecognizer(target: self, action: #selector(labelClicked(_:)))
                l.addGestureRecognizer(gr)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset: CGFloat = 12
        let bodyRect = bounds.insetBy(dx: inset, dy: inset)
        let leftWidth = bodyRect.width * 0.45
        let leftRect = NSRect(x: bodyRect.minX, y: bodyRect.minY, width: leftWidth, height: bodyRect.height)

        // Draw stylized mouse body (rounded rect)
        let path = NSBezierPath(roundedRect: leftRect, xRadius: 18, yRadius: 18)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        // Light border
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        // No cross-card connection lines in this design
    }

    func updateLabels() {
        let mapping = ConfigManager.shared.mappingForCurrentProfile()
        for i in 1...12 {
            labelViews[i]?.stringValue = actionDescription(mapping[i])
        }
        needsDisplay = true
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        onEditButton?(sender.tag)
    }

    @objc private func labelClicked(_ sender: NSClickGestureRecognizer) {
        guard let v = sender.view else { return }
        onEditButton?(v.tag)
    }

    private func updateHoverBorders() {
        for i in 1...12 {
            let sel = (i == hoverIndex)
            if let l = labelViews[i] {
                l.layer?.borderWidth = sel ? 1 : 0
                if #available(macOS 10.14, *) {
                    l.layer?.borderColor = NSColor.controlAccentColor.cgColor
                } else {
                    l.layer?.borderColor = NSColor.systemBlue.cgColor
                }
            }
        }
    }

    private func actionDescription(_ action: ActionType?) -> String {
        guard let action = action else { return "(Unassigned)" }
        switch action {
        case .keySequence(let keys, let d):
            let ks = keys.map { $0.formattedShortcut() }.joined(separator: ", ")
            return d ?? "Key Sequence: \(ks)"
        case .application(let path, let d):
            return d ?? "Open App: \(path)"
        case .systemCommand(let cmd, let d):
            return d ?? "Command: \(cmd)"
        case .textSnippet(let text, let d):
            let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            let truncated = preview.count > 40 ? String(preview.prefix(37)) + "…" : preview
            return d ?? "Type Text: \(truncated)"
        case .macro(_, let d):
            return d ?? "Macro"
        case .profileSwitch(let p, let d):
            return d ?? "Switch Profile: \(p)"
        }
    }
}
