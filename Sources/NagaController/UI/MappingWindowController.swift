import Cocoa

final class MappingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MappingWindowController()
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    private init() {
        let vc = MappingViewController()
        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "NagaController — Button Mappings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 780, height: 560))
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false

        // Note: Do not wrap vc.view here. MappingViewController already draws a full-size
        // NSVisualEffectView background. Wrapping again caused a self-subview cycle and hang.
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }

        previousActivationPolicy = nil
        let currentPolicy = NSApp.activationPolicy()
        if currentPolicy != .regular {
            previousActivationPolicy = currentPolicy
            NSApp.setActivationPolicy(.regular)
        }

        window.delegate = self
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let previous = previousActivationPolicy {
            NSApp.setActivationPolicy(previous)
            previousActivationPolicy = nil
        }
    }
}
