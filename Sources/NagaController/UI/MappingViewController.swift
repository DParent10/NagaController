import Cocoa
import UniformTypeIdentifiers
import QuartzCore

final class MappingViewController: NSViewController {
    private let headerLabel: NSTextField = {
        let l = NSTextField(labelWithString: "Button Mappings — \(ConfigManager.shared.currentProfileName)")
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        return l
    }()

    private let profilePopup: NSPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let managePopup: NSPopUpButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let saveButton: NSButton = NSButton(title: "Save", target: nil, action: nil)
    private let stack = NSStackView() // unused legacy
    private var grid: NSGridView?

    private var rowViews: [Int: NSView] = [:]
    private var descLabels: [Int: NSTextField] = [:]
    private var container: NSStackView!
    private var topConstraint: NSLayoutConstraint?
    private var backgroundGradient: CAGradientLayer?

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

        // Subtle razer-green gradient tint over black
        let grad = CAGradientLayer()
        grad.colors = [
            UIStyle.razerGreen.withAlphaComponent(0.10).cgColor,
            NSColor.clear.cgColor
        ]
        grad.startPoint = CGPoint(x: 0.0, y: 1.0)
        grad.endPoint = CGPoint(x: 1.0, y: 0.0)
        background.layer?.insertSublayer(grad, at: 0)
        backgroundGradient = grad

        // Top bar with profile selector and save button
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .firstBaseline
        topBar.distribution = .fill
        topBar.spacing = 8

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

        topBar.addArrangedSubview(headerLabel)
        topBar.addArrangedSubview(NSView()) // spacer
        topBar.addArrangedSubview(profileLabel)
        topBar.addArrangedSubview(profilePopup)
        topBar.addArrangedSubview(managePopup)
        topBar.addArrangedSubview(saveButton)

        // (Removed mouse visualization)

        // Three equal-width columns of cards (1,4,7,10 | 2,5,8,11 | 3,6,9,12)
        let col1 = NSStackView(); col1.orientation = .vertical; col1.spacing = 12
        let col2 = NSStackView(); col2.orientation = .vertical; col2.spacing = 12
        let col3 = NSStackView(); col3.orientation = .vertical; col3.spacing = 12

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
        columns.spacing = 12
        columns.distribution = .fillEqually
        columns.translatesAutoresizingMaskIntoConstraints = false

        // Card container for columns
        let cardsCard = UIStyle.makeCard()
        cardsCard.contentViewMargins = NSSize(width: 10, height: 10)
        cardsCard.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: cardsCard.leadingAnchor, constant: 10),
            columns.trailingAnchor.constraint(equalTo: cardsCard.trailingAnchor, constant: -10),
            columns.topAnchor.constraint(equalTo: cardsCard.topAnchor, constant: 10),
            columns.bottomAnchor.constraint(equalTo: cardsCard.bottomAnchor, constant: -10)
        ])

        let dpiStack = NSStackView()
        dpiStack.orientation = .vertical
        dpiStack.spacing = 12
        dpiStack.translatesAutoresizingMaskIntoConstraints = false
        for idx in [13, 14] {
            let card = makeCard(for: idx)
            rowViews[idx] = card
            dpiStack.addArrangedSubview(card)
        }

        let extrasCard = UIStyle.makeCard()
        extrasCard.contentViewMargins = NSSize(width: 10, height: 10)
        extrasCard.addSubview(dpiStack)
        NSLayoutConstraint.activate([
            dpiStack.leadingAnchor.constraint(equalTo: extrasCard.leadingAnchor, constant: 10),
            dpiStack.trailingAnchor.constraint(equalTo: extrasCard.trailingAnchor, constant: -10),
            dpiStack.topAnchor.constraint(equalTo: extrasCard.topAnchor, constant: 10),
            dpiStack.bottomAnchor.constraint(equalTo: extrasCard.bottomAnchor, constant: -10)
        ])

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(cardsCard)
        contentStack.addArrangedSubview(extrasCard)

        // Main content area: mapping cards plus DPI buttons
        let content = contentStack

        container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        container.addArrangedSubview(topBar)
        container.addArrangedSubview(NSBox()) // separator
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
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.borderWidth = on ? 2.0 : 0.5
            layer.borderColor = on ? UIStyle.razerGreen.withAlphaComponent(0.9).cgColor : NSColor.white.withAlphaComponent(0.18).cgColor
            layer.shadowOpacity = on ? 0.25 : 0.0
            layer.shadowRadius = on ? 12 : 0
            layer.shadowColor = UIStyle.razerGreen.withAlphaComponent(0.6).cgColor
            layer.shadowOffset = CGSize(width: 0, height: 0)
            layer.transform = on ? CATransform3DMakeScale(1.02, 1.02, 1) : CATransform3DIdentity
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
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false

        // Title row with big button number and profile-colored accent
        let title = NSTextField(labelWithString: displayName(for: index))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white

        let desc = NSTextField(labelWithString: "")
        desc.lineBreakMode = .byTruncatingTail
        desc.textColor = .white

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let edit = NSButton(title: "Edit…", target: nil, action: nil)
        edit.bezelStyle = .rounded
        edit.image = UIStyle.symbol("pencil", size: 13, weight: .regular)
        edit.imagePosition = .imageLeading
        edit.toolTip = "Edit mapping for \(displayName(for: index))"
        edit.tag = index
        edit.target = self
        edit.action = #selector(editTapped(_:))
        UIStyle.stylePrimaryButton(edit)

        let clear = NSButton(title: "Clear", target: nil, action: nil)
        clear.bezelStyle = .rounded
        clear.image = UIStyle.symbol("trash", size: 13, weight: .regular)
        clear.imagePosition = .imageLeading
        clear.contentTintColor = .systemRed
        clear.toolTip = "Clear mapping for \(displayName(for: index))"
        clear.tag = index
        clear.target = self
        clear.action = #selector(clearTapped(_:))
        UIStyle.styleSecondaryButton(clear)

        buttonRow.addArrangedSubview(edit)
        buttonRow.addArrangedSubview(clear)

        v.addArrangedSubview(title)
        v.addArrangedSubview(desc)
        v.addArrangedSubview(buttonRow)

        card.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
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
        let mapping = ConfigManager.shared.mappingForCurrentProfile()
        for i in 1...14 {
            descLabels[i]?.stringValue = actionDescription(mapping[i])
        }
        headerLabel.stringValue = "Button Mappings — \(ConfigManager.shared.currentProfileName)"
        reloadProfilesPopup()
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

    @objc private func editTapped(_ sender: NSButton) {
        let idx = sender.tag
        let editor = ActionEditorViewController(buttonIndex: idx) { [weak self] action in
            if let action = action {
                ConfigManager.shared.setAction(forButton: idx, action: action)
            }
            self?.refreshRows()
        }
        presentAsSheet(editor)
    }

    @objc private func clearTapped(_ sender: NSButton) {
        ConfigManager.shared.setAction(forButton: sender.tag, action: nil)
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

    private func showInfo(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Info"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
 
