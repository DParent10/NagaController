import Cocoa
import UniformTypeIdentifiers
import QuartzCore

final class MappingViewController: NSViewController {
    private let headerLabel: NSTextField = {
        let l = NSTextField(labelWithString: ConfigManager.shared.currentProfileName)
        l.font = .systemFont(ofSize: 32, weight: .bold)
        l.textColor = UIStyle.razerGreen
        return l
    }()

    private let subHeaderLabel: NSTextField = {
        let l = NSTextField(labelWithString: "BUTTON MAPPING CONFIGURATION")
        l.font = .systemFont(ofSize: 11, weight: .black)
        l.textColor = NSColor.white.withAlphaComponent(0.3)
        return l
    }()

    private let profilePopup: NSPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let managePopup: NSPopUpButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let saveButton: NSButton = NSButton(title: "Save", target: nil, action: nil)
    private let stack = NSStackView() // unused legacy
    private var grid: NSGridView?
    private var isHypershiftView = false
    private let hypershiftToggle = NSButton(title: "Hypershift", target: nil, action: nil)

    private var rowViews: [Int: NSView] = [:]
    private var descLabels: [Int: NSTextField] = [:]
    private var container: NSStackView!
    private var topConstraint: NSLayoutConstraint?
    private var backgroundGradient: CAGradientLayer?
    private var profileObserver: NSObjectProtocol?

    override func loadView() {
        self.view = NSView()
        self.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 10.14, *) { self.view.appearance = NSAppearance(named: .darkAqua) }

        // Solid black background container
        let background = NSView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.cgColor
        view.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Subtle razer-green gradient tint over dark background
        let grad = CAGradientLayer()
        grad.colors = [
            UIStyle.razerGreen.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ]
        grad.startPoint = CGPoint(x: 0.1, y: 1.0)
        grad.endPoint = CGPoint(x: 1.0, y: 0.1)
        background.layer?.insertSublayer(grad, at: 0)
        backgroundGradient = grad
        
        background.layer?.backgroundColor = UIStyle.backgroundDark.cgColor

        // Top bar with profile selector and save button
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.distribution = .fill
        topBar.spacing = 16

