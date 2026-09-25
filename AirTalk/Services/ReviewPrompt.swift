import Foundation

/// 「会話が成立した直後」にだけ App Store レビューを依頼するための判定。
///
/// メッセージ本文は一切保存しない。UserDefaults に残すのは、成立した会話の回数と
/// 最後に依頼したアプリバージョンだけ。
enum ReviewPrompt {
    /// 自分・相手それぞれがこの件数以上送った会話を「成立した会話」とみなす。
    static let minMessagesEachSide = 2

    private static let goodConversationCountKey = "reviewPrompt.goodConversationCount"
    private static let lastRequestedVersionKey = "reviewPrompt.lastRequestedVersion"

    static func isGoodConversation(_ messages: [AirMessage]) -> Bool {
        let sent = messages.filter(\.isMe).count
        let received = messages.count - sent
        return sent >= minMessagesEachSide && received >= minMessagesEachSide
    }

    /// 成立した会話を記録し、今回レビューを依頼すべきなら true を返す。
    /// 依頼は1バージョンにつき1回まで（実際の表示回数は OS がさらに制限する）。
    static func recordGoodConversation() -> Bool {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: goodConversationCountKey) + 1
        defaults.set(count, forKey: goodConversationCountKey)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard defaults.string(forKey: lastRequestedVersionKey) != version else { return false }
        defaults.set(version, forKey: lastRequestedVersionKey)
        return true
    }
}
