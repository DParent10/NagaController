import Foundation

/// Checks GitHub's releases API for a newer tagged release than the running build, at
/// most once a day. No auto-download and no auto-install — just enough visibility that
/// "am I on the latest version?" stops requiring a manual trip to GitHub.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let didFindUpdateNotification = Notification.Name("UpdateChecker.didFindUpdate")
    static let releasesPageURL = URL(string: "https://github.com/DParent10/NagaController/releases/latest")!

    private(set) var availableVersion: String?
    private let lastCheckKey = "NagaController.lastUpdateCheckDate"
    private let apiURL = URL(string: "https://api.github.com/repos/DParent10/NagaController/releases/latest")!

    private init() {}

    func checkIfNeeded() {
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 86_400 {
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            guard UpdateChecker.isNewer(latest, than: current) else { return }
            DispatchQueue.main.async {
                self.availableVersion = latest
                NotificationCenter.default.post(name: UpdateChecker.didFindUpdateNotification, object: latest)
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let x = i < aParts.count ? aParts[i] : 0
            let y = i < bParts.count ? bParts[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
