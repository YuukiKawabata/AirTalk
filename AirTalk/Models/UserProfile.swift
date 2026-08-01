import Foundation

struct UserProfile: Codable {
    static let maximumNameUTF8Bytes = 48
    static let maximumStatusUTF8Bytes = 120
    static let maximumImageBytes = 32 * 1024

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
        self.name = Self.sanitizedName(name)
        self.status = Self.sanitizedStatus(status)
        self.iconID = Self.sanitizedIdentifier(iconID, maximumUTF8Bytes: 64)
        self.themeColor = ThemeColor(rawValue: themeColor)?.rawValue ?? ThemeColor.purple.rawValue
        self.imageData = imageData.flatMap { $0.count <= Self.maximumImageBytes ? $0 : nil }
        self.isHostBadgeEnabled = isHostBadgeEnabled
        self.profileFrameID = ProfileFrame(rawValue: profileFrameID)?.rawValue ?? ProfileFrame.none.rawValue
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

    static func sanitizedName(_ value: String) -> String {
        sanitizedText(value, maximumUTF8Bytes: maximumNameUTF8Bytes)
    }

    static func sanitizedStatus(_ value: String) -> String {
        sanitizedText(value, maximumUTF8Bytes: maximumStatusUTF8Bytes)
    }

    static func limitedNameInput(_ value: String) -> String {
        utf8Prefix(value, maximumBytes: maximumNameUTF8Bytes)
    }

    static func limitedStatusInput(_ value: String) -> String {
        utf8Prefix(value, maximumBytes: maximumStatusUTF8Bytes)
    }

    func replacingName(_ value: String) -> UserProfile {
        UserProfile(
            name: value,
            status: status,
            iconID: iconID,
            themeColor: themeColor,
            imageData: imageData,
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
        name = Self.sanitizedName(try container.decode(String.self, forKey: .name))
        status = Self.sanitizedStatus(try container.decode(String.self, forKey: .status))
        iconID = Self.sanitizedIdentifier(
            try container.decode(String.self, forKey: .iconID),
            maximumUTF8Bytes: 64
        )
        let decodedTheme = try container.decodeIfPresent(String.self, forKey: .themeColor)
        themeColor = decodedTheme.flatMap(ThemeColor.init(rawValue:))?.rawValue ?? ThemeColor.purple.rawValue
        let decodedImage = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageData = decodedImage.flatMap { $0.count <= Self.maximumImageBytes ? $0 : nil }
        isHostBadgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHostBadgeEnabled) ?? false
        let decodedFrame = try container.decodeIfPresent(String.self, forKey: .profileFrameID)
        profileFrameID = decodedFrame.flatMap(ProfileFrame.init(rawValue:))?.rawValue ?? ProfileFrame.none.rawValue
    }

    private static func sanitizedIdentifier(_ value: String, maximumUTF8Bytes: Int) -> String {
        utf8Prefix(value.trimmingCharacters(in: .whitespacesAndNewlines), maximumBytes: maximumUTF8Bytes)
    }

    private static func sanitizedText(_ value: String, maximumUTF8Bytes: Int) -> String {
        let singleLine = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return utf8Prefix(singleLine, maximumBytes: maximumUTF8Bytes)
    }

    private static func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        var byteCount = 0

        for character in value {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumBytes else { break }
            result.append(character)
            byteCount += characterByteCount
        }

        return result
    }
}
