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

    private let inputmonitoringStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Checking…")
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        return label
    }()

    override func loadView() {
        // Base container with glassy effect (darker material for contrast)
        let glassyView = UIStyle.makeGlassyView()
        self.view = glassyView
        
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 20
        container.alignment = .centerX
        container.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        container.translatesAutoresizingMaskIntoConstraints = false
        glassyView.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: glassyView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: glassyView.trailingAnchor),
            container.topAnchor.constraint(equalTo: glassyView.topAnchor),
            container.bottomAnchor.constraint(equalTo: glassyView.bottomAnchor),
            glassyView.widthAnchor.constraint(equalToConstant: 320)
        ])

        // 1. Header Section
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = UIStyle.razerGreen
        
        let enabled = ConfigManager.shared.getRemappingEnabled()
        statusLabel.stringValue = enabled ? "Remapping active" : "Listen-only mode"
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        
        let batteryRow = NSStackView(views: [batteryLabel, batteryGlass])
        batteryRow.orientation = .horizontal
        batteryRow.spacing = 8
        batteryRow.alignment = .centerY
        batteryLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        batteryGlass.widthAnchor.constraint(equalToConstant: 60).isActive = true
        batteryGlass.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let headerStack = NSStackView(views: [titleLabel, statusLabel, batteryRow])
        headerStack.orientation = .vertical
        headerStack.spacing = 8
        headerStack.alignment = .centerX
        
        container.addArrangedSubview(headerStack)

        // 2. Actions Section (in a card)
        let actionsCard = UIStyle.makeCard()
        let actionsStack = NSStackView()
        actionsStack.orientation = .vertical
        actionsStack.spacing = 16
        actionsStack.alignment = .centerX
        actionsStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        // Target existing toggle action
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.state = enabled ? .on : .off
        toggle.font = .systemFont(ofSize: 13, weight: .medium)
        toggle.contentTintColor = .white
        
        configureButton.target = self
        configureButton.action = #selector(openMappings)
        UIStyle.stylePrimaryButton(configureButton)
        configureButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        configureButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        quitButton.target = NSApp
        quitButton.action = #selector(NSApplication.terminate(_:))
        UIStyle.styleDangerButton(quitButton)
        quitButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        quitButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        let toggleContainer = NSStackView(views: [toggle])
        toggleContainer.alignment = .centerX
        toggleContainer.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        (toggle.cell as? NSButtonCell)?.wraps = true
        toggleContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 230).isActive = true
        
        actionsStack.addArrangedSubview(toggleContainer)
        actionsStack.addArrangedSubview(configureButton)
        actionsStack.addArrangedSubview(quitButton)
        
        actionsCard.addSubview(actionsStack)
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actionsStack.topAnchor.constraint(equalTo: actionsCard.topAnchor),
            actionsStack.leadingAnchor.constraint(equalTo: actionsCard.leadingAnchor),
            actionsStack.trailingAnchor.constraint(equalTo: actionsCard.trailingAnchor),
            actionsStack.bottomAnchor.constraint(equalTo: actionsCard.bottomAnchor)
        ])
        
        container.addArrangedSubview(actionsCard)

        // 3. Permissions Section
        let permCard = UIStyle.makeCard()
        let permStack = NSStackView()
        permStack.orientation = .vertical
        permStack.spacing = 12
        permStack.alignment = .leading
        permStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        permissionHeaderLabel.font = .systemFont(ofSize: 11, weight: .black)
        permissionHeaderLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        permStack.addArrangedSubview(permissionHeaderLabel)
        
        permStack.addArrangedSubview(makePermissionRow(title: "Accessibility", statusLabel: accessibilityStatusLabel, selector: #selector(openAccessibilitySettings)))
        permStack.addArrangedSubview(makePermissionRow(title: "Input Monitoring", statusLabel: inputmonitoringStatusLabel, selector: #selector(openInputMonitoringSettings)))
        
        permCard.addSubview(permStack)
        permStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            permStack.topAnchor.constraint(equalTo: permCard.topAnchor),
            permStack.leadingAnchor.constraint(equalTo: permCard.leadingAnchor),
            permStack.trailingAnchor.constraint(equalTo: permCard.trailingAnchor),
            permStack.bottomAnchor.constraint(equalTo: permCard.bottomAnchor)
        ])
        
        container.addArrangedSubview(permCard)

        // Initial setup and observers
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
        EventTapManager.shared.start(listenOnly: !enabled)
        statusLabel.stringValue = enabled ? "Remapping active" : "Listen-only mode"
        statusLabel.textColor = .white
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
                batteryLabel.textColor = .white.withAlphaComponent(0.6)
            }
            batteryGlass.level = level
        } else {
            batteryLabel.stringValue = "Battery: —"
            batteryLabel.textColor = .white.withAlphaComponent(0.6)
            batteryGlass.level = nil
        }
    }

    func refreshPermissionStatuses() {
        updateStatus(label: accessibilityStatusLabel, granted: PermissionManager.shared.hasAccessibilityPermission())
        updateStatus(label: inputmonitoringStatusLabel, granted: PermissionManager.shared.hasInputMonitoringPermission())
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
        titleLabel.textColor = .white

        let spacer = NSView()

        let button = NSButton(title: "Open Settings", target: self, action: selector)
        UIStyle.styleSecondaryButton(button)
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.widthAnchor.constraint(equalToConstant: 120).isActive = true
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
