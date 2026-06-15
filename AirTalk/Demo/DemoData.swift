import Foundation
import MultipeerConnectivity

/// App Store のスクリーンショット／プレビュー撮影用のデモデータ。
///
/// AirTalk は MultipeerConnectivity を使う P2P アプリのため、本来は実機2台がないと
/// レーダーにピアが並んだ状態やチャット画面を再現できない。シミュレータでも見栄えの良い
/// スクショを撮れるよう、ここに定義した架空のプロフィール・会話を注入する。
///
/// 本番ビルドの挙動には一切影響しない（`DemoMode.isEnabled` が true のときだけ使われる）。
enum DemoData {

    // MARK: - 自分のプロフィール

    static let myProfile = UserProfile(
        name: "Yuki",
        status: "新しい出会いを探し中 ✨",
        iconID: "bolt.fill",
        themeColor: "purple",
        imageData: nil
    )

    // MARK: - 周囲で発見されるピア（レーダー画面）

    /// レーダーに並べる架空のユーザーたち。アイコン・テーマ・ひとことに変化を持たせて
    /// 賑わっている雰囲気を出す。
    static let discoveredProfiles: [UserProfile] = [
        UserProfile(name: "Aoi",   status: "カフェで作業中 ☕️",      iconID: "moon.fill",     themeColor: "blue",   imageData: nil),
        UserProfile(name: "Haru",  status: "音楽の話しよう 🎧",       iconID: "music.note",    themeColor: "green",  imageData: nil),
        UserProfile(name: "Mina",  status: "はじめまして！",          iconID: "heart.fill",    themeColor: "pink",   imageData: nil),
        UserProfile(name: "Ren",   status: "ランチ仲間募集中 🍜",     iconID: "flame.fill",    themeColor: "orange", imageData: nil),
        UserProfile(name: "Sora",  status: "ひとやすみ 🌙",           iconID: "star.fill",     themeColor: "purple", imageData: nil),
    ]

    /// 発見されたピア（MCPeerID + プロフィール）の一覧。
    static func discoveredPeers() -> [DiscoveredPeer] {
        discoveredProfiles.map { profile in
            DiscoveredPeer(peerID: MCPeerID(displayName: profile.name), profile: profile)
        }
    }

    // MARK: - チャット画面の会話

    /// チャット相手（レーダーの先頭ピアと一致させる）。
    static let chatPartner = discoveredProfiles[0]

    /// チャットリクエストを送ってくる相手の名前（着信シーン用）。
    static let inviterName = "Mina"

    /// チャット画面に表示する会話。`isMe` と `reaction` を散りばめて自然な往復に見せる。
    static func chatMessages(partnerName: String) -> [AirMessage] {
        let now = Date()
        func at(_ minutesAgo: Int) -> Date { now.addingTimeInterval(TimeInterval(-minutesAgo * 60)) }

        return [
            AirMessage(id: UUID(), sender: partnerName, text: "こんにちは！近くにいたので話しかけてみました 👋", timestamp: at(8),  isMe: false, reaction: nil),
            AirMessage(id: UUID(), sender: "Yuki",      text: "わ、はじめまして！同じカフェですか？",          timestamp: at(7),  isMe: true,  reaction: "❤️"),
            AirMessage(id: UUID(), sender: partnerName, text: "そうです、窓際の席です ☕️",                   timestamp: at(6),  isMe: false, reaction: nil),
            AirMessage(id: UUID(), sender: "Yuki",      text: "AirTalk、ネット無しで繋がるの不思議ですね",     timestamp: at(5),  isMe: true,  reaction: nil),
            AirMessage(id: UUID(), sender: partnerName, text: "離れると会話が消えるのが逆に良いよね 🌫️",       timestamp: at(3),  isMe: false, reaction: "👍"),
            AirMessage(id: UUID(), sender: "Yuki",      text: "まさに一期一会！この後おすすめのお店あります？", timestamp: at(2),  isMe: true,  reaction: nil),
            AirMessage(id: UUID(), sender: partnerName, text: "向かいのベーカリー超おすすめです 🥐",          timestamp: at(1),  isMe: false, reaction: nil),
        ]
    }
}
