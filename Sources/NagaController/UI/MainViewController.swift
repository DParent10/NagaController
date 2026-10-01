import Cocoa
import ServiceManagement

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
    private let launchAtLoginToggle = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let dockIconToggle = NSButton(checkboxWithTitle: "Show icon in Dock", target: nil, action: nil)
    private let updateBanner: NSButton = {
        let b = NSButton(title: "", target: nil, action: nil)
        b.isBordered = false
        b.font = .systemFont(ofSize: 11, weight: .semibold)
        b.contentTintColor = UIStyle.razerGreen
        b.isHidden = true
        return b
    }()
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
    private var updateObserver: NSObjectProtocol?

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

        updateBanner.target = self
        updateBanner.action = #selector(openReleasesPage)

        let headerStack = NSStackView(views: [titleLabel, statusLabel, batteryRow, updateBanner])
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

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginToggle.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        launchAtLoginToggle.font = .systemFont(ofSize: 13, weight: .medium)
        launchAtLoginToggle.contentTintColor = .white

        let launchAtLoginContainer = NSStackView(views: [launchAtLoginToggle])
        launchAtLoginContainer.alignment = .centerX
        launchAtLoginContainer.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        launchAtLoginContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 230).isActive = true

        dockIconToggle.target = self
        dockIconToggle.action = #selector(dockIconChanged(_:))
        dockIconToggle.state = UserDefaults.standard.bool(forKey: AppDelegate.showDockIconKey) ? .on : .off
        dockIconToggle.font = .systemFont(ofSize: 13, weight: .medium)
        dockIconToggle.contentTintColor = .white
        dockIconToggle.toolTip = "The app lives in the menu bar. Turn this on if the menu bar icon is hidden on your Mac, or you prefer a Dock icon."

        let dockIconContainer = NSStackView(views: [dockIconToggle])
        dockIconContainer.alignment = .centerX
        dockIconContainer.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        dockIconContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 230).isActive = true

        actionsStack.addArrangedSubview(toggleContainer)
        actionsStack.addArrangedSubview(launchAtLoginContainer)
        actionsStack.addArrangedSubview(dockIconContainer)
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

        updateObserver = NotificationCenter.default.addObserver(forName: UpdateChecker.didFindUpdateNotification, object: nil, queue: .main) { [weak self] note in
            self?.showUpdateBanner(version: note.object as? String)
        }
        showUpdateBanner(version: UpdateChecker.shared.availableVersion)
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        EventTapManager.shared.start(listenOnly: !enabled)
        statusLabel.stringValue = enabled ? "Remapping active" : "Listen-only mode"
        statusLabel.textColor = .white
        ConfigManager.shared.setRemappingEnabled(enabled)
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[LoginItem] Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            sender.state = enabled ? .off : .on
        }
    }

    @objc private func dockIconChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: AppDelegate.showDockIconKey)
        AppDelegate.applyDockIconPreference()
        // Switching to .regular can leave the app inactive; bring it forward so the window
        // and the new Dock icon are both visible immediately.
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openReleasesPage() {
        NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
    }

    private func showUpdateBanner(version: String?) {
        guard let version else {
            updateBanner.isHidden = true
            return
        }
        updateBanner.title = "Update available: v\(version)"
        updateBanner.isHidden = false
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
        let accessibilityGranted = PermissionManager.shared.hasAccessibilityPermission()
        let inputMonitoringGranted = PermissionManager.shared.hasInputMonitoringPermission()
        updateStatus(label: accessibilityStatusLabel, granted: accessibilityGranted)
        updateStatus(label: inputmonitoringStatusLabel, granted: inputMonitoringGranted)

        if accessibilityGranted && inputMonitoringGranted {
            promptToEnableRemappingIfNeeded()
        }
    }

    // Both permissions granted has never meant remapping is actually on — that's a
    // separate switch, and forgetting to flip it reads as "the app doesn't do anything"
    // (it did, twice, in testing). Nudge once per install rather than nagging forever.
    private func promptToEnableRemappingIfNeeded() {
        let nudgeKey = "NagaController.didNudgeEnableRemapping"
        guard !ConfigManager.shared.getRemappingEnabled(), !UserDefaults.standard.bool(forKey: nudgeKey) else { return }
        UserDefaults.standard.set(true, forKey: nudgeKey)

        let alert = NSAlert()
        alert.messageText = "Turn on remapping?"
        alert.informativeText = "Accessibility and Input Monitoring are both granted. Saved button mappings only take effect once remapping is switched on."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            toggle.state = .on
            toggleChanged(toggle)
        }
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
        if let obs = updateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
