#if DEBUG
import Foundation

/// In-memory product prototype. No accounts, BLE identifiers or network operations.
struct OnlinePreviewPerson: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let topic: String
    let introduction: String
    let expiresAt: Date
}

enum PreviewRelationship: Equatable {
    case encountered, outgoing, incoming, accepted, declined, connected, blocked
}

struct PreviewConversationMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isMe: Bool
}

struct OnlinePreviewState {
    var optedIn = false
    private(set) var relationships: [String: PreviewRelationship] = [:]
    private(set) var activePeer: String?
    private(set) var messages: [PreviewConversationMessage] = []
    private(set) var myReconnect: Set<String> = []
    private(set) var peerReconnect: Set<String> = []
    private(set) var connections: Set<String> = []
    private(set) var reported: Set<String> = []
    let people: [OnlinePreviewPerson]

    init(now: Date = Date()) {
        people = [
            .init(id: "demo-aoi", name: "Aoi", symbol: "leaf.fill", topic: "カフェ・旅行", introduction: "最近見つけた、お気に入りの場所を話したいです。", expiresAt: now.addingTimeInterval(86400)),
            .init(id: "demo-sora", name: "Sora", symbol: "headphones", topic: "音楽・映画", introduction: "最近よかった映画や曲を教えてください。", expiresAt: now.addingTimeInterval(86400)),
            .init(id: "demo-ren", name: "Ren", symbol: "book.fill", topic: "本・ものづくり", introduction: "読んでいる本や、作っているものの話をしましょう。", expiresAt: now.addingTimeInterval(86400))
        ]
        for person in people { relationships[person.id] = .encountered }
        relationships["demo-sora"] = .incoming
    }

    func relationship(_ id: String) -> PreviewRelationship? { relationships[id] }

    private func available(_ id: String, now: Date) -> Bool {
        guard optedIn, relationships[id] != .blocked, let person = people.first(where: { $0.id == id }) else { return false }
        return connections.contains(id) || person.expiresAt > now
    }

    @discardableResult mutating func request(_ id: String, now: Date = Date()) -> Bool {
        guard available(id, now: now), (relationships[id] == .encountered || relationships[id] == .connected) else { return false }
        relationships[id] = .outgoing
        return true
    }

    @discardableResult mutating func accept(_ id: String, now: Date = Date()) -> Bool {
        guard available(id, now: now), relationships[id] == .incoming else { return false }
        relationships[id] = .accepted
        return true
    }

    /// Explicit demo control, never an automatic or production acceptance path.
    @discardableResult mutating func simulatePeerAcceptance(_ id: String, now: Date = Date()) -> Bool {
        guard available(id, now: now), relationships[id] == .outgoing else { return false }
        relationships[id] = .accepted
        return true
    }

    mutating func decline(_ id: String) {
        guard relationships[id] == .incoming else { return }
        relationships[id] = .declined
    }

    @discardableResult mutating func startChat(_ id: String, now: Date = Date()) -> Bool {
        guard available(id, now: now), activePeer == nil,
              relationships[id] == .accepted else { return false }
        activePeer = id
        messages = []
        return true
    }

    @discardableResult mutating func send(_ text: String, isMe: Bool = true) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard optedIn, activePeer != nil, !trimmed.isEmpty, trimmed.count <= 1000, trimmed.utf8.count <= 4000 else { return false }
        messages.append(.init(text: trimmed, isMe: isMe))
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
        return true
    }

    mutating func wantReconnect(_ id: String, fromPeer: Bool = false) {
        guard optedIn, activePeer == id, relationships[id] != .blocked else { return }
        if fromPeer { peerReconnect.insert(id) } else { myReconnect.insert(id) }
        if myReconnect.contains(id) && peerReconnect.contains(id) { connections.insert(id) }
    }

    mutating func endChat() {
        if let id = activePeer, relationships[id] != .blocked {
            relationships[id] = connections.contains(id) ? .connected : .declined
            myReconnect.remove(id)
            peerReconnect.remove(id)
        }
        messages.removeAll()
        activePeer = nil
    }

    mutating func block(_ id: String) {
        guard relationships[id] != nil else { return }
        relationships[id] = .blocked
        connections.remove(id)
        myReconnect.remove(id)
        peerReconnect.remove(id)
        if activePeer == id { endChat() }
    }

    mutating func reportAndBlock(_ id: String) {
        guard relationships[id] != nil else { return }
        reported.insert(id)
        block(id)
    }

    mutating func deleteAccount() {
        endChat()
        optedIn = false
        relationships.removeAll()
        connections.removeAll()
        myReconnect.removeAll()
        peerReconnect.removeAll()
        reported.removeAll()
    }
}
#endif
