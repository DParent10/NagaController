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
    var hardwareBindings: [String: HardwareBinding]?
    var hypershiftMappings: [String: ButtonAction]?
}

struct HardwareBinding: Codable {
    var usagePage: UInt32?
    var usage: UInt32?
    var keyCode: UInt16?
    var cookie: UInt32?
    var value: Int32?
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
    let mediaKey: Int? // for mediaKey
    let mode: String? // for hypershift
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
        ButtonMapper.shared.updateHypershiftMapping(hypershiftMappingForCurrentProfile())
    }

    func setCurrentProfile(_ name: String) {
        guard profiles[name] != nil else { return }
        currentProfileName = name
        UserDefaults.standard.set(name, forKey: kCurrentProfileKey)
        ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
        ButtonMapper.shared.updateHypershiftMapping(hypershiftMappingForCurrentProfile())
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

    func hypershiftMappingForCurrentProfile() -> [Int: ActionType] {
        guard let profile = profiles[currentProfileName] else { return [:] }
        var result: [Int: ActionType] = [:]
        if let mappings = profile.hypershiftMappings {
            for (key, action) in mappings {
                if let idx = Int(key), let mapped = convert(action: action) {
                    result[idx] = mapped
                }
            }
        }
        return result
    }

    func hardwareBindingsForCurrentProfile() -> [Int: HardwareBinding] {
        guard let profile = profiles[currentProfileName] else { return [:] }
        var result: [Int: HardwareBinding] = [:]
        if let bindings = profile.hardwareBindings {
            for (key, binding) in bindings {
                if let idx = Int(key) {
                    result[idx] = binding
                }
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
            profiles[trimmed] = Profile(buttons: [:], hardwareBindings: nil, hypershiftMappings: nil)
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
            ButtonMapper.shared.updateHypershiftMapping(hypershiftMappingForCurrentProfile())
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
            ButtonMapper.shared.updateHypershiftMapping(hypershiftMappingForCurrentProfile())
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
        case "hypershift":
            let hsMode: HypershiftMode = (action.mode == "toggle") ? .toggle : .hold
            return .hypershift(mode: hsMode)
        case "mediaKey":
            if let mkRaw = action.mediaKey, let mk = MediaKeyType(rawValue: mkRaw) {
                return .mediaKey(key: mk, description: action.description)
            }
            return nil
        default:
            return nil
        }
    }

    private func toButtonAction(_ action: ActionType) -> ButtonAction {
        switch action {
        case .keySequence(let keys, let description):
            return ButtonAction(type: "keySequence", keys: keys, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil)
        case .application(let path, let description):
            return ButtonAction(type: "application", keys: nil, description: description, path: path, command: nil, text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil)
        case .systemCommand(let command, let description):
            return ButtonAction(type: "systemCommand", keys: nil, description: description, path: nil, command: command, text: nil, steps: nil, profile: nil, mediaKey: nil, mode: nil)
        case .textSnippet(let text, let description):
            return ButtonAction(type: "textSnippet", keys: nil, description: description, path: nil, command: nil, text: text, steps: nil, profile: nil, mediaKey: nil, mode: nil)
        case .macro(let steps, let description):
            return ButtonAction(type: "macro", keys: nil, description: description, path: nil, command: nil, text: nil, steps: steps, profile: nil, mediaKey: nil, mode: nil)
        case .profileSwitch(let profile, let description):
            return ButtonAction(type: "profileSwitch", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: profile, mediaKey: nil, mode: nil)
        case .hypershift(let mode):
            return ButtonAction(type: "hypershift", keys: nil, description: "Hypershift Modifier", path: nil, command: nil, text: nil, steps: nil, profile: nil, mediaKey: nil, mode: mode.rawValue)
        case .mediaKey(let key, let description):
            return ButtonAction(type: "mediaKey", keys: nil, description: description, path: nil, command: nil, text: nil, steps: nil, profile: nil, mediaKey: key.rawValue, mode: nil)
        }
    }

    // Update a single button's action in the current profile and refresh mapping
    func setAction(forButton index: Int, action: ActionType?) {
        var profile = profiles[currentProfileName] ?? Profile(buttons: [:], hardwareBindings: nil, hypershiftMappings: nil)
        let key = String(index)
        if let action = action {
            profile.buttons[key] = toButtonAction(action)
        } else {
            profile.buttons.removeValue(forKey: key)
        }
        profiles[currentProfileName] = profile
        ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
        saveUserProfiles()
    }

    func setHypershiftAction(forButton index: Int, action: ActionType?) {
        var profile = profiles[currentProfileName] ?? Profile(buttons: [:], hardwareBindings: nil, hypershiftMappings: nil)
        let key = String(index)
        if profile.hypershiftMappings == nil { profile.hypershiftMappings = [:] }
        
        if let action = action {
            profile.hypershiftMappings?[key] = toButtonAction(action)
        } else {
            profile.hypershiftMappings?.removeValue(forKey: key)
        }
        profiles[currentProfileName] = profile
        ButtonMapper.shared.updateHypershiftMapping(hypershiftMappingForCurrentProfile())
        saveUserProfiles()
    }

    /// Atomic update for both Standard and Hypershift layers to prevent race conditions or partial saves.
    func setBothActions(forButton index: Int, standard: ActionType?, hypershift: ActionType?) {
        var profile = profiles[currentProfileName] ?? Profile(buttons: [:], hardwareBindings: nil, hypershiftMappings: nil)
        let key = String(index)
        
        // Update Standard
        if let std = standard {
            profile.buttons[key] = toButtonAction(std)
        } else {
            profile.buttons.removeValue(forKey: key)
        }
        
        // Update Hypershift
        if profile.hypershiftMappings == nil { profile.hypershiftMappings = [:] }
        if let hs = hypershift {
            profile.hypershiftMappings?[key] = toButtonAction(hs)
        } else {
            profile.hypershiftMappings?.removeValue(forKey: key)
        }
        
        // Persist once
        profiles[currentProfileName] = profile
        
        // Sync both mappings to runtime
        ButtonMapper.shared.updateMapping(mappingForCurrentProfile())
        ButtonMapper.shared.updateHypershiftMapping(hypershiftMappingForCurrentProfile())
        
        saveUserProfiles()
        NSLog("[Config] Atomically updated standard and hypershift actions for button \(index)")
    }

    func setHardwareBinding(forButton index: Int, binding: HardwareBinding?) {
        var profile = profiles[currentProfileName] ?? Profile(buttons: [:], hardwareBindings: nil, hypershiftMappings: nil)
        let key = String(index)
        if profile.hardwareBindings == nil { profile.hardwareBindings = [:] }
        
        if let binding = binding {
            profile.hardwareBindings?[key] = binding
        } else {
            profile.hardwareBindings?.removeValue(forKey: key)
        }
        profiles[currentProfileName] = profile
        NotificationCenter.default.post(name: ConfigManager.didUpdateHardwareBindingsNotification, object: nil)
        saveUserProfiles() // Ensure it's saved to disk
    }

    func getHardwareBinding(forUsage usage: UInt32, usagePage: UInt32, cookie: UInt32? = nil, value: Int32? = nil) -> HardwareBinding? {
        guard let bindings = profiles[currentProfileName]?.hardwareBindings else { return nil }
        
        // 1. Try exact match (Usage, Page, Cookie, and Value if provided)
        for (_, binding) in bindings {
            if binding.usage == usage && binding.usagePage == usagePage {
                let cookieMatches = (binding.cookie == nil || cookie == nil || binding.cookie == cookie)
                let valueMatches = (binding.value == nil || value == nil || binding.value == value)
                
                if cookieMatches && valueMatches {
                    // Favor bindings that match the specific value if multiple exist
                    if binding.value == value {
                        return binding
                    }
                }
            }
        }
        
        // 2. Fallback: Match Usage/Page/Cookie if no value-specific binding found
        for (_, binding) in bindings {
            if binding.usage == usage && binding.usagePage == usagePage {
                let cookieMatches = (binding.cookie == nil || cookie == nil || binding.cookie == cookie)
                if cookieMatches && binding.value == nil {
                    return binding
                }
            }
        }

        // 3. Ultra-fallback: Match Usage/Page ONLY if there's exactly one binding for this usage/page
        let candidates = bindings.values.filter { $0.usage == usage && $0.usagePage == usagePage }
        if candidates.count == 1 {
            NSLog("[Config] Ultra-fallback match for usage=0x\(String(usage, radix: 16)) pg=0x\(String(usagePage, radix: 16))")
            return candidates[0]
        }
        
        return nil
    }

    func getButtonIndex(forHardwareBinding binding: HardwareBinding) -> Int? {
        guard let bindings = profiles[currentProfileName]?.hardwareBindings else { return nil }
        for (key, b) in bindings {
            if b.usage == binding.usage && b.usagePage == binding.usagePage && b.cookie == binding.cookie && b.value == binding.value {
                return Int(key)
            }
        }
        return nil
    }

    static let didUpdateHardwareBindingsNotification = Notification.Name("ConfigManager.didUpdateHardwareBindings")

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
