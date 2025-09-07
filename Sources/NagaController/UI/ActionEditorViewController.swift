import Cocoa
import UniformTypeIdentifiers

final class ActionEditorViewController: NSViewController {
    private let buttonIndex: Int
    private let onComplete: (ActionType?) -> Void

    private let segmented = NSSegmentedControl(labels: ["Key", "App", "Cmd", "Profile"], trackingMode: .selectOne, target: nil, action: nil)

    // Common
    private let descriptionField = NSTextField(string: "")

    // Key Sequence
    private let keyField = NSTextField(string: "")
    private let modCmd = NSButton(checkboxWithTitle: "⌘", target: nil, action: nil)
    private let modAlt = NSButton(checkboxWithTitle: "⌥", target: nil, action: nil)
    private let modCtrl = NSButton(checkboxWithTitle: "⌃", target: nil, action: nil)
    private let modShift = NSButton(checkboxWithTitle: "⇧", target: nil, action: nil)

    // Application
    private let appPath = NSPathControl()

    // Command
    private let commandField = NSTextField(string: "")

    // Profile Switch
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let contentStack = NSStackView()

    init(buttonIndex: Int, onComplete: @escaping (ActionType?) -> Void) {
        self.buttonIndex = buttonIndex
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = NSView()

        let header = NSTextField(labelWithString: "Edit Action — Button \(buttonIndex)")
        header.font = .systemFont(ofSize: 15, weight: .semibold)

        segmented.target = self
        segmented.action = #selector(segmentedChanged)
        segmented.selectedSegment = 0

        // Description
        let descLabel = NSTextField(labelWithString: "Description (optional):")
        descriptionField.placeholderString = "e.g. Copy"

        // Key UI
        let keyRow = NSStackView(views: [NSTextField(labelWithString: "Key:"), keyField, NSView()])
        keyRow.spacing = 8
        let modsRow = NSStackView(views: [NSTextField(labelWithString: "Modifiers:"), modCmd, modAlt, modCtrl, modShift, NSView()])
        modsRow.spacing = 8
        let keyGroup = group("Key Sequence", views: [keyRow, modsRow])

        // App UI
        appPath.url = nil
        appPath.pathStyle = .standard
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browseApp))
        browse.image = UIStyle.symbol("folder", size: 13)
        browse.imagePosition = .imageLeading
        let appRow = NSStackView(views: [NSTextField(labelWithString: "Application:"), appPath, browse])
        appRow.spacing = 8
        let appGroup = group("Application", views: [appRow])

        // Command UI
        commandField.placeholderString = "e.g. say Hello or osascript …"
        if #available(macOS 10.15, *) {
            commandField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        let cmdRow = NSStackView(views: [NSTextField(labelWithString: "Command:"), commandField])
        cmdRow.spacing = 8
        let cmdGroup = group("System Command", views: [cmdRow])

        // Profile UI
        let profLabel = NSTextField(labelWithString: "Profile:")
        profilePopup.addItems(withTitles: ConfigManager.shared.availableProfiles())
        let profRow = NSStackView(views: [profLabel, profilePopup])
        profRow.spacing = 8
        let profGroup = group("Profile Switch", views: [profRow])

        // Content stack
        contentStack.orientation = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let descStack = NSStackView(views: [descLabel, descriptionField])
        descStack.spacing = 6

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.image = UIStyle.symbol("xmark.circle", size: 14)
        cancel.imagePosition = .imageLeading
        cancel.keyEquivalent = "\u{1b}"
        cancel.toolTip = "Close without saving"

        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.image = UIStyle.symbol("tray.and.arrow.down", size: 14, weight: .semibold)
        save.imagePosition = .imageLeading
        save.keyEquivalent = "\r"
        save.toolTip = "Save changes"
        buttonsStack.addArrangedSubview(NSView())
        buttonsStack.addArrangedSubview(cancel)
        buttonsStack.addArrangedSubview(save)

        view.addSubview(header)
        view.addSubview(segmented)
        view.addSubview(descStack)
        view.addSubview(contentStack)
        view.addSubview(buttonsStack)

        for v in [header, segmented, descStack, contentStack, buttonsStack] { v.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            segmented.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            segmented.leadingAnchor.constraint(equalTo: header.leadingAnchor),

            descStack.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            descStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            descStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            contentStack.topAnchor.constraint(equalTo: descStack.bottomAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            buttonsStack.topAnchor.constraint(greaterThanOrEqualTo: contentStack.bottomAnchor, constant: 12),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        // Add groups and show first
        contentStack.addArrangedSubview(keyGroup)
        contentStack.addArrangedSubview(appGroup)
        contentStack.addArrangedSubview(cmdGroup)
        contentStack.addArrangedSubview(profGroup)
        selectGroup(index: 0)

        preloadCurrent()
    }

    private func group(_ title: String, views: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(titleLabel)
        views.forEach { stack.addArrangedSubview($0) }
        return stack
    }

    @objc private func segmentedChanged() {
        selectGroup(index: segmented.selectedSegment)
    }

    private func selectGroup(index: Int) {
        for (i, v) in contentStack.arrangedSubviews.enumerated() {
            v.isHidden = (i != index)
        }
    }

    private func preloadCurrent() {
        let current = ConfigManager.shared.mappingForCurrentProfile()[buttonIndex]
        switch current {
        case .keySequence(let keys, let d):
            if let first = keys.first {
                keyField.stringValue = first.key
                set(mod: modCmd, from: first.modifiers.contains("cmd"))
                set(mod: modAlt, from: first.modifiers.contains("alt"))
                set(mod: modCtrl, from: first.modifiers.contains("ctrl"))
                set(mod: modShift, from: first.modifiers.contains("shift"))
            }
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 0
            selectGroup(index: 0)
        case .application(let path, let d):
            appPath.url = URL(fileURLWithPath: path)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 1
            selectGroup(index: 1)
        case .systemCommand(let cmd, let d):
            commandField.stringValue = cmd
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 2
            selectGroup(index: 2)
        case .profileSwitch(let profile, let d):
            profilePopup.selectItem(withTitle: profile)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 3
            selectGroup(index: 3)
        case .macro, .none:
            // Not supported in this lightweight editor yet
            break
        }
    }

    @objc private func cancelTapped() {
        dismiss(self)
        onComplete(nil)
    }

    @objc private func saveTapped() {
        let desc = descriptionField.stringValue.isEmpty ? nil : descriptionField.stringValue
        switch segmented.selectedSegment {
        case 0:
            let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty { onComplete(nil); dismiss(self); return }
            var mods: [String] = []
            if modCmd.state == .on { mods.append("cmd") }
            if modAlt.state == .on { mods.append("alt") }
            if modCtrl.state == .on { mods.append("ctrl") }
            if modShift.state == .on { mods.append("shift") }
            let ks = KeyStroke(key: key, modifiers: mods)
            onComplete(.keySequence(keys: [ks], description: desc))
        case 1:
            if let url = appPath.url {
                onComplete(.application(path: url.path, description: desc))
            } else {
                onComplete(nil)
            }
        case 2:
            let cmd = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if cmd.isEmpty { onComplete(nil) } else { onComplete(.systemCommand(command: cmd, description: desc)) }
        case 3:
            if let title = profilePopup.titleOfSelectedItem { onComplete(.profileSwitch(profile: title, description: desc)) } else { onComplete(nil) }
        default:
            onComplete(nil)
        }
        dismiss(self)
    }

    private func set(mod: NSButton, from on: Bool) { mod.state = on ? .on : .off }

    @objc private func browseApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.beginSheetModal(for: self.view.window!) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.appPath.url = url
        }
    }
}
