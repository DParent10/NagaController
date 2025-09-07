import Cocoa
import UniformTypeIdentifiers

final class MappingViewController: NSViewController {
    private let headerLabel: NSTextField = {
        let l = NSTextField(labelWithString: "Button Mappings — \(ConfigManager.shared.currentProfileName)")
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        return l
    }()

    private let profilePopup: NSPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let managePopup: NSPopUpButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let saveButton: NSButton = NSButton(title: "Save", target: nil, action: nil)
    private let stack = NSStackView()

    private var rowViews: [Int: NSView] = [:]
    private var descLabels: [Int: NSTextField] = [:]

    override func loadView() {
        self.view = NSView()
        self.view.translatesAutoresizingMaskIntoConstraints = false

        // Background effect for a modern look
        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        if #available(macOS 10.14, *) {
            effect.material = .sidebar
        }
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            effect.topAnchor.constraint(equalTo: view.topAnchor),
            effect.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Top bar with profile selector and save button
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .firstBaseline
        topBar.distribution = .fill
        topBar.spacing = 8

        let profileLabel = NSTextField(labelWithString: "Profile:")
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

        topBar.addArrangedSubview(headerLabel)
        topBar.addArrangedSubview(NSView()) // spacer
        topBar.addArrangedSubview(profileLabel)
        topBar.addArrangedSubview(profilePopup)
        topBar.addArrangedSubview(managePopup)
        topBar.addArrangedSubview(saveButton)

        // Rows for 1..12 inside a "card"
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        for idx in 1...12 {
            let row = makeRow(for: idx)
            rowViews[idx] = row
            stack.addArrangedSubview(row)
        }

        // Card container for rows
        let card = UIStyle.makeCard()
        card.contentViewMargins = NSSize(width: 8, height: 8)
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        container.addArrangedSubview(topBar)
        container.addArrangedSubview(NSBox())
        container.addArrangedSubview(card)

        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshRows()
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

    private func makeRow(for index: Int) -> NSView {
        let h = NSStackView()
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 8

        let label = NSTextField(labelWithString: "Button \(index)")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let desc = NSTextField(labelWithString: "")
        desc.lineBreakMode = .byTruncatingTail
        desc.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let edit = NSButton(title: "Edit…", target: nil, action: nil)
        edit.image = UIStyle.symbol("pencil", size: 13, weight: .regular)
        edit.imagePosition = .imageLeading
        edit.toolTip = "Edit button \(index) action"
        edit.tag = index
        edit.target = self
        edit.action = #selector(editTapped(_:))

        let clear = NSButton(title: "Clear", target: nil, action: nil)
        clear.image = UIStyle.symbol("trash", size: 13, weight: .regular)
        clear.imagePosition = .imageLeading
        clear.contentTintColor = .systemRed
        clear.toolTip = "Clear mapping for button \(index)"
        clear.tag = index
        clear.target = self
        clear.action = #selector(clearTapped(_:))

        h.addArrangedSubview(label)
        h.addArrangedSubview(NSBox()) // spacer
        h.addArrangedSubview(desc)
        h.addArrangedSubview(edit)
        h.addArrangedSubview(clear)

        h.translatesAutoresizingMaskIntoConstraints = false
        h.widthAnchor.constraint(equalToConstant: 520).isActive = true

        // Store desc label for later refresh
        descLabels[index] = desc
        return h
    }

    private func refreshRows() {
        let mapping = ConfigManager.shared.mappingForCurrentProfile()
        for i in 1...12 {
            descLabels[i]?.stringValue = actionDescription(mapping[i])
        }
        headerLabel.stringValue = "Button Mappings — \(ConfigManager.shared.currentProfileName)"
        reloadProfilesPopup()
    }

    private func actionDescription(_ action: ActionType?) -> String {
        guard let action = action else { return "(Unassigned)" }
        switch action {
        case .keySequence(let keys, let d):
            let ks = keys.map { stroke in
                let mods = stroke.modifiers.map { $0.capitalized }.joined(separator: "+")
                return mods.isEmpty ? stroke.key.uppercased() : "\(mods)+\(stroke.key.uppercased())"
            }.joined(separator: ", ")
            return d ?? "Key Sequence: \(ks)"
        case .application(let path, let d):
            return d ?? "Open App: \(path)"
        case .systemCommand(let cmd, let d):
            return d ?? "Command: \(cmd)"
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
 
