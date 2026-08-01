import Foundation

struct UserProfile: Codable {
    var name: String
    var status: String
    var iconID: String
    var themeColor: String
    var imageData: Data?
    var isHostBadgeEnabled: Bool
    var profileFrameID: String

    init(
        name: String,
        status: String,
        iconID: String,
        themeColor: String,
        imageData: Data? = nil,
        isHostBadgeEnabled: Bool = false,
        profileFrameID: String = ProfileFrame.none.rawValue
    ) {
        self.name = name
        self.status = status
        self.iconID = iconID
        self.themeColor = themeColor
        self.imageData = imageData
        self.isHostBadgeEnabled = isHostBadgeEnabled
        self.profileFrameID = profileFrameID
    }

    // 注意: MCNearbyServiceAdvertiser の discoveryInfo は辞書全体で約400バイト未満という
    // 制限がある（Bonjour TXT レコードとして配信されるため）。
    // 画像のような大きなデータは含められない（含めると初期化時にクラッシュする）。
    // プロフィール画像は接続確立後に MCSession 経由で送る想定。
    var asDiscoveryInfo: [String: String] {
        var info = ["name": name, "status": status, "iconID": iconID, "themeColor": themeColor]
        if isHostBadgeEnabled {
            info["host"] = "1"
        }
        if profileFrameID != ProfileFrame.none.rawValue {
            info["frame"] = profileFrameID
        }
        return info
    }

    static func from(discoveryInfo: [String: String]) -> UserProfile? {
        guard let name = discoveryInfo["name"],
              let status = discoveryInfo["status"],
              let iconID = discoveryInfo["iconID"] else { return nil }
              
        let themeColor = discoveryInfo["themeColor"] ?? "purple"
        let isHostBadgeEnabled = discoveryInfo["host"] == "1"
        let profileFrameID = discoveryInfo["frame"] ?? ProfileFrame.none.rawValue
        var data: Data? = nil
        if let base64String = discoveryInfo["img"] {
            data = Data(base64Encoded: base64String)
        }
              
        return UserProfile(
            name: name,
            status: status,
            iconID: iconID,
            themeColor: themeColor,
            imageData: data,
            isHostBadgeEnabled: isHostBadgeEnabled,
            profileFrameID: profileFrameID
        )
    }

    var selectedTheme: ThemeColor {
        ThemeColor(rawValue: themeColor) ?? .purple
    }

    var selectedFrame: ProfileFrame {
        ProfileFrame(rawValue: profileFrameID) ?? .none
    }

    var usesPlusFeatures: Bool {
        isHostBadgeEnabled ||
        selectedFrame != .none ||
        AirTalkPlus.isPremiumTheme(selectedTheme)
    }

    func removingPlusFeatures() -> UserProfile {
        var copy = self
        copy.isHostBadgeEnabled = false
        copy.profileFrameID = ProfileFrame.none.rawValue
        if AirTalkPlus.isPremiumTheme(copy.selectedTheme) {
            copy.themeColor = ThemeColor.purple.rawValue
        }
        return copy
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

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case iconID
        case themeColor
        case imageData
        case isHostBadgeEnabled
        case profileFrameID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(String.self, forKey: .status)
        iconID = try container.decode(String.self, forKey: .iconID)
        themeColor = try container.decodeIfPresent(String.self, forKey: .themeColor) ?? ThemeColor.purple.rawValue
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        isHostBadgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHostBadgeEnabled) ?? false
        profileFrameID = try container.decodeIfPresent(String.self, forKey: .profileFrameID) ?? ProfileFrame.none.rawValue
    }
}
