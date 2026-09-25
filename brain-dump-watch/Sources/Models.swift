import Foundation
struct BrainThread: Codable, Identifiable {
    let id: String
    let title: String
    let delegation: String?
    let priority: Double
}
struct ExpectedExecution: Codable, Equatable {
    let sessionID: String
    let confirmationRevision: String
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", confirmationRevision = "confirmation_revision"
    }
}
struct ActiveExecution: Codable {
    let sessionID: String
    let confirmationRevision: String
    let threadID: String
    let lastConfirmedAt: String
    let deadline: String
    var expected: ExpectedExecution { .init(sessionID: sessionID, confirmationRevision: confirmationRevision) }
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", confirmationRevision = "confirmation_revision"
        case threadID = "thread_id", lastConfirmedAt = "last_confirmed_at", deadline
    }
}
struct Snapshot: Codable {
    let serverTime: String
    let threads: [BrainThread]
    let active: ActiveExecution?
    var needsConfirmation: Bool {
        func date(_ value: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
        guard let active, let now = date(serverTime),
              let confirmed = date(active.lastConfirmedAt), let deadline = date(active.deadline) else { return false }
        return now.timeIntervalSince(confirmed) >= 55 * 60 && now < deadline
    }
    var waitingThreads: [BrainThread] { threads.filter { $0.delegation == nil }.sorted { $0.priority < $1.priority } }
    var delegatedThreads: [BrainThread] { threads.filter { $0.delegation != nil }.sorted { $0.priority < $1.priority } }
    enum CodingKeys: String, CodingKey { case serverTime = "server_time", threads, active }
}
struct Mutation: Encodable {
    let operationID: String
    let action: String
    let expected: ExpectedExecution?
    let targetThreadID: String?
    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id", action, expected, targetThreadID = "target_thread_id"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(operationID, forKey: .operationID)
        try c.encode(action, forKey: .action)
        try c.encode(expected, forKey: .expected)
        if action == "switch" { try c.encode(targetThreadID, forKey: .targetThreadID) }
    }
}
struct MutationResult: Decodable { let status: String; let snapshot: Snapshot }
