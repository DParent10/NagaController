import Cocoa
import UniformTypeIdentifiers

private final class KeyCaptureField: NSTextField {
    var onKeyCaptured: ((NSEvent) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            currentEditor()?.selectAll(nil)
            onFocusChanged?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChanged?(false)
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        onKeyCaptured?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyCaptured?(event)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

final class ActionEditorViewController: NSViewController {
    private let buttonIndex: Int
    private let onComplete: (ActionType?) -> Void

    private let segmented = NSSegmentedControl(labels: ["Key", "App", "Cmd", "Text", "Profile"], trackingMode: .selectOne, target: nil, action: nil)

    // Common
    private let descriptionField = NSTextField(string: "")

    // Key Sequence
    private let keyField = KeyCaptureField()
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

    // Text Snippet
    private let textSnippetView = NSTextView(frame: .zero)
    private let textSnippetScroll = NSScrollView(frame: .zero)

    private let contentStack = NSStackView()

    private var recordedKeyCode: UInt16?
    private var recordedKeyIdentifier: String?

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
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = "Press a key"
        keyField.alignment = .center
        keyField.isEditable = false
        keyField.drawsBackground = false
        keyField.isBordered = false
        keyField.font = .systemFont(ofSize: 16, weight: .medium)
        keyField.wantsLayer = true
        keyField.layer?.cornerRadius = 8
        keyField.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        keyField.layer?.borderColor = NSColor.separatorColor.cgColor
        keyField.layer?.borderWidth = 1
        keyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        keyField.setContentCompressionResistancePriority(.required, for: .horizontal)
        keyField.onKeyCaptured = { [weak self] event in
            self?.capture(event: event)
        }
        keyField.onFocusChanged = { [weak keyField] focused in
            keyField?.layer?.borderColor = (focused ? NSColor.systemBlue.cgColor : NSColor.separatorColor.cgColor)
            keyField?.layer?.borderWidth = focused ? 2 : 1
        }

        [modCmd, modAlt, modCtrl, modShift].forEach { button in
            button.target = self
            button.action = #selector(modifierCheckboxChanged(_:))
        }

        let keyRow = NSStackView(views: [NSTextField(labelWithString: "Key:"), keyField, NSView()])
        keyRow.spacing = 8
        let modsRow = NSStackView(views: [NSTextField(labelWithString: "Modifiers:"), modCmd, modAlt, modCtrl, modShift, NSView()])
        modsRow.spacing = 8
        let keyHint = NSTextField(labelWithString: "Click the capture box above, then press the keyboard shortcut you want to record (e.g. ⇧⌘4).")
        keyHint.font = .systemFont(ofSize: 11)
        keyHint.textColor = .secondaryLabelColor
        keyHint.lineBreakMode = .byWordWrapping
        keyHint.maximumNumberOfLines = 2
        let keyGroup = group("Key Sequence", views: [keyRow, modsRow, keyHint])

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

        // Text Snippet UI
        textSnippetView.isAutomaticQuoteSubstitutionEnabled = false
        textSnippetView.isAutomaticDashSubstitutionEnabled = false
        textSnippetView.isAutomaticLinkDetectionEnabled = false
        textSnippetView.isRichText = false
        textSnippetView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textSnippetView.textContainerInset = NSSize(width: 6, height: 6)
        textSnippetView.backgroundColor = .textBackgroundColor
        textSnippetView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textSnippetView.isVerticallyResizable = true
        textSnippetView.isHorizontallyResizable = false
        textSnippetView.textContainer?.widthTracksTextView = true

        textSnippetScroll.documentView = textSnippetView
        textSnippetScroll.hasVerticalScroller = true
        textSnippetScroll.borderType = .bezelBorder
        textSnippetScroll.translatesAutoresizingMaskIntoConstraints = false
        textSnippetScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let textHint = NSTextField(labelWithString: "Type the text you want this button to output. It will be sent exactly as written when pressed.")
        textHint.font = .systemFont(ofSize: 11)
        textHint.textColor = .secondaryLabelColor
        textHint.lineBreakMode = .byWordWrapping
        textHint.maximumNumberOfLines = 2
        let textGroup = group("Text Snippet", views: [textSnippetScroll, textHint])

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
        contentStack.addArrangedSubview(textGroup)
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

    override func viewDidAppear() {
        super.viewDidAppear()
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    @objc private func segmentedChanged() {
        selectGroup(index: segmented.selectedSegment)
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    private func selectGroup(index: Int) {
        for (i, v) in contentStack.arrangedSubviews.enumerated() {
            v.isHidden = (i != index)
        }
    }

    private func preloadCurrent() {
        let current = ConfigManager.shared.mappingForCurrentProfile()[buttonIndex]
        recordedKeyCode = nil
        recordedKeyIdentifier = nil
        updateKeyFieldDisplay()
        applyModifiers(from: [])
        textSnippetView.string = ""
        switch current {
        case .keySequence(let keys, let d):
            if let first = keys.first {
                recordedKeyIdentifier = first.key
                recordedKeyCode = first.keyCode ?? KeyStroke.keyCode(for: first.key)
                applyModifiers(from: first.modifiers)
                updateKeyFieldDisplay()
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
        case .textSnippet(let text, let d):
            textSnippetView.string = text
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 3
            selectGroup(index: 3)
        case .profileSwitch(let profile, let d):
            profilePopup.selectItem(withTitle: profile)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 4
            selectGroup(index: 4)
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
            guard let identifier = recordedKeyIdentifier, !identifier.isEmpty else {
                onComplete(nil)
                dismiss(self)
                return
            }
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            onComplete(.keySequence(keys: [stroke], description: desc))
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
            let snippet = textSnippetView.string
            if snippet.trimmingCharacters(in: .newlines).isEmpty {
                onComplete(nil)
            } else {
                onComplete(.textSnippet(text: snippet, description: desc))
            }
        case 4:
            if let title = profilePopup.titleOfSelectedItem { onComplete(.profileSwitch(profile: title, description: desc)) } else { onComplete(nil) }
        default:
            onComplete(nil)
        }
        dismiss(self)
    }

    private func set(mod: NSButton, from on: Bool) { mod.state = on ? .on : .off }

    private func capture(event: NSEvent) {
        if event.type == .flagsChanged {
            applyModifiers(from: event.modifierFlags)
            updateKeyFieldDisplay()
            return
        }

        guard event.type == .keyDown else { return }
        if event.isARepeat { return }

        applyModifiers(from: event.modifierFlags)

        let keyCode = UInt16(event.keyCode)
        let canonical = KeyStroke.canonicalKeyString(for: keyCode, characters: event.charactersIgnoringModifiers)
        guard !canonical.isEmpty else {
            NSSound.beep()
            return
        }

        recordedKeyCode = keyCode
        recordedKeyIdentifier = canonical
        updateKeyFieldDisplay()
    }

    private func updateKeyFieldDisplay() {
        if let identifier = recordedKeyIdentifier, !identifier.isEmpty {
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            let display = stroke.formattedShortcut()
            keyField.stringValue = display
            keyField.toolTip = display
        } else {
            keyField.stringValue = ""
            keyField.toolTip = nil
        }
    }

    private func applyModifiers(from flags: NSEvent.ModifierFlags) {
        set(mod: modCmd, from: flags.contains(.command))
        set(mod: modAlt, from: flags.contains(.option))
        set(mod: modCtrl, from: flags.contains(.control))
        set(mod: modShift, from: flags.contains(.shift))
        updateKeyFieldDisplay()
    }

    private func applyModifiers(from identifiers: [String]) {
        let lower = Set(identifiers.map { $0.lowercased() })
        set(mod: modCmd, from: lower.contains("cmd") || lower.contains("command"))
        set(mod: modAlt, from: lower.contains("alt") || lower.contains("option"))
        set(mod: modCtrl, from: lower.contains("ctrl") || lower.contains("control"))
        set(mod: modShift, from: lower.contains("shift"))
        updateKeyFieldDisplay()
    }

    private func currentModifiers() -> [String] {
        var result: [String] = []
        if modCmd.state == .on { result.append("cmd") }
        if modAlt.state == .on { result.append("alt") }
        if modCtrl.state == .on { result.append("ctrl") }
        if modShift.state == .on { result.append("shift") }
        return result
    }

    @objc private func modifierCheckboxChanged(_ sender: NSButton) {
        updateKeyFieldDisplay()
    }

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
