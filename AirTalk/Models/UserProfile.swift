import Foundation

struct UserProfile: Codable {
    var name: String
    var status: String
    var iconID: String

    var asDiscoveryInfo: [String: String] {
        ["name": name, "status": status, "iconID": iconID]
    }

    static func from(discoveryInfo: [String: String]) -> UserProfile? {
        guard let name = discoveryInfo["name"],
              let status = discoveryInfo["status"],
              let iconID = discoveryInfo["iconID"] else { return nil }
        return UserProfile(name: name, status: status, iconID: iconID)
    }

    // MARK: - UserDefaults persistence

    private static let key = "userProfile"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func load() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return nil }
        return profile
    }
}