        let profileLabel = NSTextField(labelWithString: "Profile:")
        profileLabel.textColor = .white
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged(_:))
        reloadProfilesPopup()

        // Manage profiles menu (pull-down)
        setupManageMenu()

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.image = UIStyle.symbol("tray.and.arrow.down", size: 14, weight: .semibold)
        saveButton.imagePosition = .imageLeading
        saveButton.toolTip = "Save all changes to disk"
        UIStyle.stylePrimaryButton(saveButton)
        saveButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        saveButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let titlesStack = NSStackView(views: [headerLabel, subHeaderLabel])
        titlesStack.orientation = .vertical
        titlesStack.alignment = .leading
        titlesStack.spacing = 0

        hypershiftToggle.setButtonType(.pushOnPushOff)
        hypershiftToggle.bezelStyle = .recessed
        hypershiftToggle.wantsLayer = true
        hypershiftToggle.layer?.cornerRadius = 8
        hypershiftToggle.target = self
        hypershiftToggle.action = #selector(hypershiftToggleTapped(_:))
        hypershiftToggle.font = .systemFont(ofSize: 13, weight: .bold)
        hypershiftToggle.image = UIStyle.symbol("bolt.fill", size: 14)
        hypershiftToggle.imagePosition = .imageLeading
        hypershiftToggle.widthAnchor.constraint(equalToConstant: 120).isActive = true
        hypershiftToggle.heightAnchor.constraint(equalToConstant: 32).isActive = true

        topBar.addArrangedSubview(titlesStack)
        topBar.addArrangedSubview(NSView()) // spacer
        topBar.addArrangedSubview(profileLabel)
        topBar.addArrangedSubview(profilePopup)
        topBar.addArrangedSubview(managePopup)
        topBar.addArrangedSubview(hypershiftToggle)
        topBar.addArrangedSubview(saveButton)

        // (Removed mouse visualization)

        // Three equal-width columns of cards
        let col1 = NSStackView(); col1.orientation = .vertical; col1.spacing = 16
        let col2 = NSStackView(); col2.orientation = .vertical; col2.spacing = 16
        let col3 = NSStackView(); col3.orientation = .vertical; col3.spacing = 16

        for idx in stride(from: 1, through: 10, by: 3) {
            let v = makeCard(for: idx); rowViews[idx] = v; col1.addArrangedSubview(v)
        }
        for idx in stride(from: 2, through: 11, by: 3) {
            let v = makeCard(for: idx); rowViews[idx] = v; col2.addArrangedSubview(v)
        }
        for idx in stride(from: 3, through: 12, by: 3) {
            let v = makeCard(for: idx); rowViews[idx] = v; col3.addArrangedSubview(v)
        }

        let columns = NSStackView(views: [col1, col2, col3])
        columns.orientation = .horizontal
        columns.spacing = 16
        columns.distribution = .fillEqually
        columns.translatesAutoresizingMaskIntoConstraints = false

        // Card container for columns
        let cardsCard = UIStyle.makeCard()
        cardsCard.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: cardsCard.leadingAnchor, constant: 16),
            columns.trailingAnchor.constraint(equalTo: cardsCard.trailingAnchor, constant: -16),
            columns.topAnchor.constraint(equalTo: cardsCard.topAnchor, constant: 16),
            columns.bottomAnchor.constraint(equalTo: cardsCard.bottomAnchor, constant: -16)
        ])

        let dpiStack = NSStackView()
        dpiStack.translatesAutoresizingMaskIntoConstraints = false
        dpiStack.orientation = .horizontal
        dpiStack.spacing = 16
        dpiStack.distribution = .fillEqually
        for idx in [13, 14] {
            let card = makeCard(for: idx)
            rowViews[idx] = card
            dpiStack.addArrangedSubview(card)
        }

        let extrasCard = UIStyle.makeCard()
        extrasCard.addSubview(dpiStack)
        NSLayoutConstraint.activate([
            dpiStack.leadingAnchor.constraint(equalTo: extrasCard.leadingAnchor, constant: 16),
            dpiStack.trailingAnchor.constraint(equalTo: extrasCard.trailingAnchor, constant: -16),
            dpiStack.topAnchor.constraint(equalTo: extrasCard.topAnchor, constant: 16),
            dpiStack.bottomAnchor.constraint(equalTo: extrasCard.bottomAnchor, constant: -16)
        ])

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(cardsCard)
        contentStack.addArrangedSubview(extrasCard)

        let scrollView = NSScrollView()
        scrollView.documentView = contentStack
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        // Main content area: scrollable mapping cards plus DPI buttons
        let content = scrollView

        container = NSStackView()
        container.orientation = .vertical
        container.spacing = 20
        container.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        container.addArrangedSubview(topBar)
        container.addArrangedSubview(makeSeparator())
        container.addArrangedSubview(content)

        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // Temporary top constraint to view; will re-anchor to window's contentLayoutGuide in viewDidAppear
        topConstraint = container.topAnchor.constraint(equalTo: view.topAnchor)
        topConstraint?.isActive = true

        refreshRows()

        profileObserver = NotificationCenter.default.addObserver(
            forName: ConfigManager.profileDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRows()
        }
    }

    deinit {
        if let profileObserver {
            NotificationCenter.default.removeObserver(profileObserver)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // After the view is attached to a window, move the top to the window's contentLayoutGuide
        if let guide = view.window?.contentLayoutGuide as? NSLayoutGuide {
            topConstraint?.isActive = false
            topConstraint = container.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8)
            topConstraint?.isActive = true
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let grad = backgroundGradient, let host = view.subviews.first {
            grad.frame = host.bounds
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let card = event.trackingArea?.userInfo?["card"] as? NSView else { return }
        highlight(card: card, on: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let card = event.trackingArea?.userInfo?["card"] as? NSView else { return }
        highlight(card: card, on: false)
    }

    private func highlight(card: NSView, on: Bool) {
        guard let layer = card.layer else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.borderWidth = on ? 1.5 : 0.5
            layer.borderColor = on ? UIStyle.razerGreen.withAlphaComponent(0.6).cgColor : NSColor.white.withAlphaComponent(0.12).cgColor
            layer.backgroundColor = on ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.white.withAlphaComponent(0.04).cgColor
            layer.shadowOpacity = on ? 0.4 : 0.3
            layer.shadowRadius = on ? 16 : 8
            layer.shadowColor = on ? UIStyle.razerGreen.withAlphaComponent(0.4).cgColor : NSColor.black.cgColor
            layer.transform = on ? CATransform3DMakeScale(1.03, 1.03, 1) : CATransform3DIdentity
        }
    }

    private func reloadProfilesPopup() {
        let names = ConfigManager.shared.availableProfiles()
        profilePopup.removeAllItems()
        profilePopup.addItems(withTitles: names)
        if let idx = names.firstIndex(of: ConfigManager.shared.currentProfileName) {
            profilePopup.selectItem(at: idx)
        }
    }

    private func setupManageMenu() {
        managePopup.autoenablesItems = false
        let m = managePopup.menu ?? NSMenu()
        m.removeAllItems()

        let title = NSMenuItem(title: "Manage Profiles", action: nil, keyEquivalent: "")
        title.isEnabled = false
        m.addItem(title)
        m.addItem(.separator())

        m.addItem(makeMenuItem("New…", action: #selector(newProfile), symbol: "plus.circle"))
        m.addItem(makeMenuItem("Duplicate…", action: #selector(duplicateProfile), symbol: "doc.on.doc"))
        m.addItem(makeMenuItem("Rename…", action: #selector(renameProfile), symbol: "pencil"))
        m.addItem(makeMenuItem("Delete…", action: #selector(deleteProfile), symbol: "trash", tintRed: true))
        m.addItem(.separator())
        m.addItem(makeMenuItem("Import…", action: #selector(importProfiles), symbol: "square.and.arrow.down"))
        m.addItem(makeMenuItem("Export Current…", action: #selector(exportCurrentProfile), symbol: "square.and.arrow.up"))
        m.addItem(makeMenuItem("Export All…", action: #selector(exportAllProfiles), symbol: "square.and.arrow.up.on.square"))

        managePopup.menu = m
        managePopup.select(nil)
    }

    private func makeMenuItem(_ title: String, action: Selector, symbol: String, tintRed: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = UIStyle.symbol(symbol, size: 13)
        if tintRed { item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed]) }
        return item
    }

    private func makeCard(for index: Int) -> NSView {
        let card = UIStyle.makeCard()
        card.translatesAutoresizingMaskIntoConstraints = false

        // Vertical content stack inside card
        let v = NSStackView()
        v.orientation = .vertical
        v.spacing = 8
        v.alignment = .leading
        v.translatesAutoresizingMaskIntoConstraints = false

        // Title row with big button number and profile-colored accent
        let title = NSTextField(labelWithString: displayName(for: index).uppercased())
        title.font = .systemFont(ofSize: 10, weight: .black)
        title.textColor = NSColor.white.withAlphaComponent(0.3)

        let desc = NSTextField(labelWithString: "")
        desc.lineBreakMode = .byWordWrapping
        desc.usesSingleLineMode = false
        desc.maximumNumberOfLines = 3
        desc.font = .systemFont(ofSize: 14, weight: .bold)
        desc.textColor = .white
        desc.alignment = .left
        
        // Ensure desc can wrap and take up space properly
        desc.setContentHuggingPriority(.defaultLow, for: .vertical)
        desc.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let edit = NSButton(title: "Configure", target: nil, action: nil)
        edit.image = UIStyle.symbol("pencil", size: 12, weight: .bold)
        edit.imagePosition = .imageLeading
        edit.tag = index
        edit.target = self
        edit.action = #selector(editTapped(_:))
        UIStyle.stylePrimaryButton(edit)
        
        // Make edit button wider
        edit.widthAnchor.constraint(equalToConstant: 100).isActive = true
        edit.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let clear = NSButton(title: "", target: nil, action: nil)
        clear.image = UIStyle.symbol("trash", size: 12, weight: .medium)
        clear.imagePosition = .imageOnly
        clear.toolTip = "Reset mapping for \(displayName(for: index))"
        clear.setAccessibilityLabel("Reset mapping for \(displayName(for: index))")
        clear.tag = index
        clear.target = self
        clear.action = #selector(clearTapped(_:))
        UIStyle.styleSecondaryButton(clear)
        clear.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        
        // Small circle clear button
        clear.widthAnchor.constraint(equalToConstant: 32).isActive = true
        clear.heightAnchor.constraint(equalToConstant: 32).isActive = true

        buttonRow.addArrangedSubview(edit)
        buttonRow.addArrangedSubview(clear)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        v.addArrangedSubview(title)
        v.addArrangedSubview(desc)
        v.addArrangedSubview(spacer) // flexible spacer
        v.addArrangedSubview(buttonRow)

        card.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            card.heightAnchor.constraint(equalToConstant: 160) // Enforce uniform height
        ])

        // Hover glow for card
        addHover(to: card)

        // Store desc label for later refresh
        descLabels[index] = desc
        return card
    }

    private func displayName(for index: Int) -> String {
        switch index {
        case 13: return "DPI Up"
        case 14: return "DPI Down"
        default: return "Button \(index)"
        }
    }

    private func addHover(to view: NSView) {
        view.wantsLayer = true
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: ["card": view])
        view.addTrackingArea(area)
    }

    private func refreshRows() {
        let mapping = isHypershiftView ? ConfigManager.shared.hypershiftMappingForCurrentProfile() : ConfigManager.shared.mappingForCurrentProfile()
        for i in 1...14 {
            descLabels[i]?.stringValue = actionDescription(mapping[i])
        }
        
        // Update toggle appearance
        hypershiftToggle.layer?.backgroundColor = isHypershiftView ? UIStyle.razerGreen.withAlphaComponent(0.2).cgColor : NSColor.white.withAlphaComponent(0.1).cgColor
        hypershiftToggle.contentTintColor = isHypershiftView ? UIStyle.razerGreen : .white
        
        headerLabel.stringValue = ConfigManager.shared.currentProfileName
        reloadProfilesPopup()
    }

    private func actionDescription(_ action: ActionType?) -> String {
        guard let action = action else { return "(Unassigned)" }
        switch action {
        case .keySequence(let keys, let d):
            let ks = keys.map { $0.formattedShortcut() }.joined(separator: ", ")
            return d ?? ks
        case .application(let path, let d):
            return d ?? "App: \(URL(fileURLWithPath: path).lastPathComponent)"
        case .systemCommand(let cmd, let d):
            return d ?? "Script: \(cmd)"
        case .textSnippet(let text, let d):
            let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            let truncated = preview.count > 40 ? String(preview.prefix(37)) + "…" : preview
            return d ?? "Text: \(truncated)"
        case .macro(_, let d):
            return d ?? "Macro"
        case .profileSwitch(let p, let d):
            return d ?? "Profile: \(p)"
        case .hypershift:
            return "Hypershift Modifier"
        case .mediaKey(let key, let d):
            return d ?? key.label
        }
    }

    @objc private func hypershiftToggleTapped(_ sender: NSButton) {
        isHypershiftView = (sender.state == .on)
        refreshRows()
    }

    @objc private func editTapped(_ sender: NSButton) {
        let idx = sender.tag
        let editor = ActionEditorViewController(buttonIndex: idx, initialLayer: isHypershiftView ? 1 : 0) { [weak self] in
            guard let self = self else { return }
            self.refreshRows()
        }
        presentAsSheet(editor)
    }

    @objc private func clearTapped(_ sender: NSButton) {
        let idx = sender.tag
        if isHypershiftView {
            ConfigManager.shared.setHypershiftAction(forButton: idx, action: nil)
        } else {
            ConfigManager.shared.setAction(forButton: idx, action: nil)
        }
        refreshRows()
    }

    @objc private func saveTapped() {
        ConfigManager.shared.saveUserProfiles()
    }

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        ConfigManager.shared.setCurrentProfile(title)
        refreshRows()
    }

    // MARK: - Manage actions

    @objc private func newProfile() {
        guard let name = promptForText(title: "New Profile", message: "Enter a name for the new profile:", defaultValue: "") else { return }
        if ConfigManager.shared.createProfile(name: name) {
            ConfigManager.shared.saveUserProfiles()
            refreshRows()
        } else {
            showInfo("Couldn't create profile. Name may be empty or already exists.")
        }
    }

    @objc private func duplicateProfile() {
        let current = ConfigManager.shared.currentProfileName
        guard let name = promptForText(title: "Duplicate Profile", message: "Enter a name for the duplicated profile:", defaultValue: "\(current) copy") else { return }
        if ConfigManager.shared.duplicateProfile(source: current, as: name) {
            ConfigManager.shared.saveUserProfiles()
            refreshRows()
        } else {
            showInfo("Couldn't duplicate. Name may be empty or already exists.")
        }
    }

    @objc private func renameProfile() {
        let current = ConfigManager.shared.currentProfileName
        guard let name = promptForText(title: "Rename Profile", message: "Enter a new name for profile ‘\(current)’:", defaultValue: current) else { return }
        if ConfigManager.shared.renameProfile(from: current, to: name) {
            ConfigManager.shared.saveUserProfiles()
            refreshRows()
        } else {
            showInfo("Couldn't rename. New name may be invalid or already exists.")
        }
    }

    @objc private func deleteProfile() {
        let current = ConfigManager.shared.currentProfileName
        let ok = confirm("Delete Profile", message: "Are you sure you want to delete ‘\(current)’? This cannot be undone.")
        if ok {
            if ConfigManager.shared.deleteProfile(named: current) {
                ConfigManager.shared.saveUserProfiles()
                refreshRows()
            } else {
                showInfo("Couldn't delete profile (it may be the last remaining profile).")
            }
        }
    }

    @objc private func importProfiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.allowedContentTypes = [.json]
        p.beginSheetModal(for: view.window!) { resp in
            guard resp == .OK, let url = p.url else { return }
            do {
                try ConfigManager.shared.importProfiles(from: url, merge: true)
                ConfigManager.shared.saveUserProfiles()
                self.refreshRows()
            } catch {
                self.showInfo("Failed to import: \(error.localizedDescription)")
            }
        }
    }

    @objc private func exportCurrentProfile() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "\(ConfigManager.shared.currentProfileName).json"
        p.beginSheetModal(for: view.window!) { resp in
            guard resp == .OK, let url = p.url else { return }
            do {
                try ConfigManager.shared.exportCurrentProfile(to: url)
            } catch {
                self.showInfo("Failed to export: \(error.localizedDescription)")
            }
        }
    }

    @objc private func exportAllProfiles() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "NagaController-profiles.json"
        p.beginSheetModal(for: view.window!) { resp in
            guard resp == .OK, let url = p.url else { return }
            do {
                try ConfigManager.shared.exportAllProfiles(to: url)
            } catch {
                self.showInfo("Failed to export: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UI helpers

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        let tf = NSTextField(string: defaultValue)
        tf.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return nil }
        return tf.stringValue
    }

    private func confirm(_ title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0.5
        box.borderColor = NSColor.white.withAlphaComponent(0.1)
        box.fillColor = NSColor.white.withAlphaComponent(0.5)
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func showInfo(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Info"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
 
