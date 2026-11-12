import Foundation

/// Prototype-only, local observations. No profile, location, message, or stable device ID.
struct EncounterRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let firstSeen: Date
    var lastSeen: Date
}

enum EncounterPolicy {
    static let retention: TimeInterval = 24 * 60 * 60
    static let tokenLifetime: TimeInterval = 15 * 60
    static let maxRecords = 200

    static func pruned(_ records: [EncounterRecord], now: Date) -> [EncounterRecord] {
        records.filter { $0.firstSeen <= now && now.timeIntervalSince($0.firstSeen) < retention }
            .sorted { $0.firstSeen > $1.firstSeen }.prefix(maxRecords).map { $0 }
    }

    static func recording(_ token: UUID, in records: [EncounterRecord], now: Date) -> [EncounterRecord] {
        var result = pruned(records, now: now)
        if let index = result.firstIndex(where: { $0.id == token }) {
            result[index].lastSeen = now
        } else {
            result.insert(EncounterRecord(id: token, firstSeen: now, lastSeen: now), at: 0)
        }
        return Array(result.prefix(maxRecords))
    }

    // Version byte + 16 UUID bytes. No text or arbitrary payload is accepted.
    static func packet(for token: UUID) -> Data {
        var bytes = token.uuid
        return Data([1]) + withUnsafeBytes(of: &bytes) { Data($0) }
    }

    static func token(from data: Data) -> UUID? {
        guard data.count == 17, data.first == 1 else { return nil }
        let b = Array(data.dropFirst())
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
