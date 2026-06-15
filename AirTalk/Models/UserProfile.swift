import Foundation

struct UserProfile: Codable {
    var name: String
    var status: String
    var iconID: String
    var themeColor: String
    var imageData: Data?

    // 注意: MCNearbyServiceAdvertiser の discoveryInfo は辞書全体で約400バイト未満という
    // 制限がある（Bonjour TXT レコードとして配信されるため）。
    // 画像のような大きなデータは含められない（含めると初期化時にクラッシュする）。
    // プロフィール画像は接続確立後に MCSession 経由で送る想定。
    var asDiscoveryInfo: [String: String] {
        ["name": name, "status": status, "iconID": iconID, "themeColor": themeColor]
    }

    static func from(discoveryInfo: [String: String]) -> UserProfile? {
        guard let name = discoveryInfo["name"],
              let status = discoveryInfo["status"],
              let iconID = discoveryInfo["iconID"] else { return nil }
              
        let themeColor = discoveryInfo["themeColor"] ?? "purple"
        var data: Data? = nil
        if let base64String = discoveryInfo["img"] {
            data = Data(base64Encoded: base64String)
        }
              
        return UserProfile(name: name, status: status, iconID: iconID, themeColor: themeColor, imageData: data)
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

    static func delete() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
