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

private struct ShortcutPreset {
    let name: String
    let key: String
    let modifiers: [String]
    let isHeader: Bool
    
    static func header(_ name: String) -> ShortcutPreset {
        ShortcutPreset(name: name, key: "", modifiers: [], isHeader: true)
    }
}

final class ActionEditorViewController: NSViewController {
    private let buttonIndex: Int
    private let onComplete: () -> Void
    private var initialRemappingState: Bool = false
    
    private let segmented = NSSegmentedControl(labels: ["Key", "App", "Cmd", "Text", "Profile", "macOS", "Hypershift"], trackingMode: .selectOne, target: nil, action: nil)
    private let layerSegmented = NSSegmentedControl(labels: ["Standard Layer", "Hypershift Layer"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Temporary storage for edits before saving
    private var tempStandardAction: ActionType?
    private var tempHypershiftAction: ActionType?
    private let initialLayer: Int
    
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

    // Presets
    private let presetsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presets: [ShortcutPreset] = [
        .header("Editing"),
        ShortcutPreset(name: "Copy", key: "c", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Paste", key: "v", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Cut", key: "x", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Undo", key: "z", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Redo", key: "z", modifiers: ["cmd", "shift"], isHeader: false),
        ShortcutPreset(name: "Select All", key: "a", modifiers: ["cmd"], isHeader: false),
        
        .header("Special Keys"),
        ShortcutPreset(name: "Return", key: "return", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Enter (keypad)", key: "enter", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Tab", key: "tab", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Escape", key: "escape", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Delete (Backspace)", key: "delete", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Space", key: "space", modifiers: [], isHeader: false),

        .header("Modifier Keys"),
        ShortcutPreset(name: "Command", key: "command", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Shift", key: "shift", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Option", key: "option", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Control", key: "control", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Fn", key: "fn", modifiers: [], isHeader: false)
    ]

    // Text Snippet
    private let textSnippetView = NSTextView(frame: .zero)
    private let textSnippetScroll = NSScrollView(frame: .zero)

    // macOS / Media Keys
    private var selectedMediaKey: MediaKeyType = .playPause
    private let macosPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let contentStack = NSStackView()
    
    // Hardware Learning
    private let hardwareBindingLabel = NSTextField(labelWithString: "Trigger: (Default)")
    private let learnButton = NSButton(title: "Learn Hardware Trigger…", target: nil, action: nil)
    private let clearHardwareButton = NSButton(title: "", target: nil, action: nil)
    private var isLearningHardware = false
    private var isCoolingDown = false

    // Hypershift mode picker (hold / toggle)
    private let hypershiftModeSegmented = NSSegmentedControl(
        labels: ["Hold to Activate", "Click to Toggle"],
        trackingMode: .selectOne, target: nil, action: nil
    )

    private var recordedKeyCode: UInt16?
    private var recordedKeyIdentifier: String?

    // Save/Cancel use Return and Escape as key equivalents. macOS routes those to the
    // buttons before the capture box sees them, so a user trying to record Enter just
    // saved and closed the editor. Suspend the equivalents while the box has focus.
    private var saveButton: NSButton!
    private var cancelButton: NSButton!

    init(buttonIndex: Int, initialLayer: Int = 0, onComplete: @escaping () -> Void) {
        self.buttonIndex = buttonIndex
        self.initialLayer = initialLayer
        self.onComplete = onComplete
        
        let standardActionMap = ConfigManager.shared.mappingForCurrentProfile()
        let hypershiftActionMap = ConfigManager.shared.hypershiftMappingForCurrentProfile()
        
        self.tempStandardAction = standardActionMap[buttonIndex]
        self.tempHypershiftAction = hypershiftActionMap[buttonIndex]
        
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let glassyView = UIStyle.makeGlassyView()
        glassyView.appearance = NSAppearance(named: .darkAqua)
        self.view = glassyView
        
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        glassyView.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: glassyView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: glassyView.trailingAnchor),
            container.topAnchor.constraint(equalTo: glassyView.topAnchor),
            container.bottomAnchor.constraint(equalTo: glassyView.bottomAnchor)
        ])

        let header = NSTextField(labelWithString: "Edit Action — Button \(buttonIndex)")
        header.font = .systemFont(ofSize: 22, weight: .bold)
        header.textColor = UIStyle.razerGreen
        
        layerSegmented.target = self
        layerSegmented.action = #selector(layerChanged)
        layerSegmented.selectedSegment = initialLayer

        segmented.target = self
        segmented.action = #selector(segmentedChanged)
        segmented.selectedSegment = 0

        // Description
        let descLabel = NSTextField(labelWithString: "Label / Description:")
        descLabel.font = .systemFont(ofSize: 11, weight: .black)
        descLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        descriptionField.placeholderString = "e.g. Copy, Open App, Paste"
        descriptionField.focusRingType = .none

        // Key UI
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = "Press a key..."
        keyField.alignment = .center
        keyField.isEditable = false
        keyField.drawsBackground = false
        keyField.isBordered = false
        keyField.font = .systemFont(ofSize: 16, weight: .bold)
        let keyFieldContainer = NSView()
        keyFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        keyFieldContainer.wantsLayer = true
        keyFieldContainer.layer?.cornerRadius = 8
        keyFieldContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        keyFieldContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        keyFieldContainer.layer?.borderWidth = 1
        keyFieldContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        keyFieldContainer.heightAnchor.constraint(equalToConstant: 44).isActive = true

        keyFieldContainer.addSubview(keyField)
        NSLayoutConstraint.activate([
            keyField.centerYAnchor.constraint(equalTo: keyFieldContainer.centerYAnchor),
            keyField.leadingAnchor.constraint(equalTo: keyFieldContainer.leadingAnchor, constant: 8),
            keyField.trailingAnchor.constraint(equalTo: keyFieldContainer.trailingAnchor, constant: -8)
        ])
        
        keyField.onKeyCaptured = { [weak self] event in
            self?.capture(event: event)
        }
        keyField.onFocusChanged = { [weak self, weak keyFieldContainer] focused in
            keyFieldContainer?.layer?.borderColor = (focused ? UIStyle.razerGreen.withAlphaComponent(0.6).cgColor : NSColor.white.withAlphaComponent(0.12).cgColor)
            keyFieldContainer?.layer?.borderWidth = focused ? 2 : 1
            keyFieldContainer?.layer?.backgroundColor = focused ? NSColor.white.withAlphaComponent(0.1).cgColor : NSColor.white.withAlphaComponent(0.05).cgColor
            self?.saveButton?.keyEquivalent = focused ? "" : "\r"
            self?.cancelButton?.keyEquivalent = focused ? "" : "\u{1b}"
        }

        [modCmd, modAlt, modCtrl, modShift].forEach { button in
            button.target = self
            button.action = #selector(modifierCheckboxChanged(_:))
            button.font = .systemFont(ofSize: 14, weight: .medium)
        }

        let keyRow = NSStackView(views: [NSTextField(labelWithString: "Key:"), keyFieldContainer])
        keyRow.spacing = 12
        keyRow.alignment = .centerY
        
        presetsPopup.addItem(withTitle: "Quick Presets…")
        for p in presets {
            if p.isHeader {
                presetsPopup.menu?.addItem(NSMenuItem.separator())
                let item = NSMenuItem(title: p.name, action: nil, keyEquivalent: "")
                item.isEnabled = false
                presetsPopup.menu?.addItem(item)
            } else {
                presetsPopup.addItem(withTitle: p.name)
            }
        }
        presetsPopup.target = self
        presetsPopup.action = #selector(presetSelected)
        
        let modsRow = NSStackView(views: [NSTextField(labelWithString: "Modifiers:"), modCmd, modAlt, modCtrl, modShift, NSView(), presetsPopup])
        modsRow.spacing = 10
        modsRow.alignment = .centerY

        let keyHint = NSTextField(labelWithString: "Focus the capture box, then press your shortcut.")
        keyHint.font = .systemFont(ofSize: 11)
        keyHint.textColor = NSColor.white.withAlphaComponent(0.4)
        
        let keyGroup = group("Key Sequence", views: [keyRow, modsRow, keyHint])

        // App UI
        appPath.url = nil
        appPath.pathStyle = .standard
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browseApp))
        browse.image = UIStyle.symbol("folder", size: 13)
        browse.imagePosition = .imageLeading
        UIStyle.styleSecondaryButton(browse)
        browse.widthAnchor.constraint(equalToConstant: 96).isActive = true
        browse.heightAnchor.constraint(equalToConstant: 28).isActive = true
        browse.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        appPath.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        let appRow = NSStackView(views: [NSTextField(labelWithString: "Path:"), appPath, browse])
        appRow.spacing = 12
        appRow.alignment = .centerY
        let appGroup = group("Application", views: [appRow])

        // Command UI
        commandField.placeholderString = "e.g. say Hello or osascript …"
        commandField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let cmdRow = NSStackView(views: [NSTextField(labelWithString: "Script:"), commandField])
        cmdRow.spacing = 12
        cmdRow.alignment = .centerY
        let cmdGroup = group("System Command", views: [cmdRow])

        // Text Snippet UI
        textSnippetView.isAutomaticQuoteSubstitutionEnabled = false
        textSnippetView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textSnippetView.textContainerInset = NSSize(width: 8, height: 8)
        textSnippetView.backgroundColor = NSColor.white.withAlphaComponent(0.05)
        textSnippetView.textColor = .white

        textSnippetScroll.documentView = textSnippetView
        textSnippetScroll.hasVerticalScroller = true
        textSnippetScroll.borderType = .noBorder
        textSnippetScroll.drawsBackground = false
        textSnippetScroll.wantsLayer = true
        textSnippetScroll.layer?.cornerRadius = 8
        textSnippetScroll.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        textSnippetScroll.translatesAutoresizingMaskIntoConstraints = false
        textSnippetScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true

        let textGroup = group("Text Snippet", views: [textSnippetScroll])

        // Profile UI
        let profLabel = NSTextField(labelWithString: "Profile:")
        profilePopup.addItems(withTitles: ConfigManager.shared.availableProfiles())
        let profRow = NSStackView(views: [profLabel, profilePopup])
        profRow.spacing = 12
        profRow.alignment = .centerY
        let profGroup = group("Profile Switch", views: [profRow])

        // macOS / Media UI
        for caseType in MediaKeyType.allCases {
            macosPopup.addItem(withTitle: caseType.label)
        }
        macosPopup.action = #selector(macosPresetSelected)
        macosPopup.target = self
        
        let macosRow = NSStackView(views: [NSTextField(labelWithString: "Select Action:"), macosPopup])
        macosRow.spacing = 12
        macosRow.alignment = .centerY
        let macosGroup = group("macOS / Media Keys", views: [macosRow])

        // Hypershift UI
        let hsHint = NSTextField(labelWithString: "This button unlocks the Hypershift layer. Choose how it activates below:")
        hsHint.font = .systemFont(ofSize: 12)
        hsHint.textColor = NSColor.white.withAlphaComponent(0.6)
        hsHint.lineBreakMode = .byWordWrapping
        hsHint.maximumNumberOfLines = 3

        let hsModeLabel = NSTextField(labelWithString: "Activation Mode:")
        hsModeLabel.font = .systemFont(ofSize: 11, weight: .black)
        hsModeLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        hypershiftModeSegmented.selectedSegment = 0 // default: hold

        let hsModeRow = NSStackView(views: [hsModeLabel, hypershiftModeSegmented])
        hsModeRow.spacing = 12
        hsModeRow.alignment = .centerY

        let hsGroup = group("Hypershift Active", views: [hsHint, hsModeRow])

        // Content stack
        contentStack.orientation = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let descStack = NSStackView(views: [descLabel, descriptionField])
        descStack.orientation = .vertical
        descStack.spacing = 8
        descStack.alignment = .leading

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 12
        
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.image = UIStyle.symbol("xmark", size: 14)
        cancelButton.imagePosition = .imageLeading
        cancelButton.keyEquivalent = "\u{1b}"
        UIStyle.styleSecondaryButton(cancelButton)
        cancelButton.widthAnchor.constraint(equalToConstant: 100).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.image = UIStyle.symbol("checkmark.circle.fill", size: 14, weight: .bold)
        saveButton.imagePosition = .imageLeading
        saveButton.keyEquivalent = "\r"
        UIStyle.stylePrimaryButton(saveButton)
        saveButton.widthAnchor.constraint(equalToConstant: 100).isActive = true
        saveButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        learnButton.target = self
        learnButton.action = #selector(learnHardwareTapped)
        UIStyle.styleSecondaryButton(learnButton)
        learnButton.widthAnchor.constraint(equalToConstant: 200).isActive = true
        learnButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        learnButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        learnButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        
        clearHardwareButton.target = self
        clearHardwareButton.action = #selector(clearHardwareTapped)
        clearHardwareButton.image = UIStyle.symbol("xmark.circle.fill", size: 14)
        clearHardwareButton.isBordered = false
        
        hardwareBindingLabel.font = .systemFont(ofSize: 12)
        hardwareBindingLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        hardwareBindingLabel.lineBreakMode = .byTruncatingTail
        hardwareBindingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // The hardware trigger row gets its own line: sharing the Cancel/Save row left
        // the "Trigger:" label with no room and it was truncated to nothing.
        let hardwareCaption = NSTextField(labelWithString: "HARDWARE TRIGGER")
        hardwareCaption.font = .systemFont(ofSize: 11, weight: .black)
        hardwareCaption.textColor = NSColor.white.withAlphaComponent(0.3)
        let hardwareStack = NSStackView(views: [learnButton, clearHardwareButton, hardwareBindingLabel, NSView()])
        hardwareStack.spacing = 10
        hardwareStack.alignment = .centerY
        let hardwareRow = NSStackView(views: [hardwareCaption, hardwareStack])
        hardwareRow.orientation = .vertical
        hardwareRow.alignment = .leading
        hardwareRow.spacing = 8
        hardwareStack.widthAnchor.constraint(equalTo: hardwareRow.widthAnchor).isActive = true

        buttonsStack.addArrangedSubview(NSView()) // Spacer
        buttonsStack.addArrangedSubview(cancelButton)
        buttonsStack.addArrangedSubview(saveButton)

        container.addSubview(header)
        container.addSubview(hardwareRow)
        hardwareRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(layerSegmented)
        container.addSubview(segmented)
        container.addSubview(descStack)
        container.addSubview(contentStack)
        container.addSubview(buttonsStack)

        for v in [header, layerSegmented, segmented, descStack, contentStack, buttonsStack] { v.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            
            layerSegmented.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            layerSegmented.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            segmented.topAnchor.constraint(equalTo: layerSegmented.bottomAnchor, constant: 24),
            segmented.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            descStack.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 24),
            descStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            descStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            contentStack.topAnchor.constraint(equalTo: descStack.bottomAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            hardwareRow.topAnchor.constraint(greaterThanOrEqualTo: contentStack.bottomAnchor, constant: 24),
            hardwareRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            hardwareRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            buttonsStack.topAnchor.constraint(equalTo: hardwareRow.bottomAnchor, constant: 20),
            buttonsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            buttonsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            buttonsStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -32),
            
            container.widthAnchor.constraint(equalToConstant: 540),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 600)
        ])

        // Add groups and show first
        let groups = [keyGroup, appGroup, cmdGroup, textGroup, profGroup, macosGroup, hsGroup]
        for groupView in groups {
            contentStack.addArrangedSubview(groupView)
            groupView.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
        selectGroup(index: 0)

        preloadCurrent()
        updateHardwareDisplay()
        
        initialRemappingState = !EventTapManager.shared.isListeningOnly
        EventTapManager.shared.start(listenOnly: true)
    }

    private func group(_ title: String, views: [NSView]) -> NSView {
        let box = UIStyle.makeCard()
        
        let header = NSTextField(labelWithString: title.uppercased())
        header.font = .systemFont(ofSize: 11, weight: .black)
        header.textColor = NSColor.white.withAlphaComponent(0.2)
        
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        
        for v in views {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let outer = NSStackView(views: [header, stack])
        outer.orientation = .vertical
        outer.spacing = 12
        outer.alignment = .leading
        
        stack.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        
        box.addSubview(outer)
        outer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20),
            outer.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -20),
            outer.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            outer.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -20)
        ])
        
        return box
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    @objc private func layerChanged() {
        // Save current UI state to temp var BEFORE switching view
        // Note: buildActionFromUI() reflects what is currently DISPLAYED.
        // If we are switching from Standard to Hypershift, buildActionFromUI() is the old Standard action.
        let action = buildActionFromUI()
        
        // layerSegmented.selectedSegment is the NEW value after the click
        if layerSegmented.selectedSegment == 1 {
            // We moved TO Hypershift, so the UI we just left was Standard
            tempStandardAction = action
            NSLog("[ActionEditor] Switched to Hypershift layer, cached Standard action: \(String(describing: action))")
        } else {
            // We moved TO Standard, so the UI we just left was Hypershift
            tempHypershiftAction = action
            NSLog("[ActionEditor] Switched to Standard layer, cached Hypershift action: \(String(describing: action))")
        }
        
        preloadCurrent()
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
        let current = layerSegmented.selectedSegment == 0 ? tempStandardAction : tempHypershiftAction
        recordedKeyCode = nil
        recordedKeyIdentifier = nil
        updateKeyFieldDisplay()
        applyModifiers(from: [])
        textSnippetView.string = ""
        descriptionField.stringValue = ""
        
        guard let action = current else {
            segmented.selectedSegment = 0
            selectGroup(index: 0)
            return
        }
        
        switch action {
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
        case .mediaKey(let key, let desc):
            macosPopup.selectItem(withTitle: key.label)
            selectedMediaKey = key
            descriptionField.stringValue = desc ?? ""
            segmented.selectedSegment = 5
            selectGroup(index: 5)
        case .hypershift(let mode):
            hypershiftModeSegmented.selectedSegment = (mode == .toggle) ? 1 : 0
            descriptionField.stringValue = ""
            segmented.selectedSegment = 6
            selectGroup(index: 6)
        case .macro:
            // Not supported in this lightweight editor yet
            break
        }
    }

    @objc private func cancelTapped() {
        dismiss(self)
        onComplete()
    }

    @objc private func saveTapped() {
        // Finalise the currently visible layer's UI state into temp storage
        let finalAction = buildActionFromUI()
        if layerSegmented.selectedSegment == 0 {
            tempStandardAction = finalAction
        } else {
            tempHypershiftAction = finalAction
        }

        NSLog("[ActionEditor] Saving both layers for button \(buttonIndex). Standard: \(String(describing: tempStandardAction)), Hypershift: \(String(describing: tempHypershiftAction))")

        // Save BOTH layers atomically
        ConfigManager.shared.setBothActions(
            forButton: buttonIndex,
            standard: tempStandardAction,
            hypershift: tempHypershiftAction
        )

        onComplete()
        dismiss(self)
    }
    
    private func buildActionFromUI() -> ActionType? {
        let desc = descriptionField.stringValue.isEmpty ? nil : descriptionField.stringValue
        switch segmented.selectedSegment {
        case 0:
            guard let identifier = recordedKeyIdentifier, !identifier.isEmpty else {
                return nil
            }
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            return .keySequence(keys: [stroke], description: desc)
        case 1:
            if let url = appPath.url {
                return .application(path: url.path, description: desc)
            } else {
                return nil
            }
        case 2:
            let cmd = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if cmd.isEmpty { return nil } else { return .systemCommand(command: cmd, description: desc) }
        case 3:
            let snippet = textSnippetView.string
            if snippet.trimmingCharacters(in: .newlines).isEmpty {
                return nil
            } else {
                return .textSnippet(text: snippet, description: desc)
            }
        case 4:
            if let title = profilePopup.titleOfSelectedItem { return .profileSwitch(profile: title, description: desc) } else { return nil }
        case 5:
            return .mediaKey(key: selectedMediaKey, description: desc)
        case 6:
            let mode: HypershiftMode = (hypershiftModeSegmented.selectedSegment == 1) ? .toggle : .hold
            return .hypershift(mode: mode)
        default:
            return nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // Learning callbacks live on singletons, so dismissing mid-learn would otherwise
        // leave the EventTap swallowing every keyDown/flagsChanged system-wide.
        if isLearningHardware {
            HIDListener.shared.setLearningCallback(nil)
            EventTapManager.shared.setLearningCallback(nil)
            isLearningHardware = false
        }
        EventTapManager.shared.start(listenOnly: !initialRemappingState)
    }

    private func set(mod: NSButton, from on: Bool) { mod.state = on ? .on : .off }

    private func capture(event: NSEvent) {
        if isLearningHardware || isCoolingDown { return }
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

    @objc private func presetSelected() {
        let title = presetsPopup.titleOfSelectedItem
        presetsPopup.selectItem(at: 0) // Reset to "Presets..."
        
        guard let title = title, title != "Quick Presets…" else { return }
        guard let preset = presets.first(where: { $0.name == title && !$0.isHeader }) else { return }
        
        recordedKeyIdentifier = preset.key
        recordedKeyCode = KeyStroke.keyCode(for: preset.key)
        applyModifiers(from: preset.modifiers)
        updateKeyFieldDisplay()
    }
    
    @objc private func macosPresetSelected() {
        guard let title = macosPopup.titleOfSelectedItem, 
              let key = MediaKeyType.allCases.first(where: { $0.label == title }) else { return }
        selectedMediaKey = key
    }

    // MARK: - Hardware Learning

    private var pendingUsagePage: UInt32?
    private var pendingUsage: UInt32?
    private var pendingCookie: UInt32?
    private var pendingKeyCode: CGKeyCode?
    private var pendingValue: Int32?
    private var pendingVendorID: Int?
    private var pendingProductID: Int?
    private var isFinalizingLearning = false

    @objc private func learnHardwareTapped() {
        isLearningHardware = true
        learnButton.title = "Press a button now..."
        learnButton.isEnabled = false
        
        pendingUsagePage = nil
        pendingUsage = nil
        pendingCookie = nil
        pendingKeyCode = nil
        pendingValue = nil
        pendingVendorID = nil
        pendingProductID = nil
        isFinalizingLearning = false
        
        HIDListener.shared.setLearningCallback { [weak self] page, usage, cookie, value, vendorID, productID in
            DispatchQueue.main.async {
                self?.pendingUsagePage = page
                self?.pendingUsage = usage
                self?.pendingCookie = UInt32(cookie)
                self?.pendingValue = value
                self?.pendingVendorID = vendorID
                self?.pendingProductID = productID
                self?.scheduleFinishLearning()
            }
        }
        
        EventTapManager.shared.setLearningCallback { [weak self] keyCode in
            DispatchQueue.main.async {
                self?.pendingKeyCode = keyCode
                self?.scheduleFinishLearning()
            }
        }
    }

    @objc private func clearHardwareTapped() {
        ConfigManager.shared.setHardwareBinding(forButton: buttonIndex, binding: nil)
        updateHardwareDisplay()
    }
    
    private func scheduleFinishLearning() {
        guard !isFinalizingLearning else { return }
        
        // If we have both, finish immediately
        if pendingUsage != nil && pendingKeyCode != nil {
            isFinalizingLearning = true
            finishLearning()
            return
        }
        
        // Timeout after 1 second if the other event doesn't arrive
        isFinalizingLearning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            // Only finish if it hasn't somehow already been reset
            if self.isLearningHardware {
                self.finishLearning()
            }
        }
    }

    private func finishLearning() {
        HIDListener.shared.setLearningCallback(nil)
        EventTapManager.shared.setLearningCallback(nil)
        isLearningHardware = false
        learnButton.title = "Learn Hardware Trigger…"
        learnButton.isEnabled = true

        // Guard: only save if we actually captured something meaningful
        guard pendingUsagePage != nil || pendingUsage != nil || pendingKeyCode != nil else {
            NSLog("[Learn] Timed out with no input — discarding empty binding")
            return
        }

        let binding = HardwareBinding(
            usagePage: pendingUsagePage,
            usage: pendingUsage,
            keyCode: pendingKeyCode.map { UInt16($0) },
            cookie: pendingCookie,
            value: pendingValue,
            vendorID: pendingVendorID,
            productID: pendingProductID
        )
        ConfigManager.shared.setHardwareBinding(forButton: buttonIndex, binding: binding)
        updateHardwareDisplay()

        // Cooldown: block capture() from picking up trailing events from the same physical press
        isCoolingDown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isCoolingDown = false
        }
    }

    private func updateHardwareDisplay() {
        let bindings = ConfigManager.shared.hardwareBindingsForCurrentProfile()
        if let binding = bindings[buttonIndex] {
            if let code = binding.keyCode {
                hardwareBindingLabel.stringValue = "Trigger: KeyCode 0x\(String(code, radix: 16))"
            } else if let page = binding.usagePage, let usage = binding.usage {
                var desc = String(format: "Trigger: Page 0x%X, Usage 0x%X", page, usage)
                if let val = binding.value {
                    desc += " (Value: \(val))"
                }
                hardwareBindingLabel.stringValue = desc
            } else {
                hardwareBindingLabel.stringValue = "Trigger: Custom"
            }
            clearHardwareButton.isHidden = false
        } else {
            hardwareBindingLabel.stringValue = "Trigger: (Default)"
            clearHardwareButton.isHidden = true
        }
    }
}
