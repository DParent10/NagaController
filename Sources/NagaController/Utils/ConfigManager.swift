import Foundation

// Keys for persistence
private let kRemappingEnabledKey = "remappingEnabled"
private let kCurrentProfileKey = "currentProfile"

struct ProfilesFile: Codable {
    var profiles: [String: Profile]
    var settings: Settings?
}

struct Settings: Codable {
    var currentProfile: String?
    var autoSwitchProfiles: Bool?
    var showNotifications: Bool?
}

struct Profile: Codable {
    var buttons: [String: ButtonAction]
}

struct ButtonAction: Codable {
    let type: String
    let keys: [KeyStroke]? // for keySequence
    let description: String?
    let path: String? // for application
    let command: String? // for systemCommand
    let text: String? // for textSnippet
    let steps: [MacroStep]? // for macro
    let profile: String? // for profileSwitch
}

final class ConfigManager {
    static let shared = ConfigManager()

    private(set) var profiles: [String: Profile] = [:]
    private(set) var currentProfileName: String = "Default"

    private init() {}

    func load() {
        // Load bundled defaults first
        var mergedProfiles: [String: Profile] = [:]
        var mergedSettings: Settings? = nil
        if let url = Bundle.main.url(forResource: "default-profiles", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let pf = try JSONDecoder().decode(ProfilesFile.self, from: data)
                mergedProfiles = pf.profiles
                mergedSettings = pf.settings
            } catch {
                NSLog("[Config] Failed to load bundled defaults: \(error.localizedDescription)")
            }
        } else {
            NSLog("[Config] default-profiles.json not found in bundle")
        }

        // Overlay with user profiles if present
        if let userURL = try? userProfilesURL(), FileManager.default.fileExists(atPath: userURL.path) {
            do {
                let userData = try Data(contentsOf: userURL)
                let upf = try JSONDecoder().decode(ProfilesFile.self, from: userData)
                // Overlay: replace/merge profiles
                for (name, profile) in upf.profiles { mergedProfiles[name] = profile }
                // Overlay settings
                if let s = upf.settings { mergedSettings = s }
            } catch {
                NSLog("[Config] Failed to load user profiles: \(error.localizedDescription)")
            }
        }

        // Adopt merged
        self.profiles = mergedProfiles

        // Preferred profile: UserDefaults > settings.currentProfile > "Default"
        let ud = UserDefaults.standard
        if let saved = ud.string(forKey: kCurrentProfileKey) {
            currentProfileName = saved
        } else if let bundled = mergedSettings?.currentProfile {
            currentProfileName = bundled
        } else {
            currentProfileName = "Default"
        }

