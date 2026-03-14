import Foundation

struct AirMessage: Identifiable, Codable {
    let id: UUID
    let sender: String
    let text: String
    let timestamp: Date
    let isMe: Bool
}
