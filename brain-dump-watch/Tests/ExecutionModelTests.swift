import XCTest
@testable import BrainDumpWatch
@MainActor final class ExecutionModelTests: XCTestCase {
    func testFailedConfirmationNeverLooksSuccessful() async {
        let api = FakeAPI()
        let store = MemoryStore(WatchCredentials(pairingSecret: "s", deviceToken: "t", deviceID: "d"))
        let model = ExecutionModel(api: api, store: store, requestNotifications: { false })
        await model.refresh()
        await model.confirm()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.isStale)
        XCTAssertFalse(model.isSending)
        XCTAssertNil(model.notice)
    }
    func testExpiredDisplayCodeDoesNotDiscardApprovedPairing() async {
        let api = FakeAPI()
        let store = MemoryStore(WatchCredentials(pairingSecret: "original-secret", deviceToken: "original-token", pairingID: "p", code: "12345678", expiresAt: "2020-01-01T00:00:00Z"))
        let model = ExecutionModel(api: api, store: store, requestNotifications: { false })
        await model.refresh()
        XCTAssertEqual(model.credentials?.deviceID, "approved-device")
        XCTAssertEqual(model.credentials?.deviceToken, "original-token")
    }
    func testRegistrationIsRetriedWhenReturningToApp() async {
        var attempts = 0
        let model = ExecutionModel(api: FakeAPI(), store: MemoryStore(WatchCredentials(pairingSecret: "s", deviceToken: "t", deviceID: "d")), requestNotifications: { attempts += 1; return false })
        await model.refresh()
        model.becameActive()
        await model.refresh()
        XCTAssertEqual(attempts, 2)
    }
}
private final class MemoryStore: CredentialStorage {
    var value: WatchCredentials?
    init(_ value: WatchCredentials?) { self.value = value }
    func load() throws -> WatchCredentials? { value }
    func save(_ value: WatchCredentials) throws { self.value = value }
    func clear() throws { value = nil }
    func clear(ifTokenMatches token: String) throws -> Bool {
        guard value?.deviceToken == token else { return false }; value = nil; return true
    }
}
private final class FakeAPI: WatchAPI {
    func snapshot(token: String) async throws -> Snapshot {
        Snapshot(serverTime: "2026-09-24T00:00:00Z", threads: [BrainThread(id: "t", title: "作業", delegation: nil, priority: 1)], active: ActiveExecution(sessionID: "1", confirmationRevision: "r", threadID: "t", lastConfirmedAt: "2026-09-24T00:00:00Z", deadline: "2026-09-24T01:00:00Z"))
    }
    func apply(_ command: Mutation, token: String) async throws -> MutationResult { throw APIError.unavailable }
    func startPairing(_ credentials: WatchCredentials) async throws -> PairingReply { throw APIError.unavailable }
    func pairingStatus(_ credentials: WatchCredentials) async throws -> PairingStatus { PairingStatus(status: "approved", deviceID: "approved-device") }
    func registerPush(_ pushToken: String, token: String) async throws {}
}
