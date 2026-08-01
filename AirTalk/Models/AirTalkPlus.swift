import Foundation
import SwiftUI

enum AirTalkPlus {
    static let monthlyProductID = "com.yuuki.AirTalk.plus.monthly"
    static let yearlyProductID = "com.yuuki.AirTalk.plus.yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    static let freeThemes: [ThemeColor] = [.purple, .blue, .green]
    static let premiumThemes: [ThemeColor] = [.orange, .pink, .black, .white, .teal, .indigo, .mint]

    static let freeReactions = ["❤️", "👍", "😂"]
    static let premiumReactions = ["😮", "😢", "👏", "🔥", "✨", "🙌", "☕️", "🎧"]
    static let allReactions = freeReactions + premiumReactions

    static let icebreakers = [
        "こんにちは！近くにいたので話しかけてみました",
        "このあたりでおすすめのお店ありますか？",
        "同じイベントに参加していますか？",
        "少しだけ話しませんか？",
        "AirTalkでつながるの不思議ですね"
    ]

    static func isPremiumTheme(_ theme: ThemeColor) -> Bool {
        premiumThemes.contains(theme)
    }
}

enum ProfileFrame: String, CaseIterable, Identifiable, Codable {
    case none
    case aurora
    case pulse
    case host

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "なし"
        case .aurora:
            return "Aurora"
        case .pulse:
            return "Pulse"
        case .host:
            return "Host"
        }
    }

    var color: Color {
        switch self {
        case .none:
            return .clear
        case .aurora:
            return .cyan
        case .pulse:
            return .pink
        case .host:
            return .yellow
        }
    }
}

struct ProfilePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var status: String
    var iconID: String
    var themeColor: String
    var imageData: Data?
    var isHostBadgeEnabled: Bool
    var profileFrameID: String
    var createdAt: Date

    init(profile: UserProfile) {
        id = UUID()
        name = profile.name
        status = profile.status
        iconID = profile.iconID
        themeColor = profile.themeColor
        imageData = profile.imageData
        isHostBadgeEnabled = profile.isHostBadgeEnabled
        profileFrameID = profile.profileFrameID
        createdAt = Date()
    }

    var profile: UserProfile {
        UserProfile(
            name: name,
            status: status,
            iconID: iconID,
            themeColor: themeColor,
            imageData: imageData,
            isHostBadgeEnabled: isHostBadgeEnabled,
            profileFrameID: profileFrameID
        )
    }
}

enum ProfilePresetStore {
    private static let key = "profilePresets"
    static let maxPresets = 6

    static func load() -> [ProfilePreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([ProfilePreset].self, from: data) else {
            return []
        }
        return presets.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ presets: [ProfilePreset]) {
        let trimmed = Array(presets.sorted { $0.createdAt > $1.createdAt }.prefix(maxPresets))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func deleteAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
