import Foundation

struct AirMessage: Identifiable, Codable {
    let id: UUID
    let sender: String
    let text: String
    let timestamp: Date
    let isMe: Bool
    var reaction: String?
}

struct ReactionEvent: Codable {
    let messageID: UUID
    let reaction: String
}

/// P2P でやり取りする全データの型安全なエンベロープ。
/// デコード順に依存した判定をやめ、明示的なケースで分岐する。
enum NetworkPacket: Codable {
    case message(AirMessage)
    case reaction(ReactionEvent)
    case profile(UserProfile)
}

extension AirMessage {
    /// 入力可能なメッセージの最大文字数。極端に長い本文の送信を防ぐ。
    static let maxTextLength = 1000
    /// 1チャットでメモリ上に保持する最大件数。切断時には従来通り全件破棄する。
    static let maxHistoryCount = 200
    /// 不正または巨大なP2Pパケットによるメモリ負荷を防ぐ上限。
    static let maxPacketBytes = 64 * 1024
}
