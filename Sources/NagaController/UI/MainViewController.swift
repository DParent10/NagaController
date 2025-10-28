import Cocoa

final class MainViewController: NSViewController {
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "NagaController")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }()

    private let statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Listen-only mode")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private let batteryLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Battery: —")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private let batteryGlass = GlassyBatteryView()

    private let toggle = NSButton(checkboxWithTitle: "Enable remapping (blocks original keys)", target: nil, action: nil)
    private let configureButton: NSButton = {
        let b = NSButton(title: "Configure mappings…", target: nil, action: nil)
        b.image = UIStyle.symbol("slider.horizontal.3", size: 14, weight: .semibold)
        b.imagePosition = .imageLeading
        b.toolTip = "Open button mapping editor"
        return b
    }()

    private let quitButton: NSButton = {
        let b = NSButton(title: "Quit", target: nil, action: nil)
        b.image = UIStyle.symbol("power", size: 14, weight: .semibold)
        b.imagePosition = .imageLeading
        b.contentTintColor = .systemRed
        return b
    }()

    private var batteryObserver: NSObjectProtocol?
    private var permissionObserver: NSObjectProtocol?

    private let permissionHeaderLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Permissions")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        if #available(macOS 10.14, *) {
            label.textColor = .secondaryLabelColor
        }
        return label
    }()

    private let accessibilityStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Checking…")
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        return label
    }()

    private let inputMonitoringStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Checking…")
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        return label
    }()

    override func loadView() {
        // Root solid black view for popover content
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        // Subtle drop shadow
        container.shadow = NSShadow()
        container.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.15)
        container.shadow?.shadowBlurRadius = 20
        container.shadow?.shadowOffset = NSSize(width: 0, height: -2)

        self.view = container
        self.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 10.14, *) {
            self.view.appearance = NSAppearance(named: .darkAqua)
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))

        configureButton.target = self
        configureButton.action = #selector(openMappings)
        UIStyle.stylePrimaryButton(configureButton)

        quitButton.target = self
        quitButton.action = #selector(quitApp)
        UIStyle.styleDangerButton(quitButton)

        // Initialize from persisted setting
        let enabled = ConfigManager.shared.getRemappingEnabled()
        toggle.state = enabled ? .on : .off
        statusLabel.stringValue = enabled ? "Remapping enabled" : "Listen-only mode"
        if #available(macOS 10.14, *) {
            titleLabel.textColor = .white
            statusLabel.textColor = .white
            batteryLabel.textColor = .white
        }

        // Controls inside a card
        let controls = NSStackView()
        controls.orientation = .vertical
        controls.spacing = 8
        controls.addArrangedSubview(toggle)
        controls.addArrangedSubview(configureButton)

        // Battery glass view next to the label
        let batteryRow = NSStackView()
        batteryRow.orientation = .horizontal
        batteryRow.alignment = .centerY
        batteryRow.spacing = 8
        batteryGlass.translatesAutoresizingMaskIntoConstraints = false
        batteryGlass.heightAnchor.constraint(equalToConstant: 10).isActive = true
        batteryGlass.widthAnchor.constraint(equalToConstant: 60).isActive = true
        batteryRow.addArrangedSubview(batteryLabel)
        batteryRow.addArrangedSubview(batteryGlass)
        controls.addArrangedSubview(quitButton)

        controls.setCustomSpacing(12, after: configureButton)
        controls.addArrangedSubview(makeSeparator())

        let permissionsSection = NSStackView()
        permissionsSection.orientation = .vertical
        permissionsSection.spacing = 6
        permissionsSection.addArrangedSubview(permissionHeaderLabel)
        permissionsSection.addArrangedSubview(makePermissionRow(title: "Accessibility", statusLabel: accessibilityStatusLabel, selector: #selector(openAccessibilitySettings)))
        permissionsSection.addArrangedSubview(makePermissionRow(title: "Input Monitoring", statusLabel: inputMonitoringStatusLabel, selector: #selector(openInputMonitoringSettings)))
        controls.addArrangedSubview(permissionsSection)

        let card = UIStyle.makeCard()
        card.contentViewMargins = NSSize(width: 10, height: 10)
        card.addSubview(controls)
        controls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            controls.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            controls.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            controls.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(batteryRow)
        stack.addArrangedSubview(card)

        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Initialize battery label and subscribe to updates
        updateBattery()
        batteryObserver = NotificationCenter.default.addObserver(forName: BatteryMonitor.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBattery()
        }

        permissionObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPermissionStatuses()
        }

        refreshPermissionStatuses()
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        EventTapManager.shared.isRemappingEnabled = enabled
        statusLabel.stringValue = enabled ? "Remapping enabled" : "Listen-only mode"
        ConfigManager.shared.setRemappingEnabled(enabled)
    }

    @objc private func openMappings() {
        MappingWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateBattery() {
        if let level = BatteryMonitor.shared.batteryLevel {
            batteryLabel.stringValue = "Battery: \(level)%"
            if level <= 20 {
                batteryLabel.textColor = .systemRed
            } else {
                batteryLabel.textColor = .secondaryLabelColor
            }
            batteryGlass.level = level
        } else {
            batteryLabel.stringValue = "Battery: —"
            batteryLabel.textColor = .secondaryLabelColor
            batteryGlass.level = nil
        }
    }

    func refreshPermissionStatuses() {
        updateStatus(label: accessibilityStatusLabel, granted: PermissionManager.shared.hasAccessibilityPermission())
        updateStatus(label: inputMonitoringStatusLabel, granted: PermissionManager.shared.hasInputMonitoringPermission())
    }

    private func updateStatus(label: NSTextField, granted: Bool) {
        label.stringValue = granted ? "Granted" : "Missing"
        if #available(macOS 10.14, *) {
            label.textColor = granted ? .systemGreen : .systemOrange
        } else {
            label.textColor = granted ? .green : .orange
        }
    }

    private func makePermissionRow(title: String, statusLabel: NSTextField, selector: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        if #available(macOS 10.14, *) {
            titleLabel.textColor = .labelColor
        }

        let spacer = NSView()

        let button = NSButton(title: "Open Settings", target: self, action: selector)
        button.setButtonType(.momentaryPushIn)
        UIStyle.styleSecondaryButton(button)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(statusLabel)
        row.addArrangedSubview(button)

        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return row
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.shared.openAccessibilityPreferences()
    }

    @objc private func openInputMonitoringSettings() {
        PermissionManager.shared.openInputMonitoringPreferences()
    }

    deinit {
        if let obs = batteryObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = permissionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

