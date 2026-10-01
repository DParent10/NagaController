import Cocoa

/// A brief, auto-dismissing on-screen message for state changes that have no other
/// visible confirmation — e.g. Hypershift toggling, which the user guide already admits
/// is easy to lose track of (that's why the long-hold safety release exists). Deliberately
/// has no queue or stacking: a second call just replaces whatever is currently showing.
final class HUDNotifier {
    static let shared = HUDNotifier()

    private var window: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func show(_ text: String, duration: TimeInterval = 1.2) {
        DispatchQueue.main.async { [weak self] in
            self?.present(text, duration: duration)
        }
    }

    private func present(_ text: String, duration: TimeInterval) {
        dismissWorkItem?.cancel()

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 20
        let contentSize = NSSize(width: label.frame.width + padding * 2, height: label.frame.height + padding)

        let win = window ?? {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window = w
            return w
        }()

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.blendingMode = .behindWindow
        label.frame = NSRect(x: padding, y: padding / 2, width: label.frame.width, height: label.frame.height)
        effectView.addSubview(label)

        win.setContentSize(contentSize)
        win.contentView = effectView

        if let screen = NSScreen.main {
            let x = screen.frame.midX - contentSize.width / 2
            let y = screen.frame.maxY - screen.frame.height * 0.22
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let win = self.window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
