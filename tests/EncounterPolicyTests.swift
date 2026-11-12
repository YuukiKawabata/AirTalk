import Foundation

@main
struct EncounterPolicyTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = UUID()
        precondition(EncounterPolicy.token(from: EncounterPolicy.packet(for: token)) == token)
        precondition(EncounterPolicy.token(from: Data()) == nil)
        precondition(EncounterPolicy.token(from: Data([2]) + EncounterPolicy.packet(for: token).dropFirst()) == nil)
        precondition(EncounterPolicy.token(from: EncounterPolicy.packet(for: token) + Data([0])) == nil)
        let first = EncounterPolicy.recording(token, in: [], now: now)
        let duplicate = EncounterPolicy.recording(token, in: first, now: now.addingTimeInterval(30))
        precondition(duplicate.count == 1 && duplicate[0].firstSeen == now && duplicate[0].lastSeen == now.addingTimeInterval(30))
        // Repeated sightings must not extend the original retention deadline.
        precondition(EncounterPolicy.pruned(duplicate, now: now.addingTimeInterval(EncounterPolicy.retention)).isEmpty)
        precondition(EncounterPolicy.pruned(first, now: now.addingTimeInterval(-1)).isEmpty)
        let many = (0..<300).map { EncounterRecord(id: UUID(), firstSeen: now.addingTimeInterval(Double(-$0)), lastSeen: now) }
        let bounded = EncounterPolicy.pruned(many, now: now)
        precondition(bounded.count == 200 && bounded.last?.firstSeen == now.addingTimeInterval(-199))
        let encoded = try! JSONEncoder().encode(duplicate)
        let decoded = try! JSONDecoder().decode([EncounterRecord].self, from: encoded)
        precondition(decoded == duplicate)
        print("EncounterPolicy: packet validation, deduplication, expiry, clock rollback, capacity and persistence passed")
    }
}