        // Apply mapping to ButtonMapper
        let mapping = mappingForCurrentProfile()
        if mapping.isEmpty {
            applyFallbackMapping()
        } else {
            ButtonMapper.shared.updateMapping(mapping)
        }
    }

    func setCurrentProfile(_ name: String) {
        guard profiles[name] != nil else { return }
        currentProfileName = name
        UserDefaults.standard.set(name, forKey: kCurrentProfileKey)
        ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
    }

    func getRemappingEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: kRemappingEnabledKey)
    }

    func setRemappingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: kRemappingEnabledKey)
    }

    func availableProfiles() -> [String] {
        return Array(profiles.keys).sorted()
    }

    func mappingForCurrentProfile() -> [Int: ActionType] {
        guard let profile = profiles[currentProfileName] else { return [:] }
        var result: [Int: ActionType] = [:]
        for (key, action) in profile.buttons {
            if let idx = Int(key), let mapped = convert(action: action) {
                result[idx] = mapped
            }
        }
        return result
    }

    // MARK: - Profile Management

    @discardableResult
    func createProfile(name: String, basedOn base: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, profiles[trimmed] == nil else { return false }
        if let base = base, let p = profiles[base] {
            profiles[trimmed] = p
        } else {
            profiles[trimmed] = Profile(buttons: [:])
        }
        setCurrentProfile(trimmed)
        return true
    }

    @discardableResult
    func duplicateProfile(source: String, as newName: String) -> Bool {
        return createProfile(name: newName, basedOn: source)
    }

    @discardableResult
    func renameProfile(from oldName: String, to newName: String) -> Bool {
        let newTrim = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard oldName != newTrim, !newTrim.isEmpty, let existing = profiles[oldName], profiles[newTrim] == nil else { return false }
        profiles.removeValue(forKey: oldName)
        profiles[newTrim] = existing
        if currentProfileName == oldName { currentProfileName = newTrim }
        UserDefaults.standard.set(currentProfileName, forKey: kCurrentProfileKey)
        return true
    }

    @discardableResult
    func deleteProfile(named name: String) -> Bool {
        guard profiles[name] != nil else { return false }
        // Prevent deleting the last profile
        if profiles.count <= 1 { return false }
        profiles.removeValue(forKey: name)
        if currentProfileName == name {
            // Switch to an arbitrary remaining profile
            if let next = profiles.keys.sorted().first {
                setCurrentProfile(next)
            }
        } else {
            // refresh mapping for current profile
            ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
        }
        return true
    }

    // MARK: - Import / Export

    func importProfiles(from url: URL, merge: Bool = true) throws {
        let data = try Data(contentsOf: url)
        let pf = try JSONDecoder().decode(ProfilesFile.self, from: data)
        if merge {
            for (k, v) in pf.profiles { profiles[k] = v }
        } else {
            profiles = pf.profiles
        }
        if let cp = pf.settings?.currentProfile, profiles[cp] != nil {
            setCurrentProfile(cp)
        } else {
            ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
        }
    }

    func exportCurrentProfile(to url: URL) throws {
        guard let p = profiles[currentProfileName] else { return }
        let pf = ProfilesFile(profiles: [currentProfileName: p], settings: Settings(currentProfile: currentProfileName, autoSwitchProfiles: nil, showNotifications: nil))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pf)
        try data.write(to: url, options: .atomic)
    }

    func exportAllProfiles(to url: URL) throws {
        let pf = ProfilesFile(profiles: profiles, settings: Settings(currentProfile: currentProfileName, autoSwitchProfiles: nil, showNotifications: nil))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pf)
        try data.write(to: url, options: .atomic)
    }

    private func convert(action: ButtonAction) -> ActionType? {
        switch action.type {
        case "keySequence":
            return .keySequence(keys: action.keys ?? [], description: action.description)
        case "application":
            if let path = action.path { return .application(path: path, description: action.description) }
            return nil
        case "systemCommand":
            if let cmd = action.command { return .systemCommand(command: cmd, description: action.description) }
            return nil
        case "textSnippet":
            if let text = action.text { return .textSnippet(text: text, description: action.description) }
            return nil
        case "macro":
            return .macro(steps: action.steps ?? [], description: action.description)
        case "profileSwitch":
            if let p = action.profile { return .profileSwitch(profile: p, description: action.description) }
            return nil
        default:
            return nil
        }
    }

    private func toButtonAction(_ action: ActionType) -> ButtonAction {
        switch action {
        case .keySequence(let keys, let description):
            return ButtonAction(type: "keySequence", keys: keys, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil)
        case .application(let path, let description):
            return ButtonAction(type: "application", keys: nil, description: description, path: path, command: nil, text: nil, steps: nil, profile: nil)
        case .systemCommand(let command, let description):
            return ButtonAction(type: "systemCommand", keys: nil, description: description, path: nil, command: command, text: nil, steps: nil, profile: nil)
        case .textSnippet(let text, let description):
            return ButtonAction(type: "textSnippet", keys: nil, description: description, path: nil, command: nil, text: text, steps: nil, profile: nil)
        case .macro(let steps, let description):
            return ButtonAction(type: "macro", keys: nil, description: description, path: nil, command: nil, text: nil, steps: steps, profile: nil)
        case .profileSwitch(let profile, let description):
            return ButtonAction(type: "profileSwitch", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: profile)
        }
    }

    // Update a single button's action in the current profile and refresh mapping
    func setAction(forButton index: Int, action: ActionType?) {
        var profile = profiles[currentProfileName] ?? Profile(buttons: [:])
        let key = String(index)
        if let action = action {
            profile.buttons[key] = toButtonAction(action)
        } else {
            profile.buttons.removeValue(forKey: key)
        }
        profiles[currentProfileName] = profile
        ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
    }

    // Persist current profiles to Application Support
    func saveUserProfiles() {
        do {
            let url = try userProfilesURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let pf = ProfilesFile(profiles: profiles, settings: Settings(currentProfile: currentProfileName, autoSwitchProfiles: nil, showNotifications: nil))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(pf)
            try data.write(to: url, options: .atomic)
            NSLog("[Config] Saved profiles to: \(url.path)")
        } catch {
            NSLog("[Config] Failed to save profiles: \(error.localizedDescription)")
        }
    }

    private func userProfilesURL() throws -> URL {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return appSupport.appendingPathComponent("NagaController/profiles.json")
    }

    private func applyFallbackMapping() {
        // Minimal fallback: Copy/Paste for 1 and 2
        let mapping: [Int: ActionType] = [
            1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: "Copy"),
            2: .keySequence(keys: [KeyStroke(key: "v", modifiers: ["cmd"])], description: "Paste")
        ]
        ButtonMapper.shared.updateMapping(mapping)
    }
}
