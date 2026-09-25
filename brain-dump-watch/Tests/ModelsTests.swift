import XCTest
@testable import BrainDumpWatch
final class ModelsTests: XCTestCase {
    func testConfirmationAppearsOnlyDuringResponseWindow() {
        let active = ActiveExecution(sessionID: "1", confirmationRevision: "r", threadID: "t", lastConfirmedAt: "2026-09-25T00:00:00Z", deadline: "2026-09-25T01:00:00Z")
        for (time, expected) in [("00:00:00", false), ("00:54:59", false), ("00:55:00", true), ("00:59:59.999", true), ("01:00:00", false)] {
            XCTAssertEqual(Snapshot(serverTime: "2026-09-25T\(time)Z", threads: [], active: active).needsConfirmation, expected, time)
        }
        XCTAssertFalse(Snapshot(serverTime: "2026-09-25T00:56:00Z", threads: [], active: nil).needsConfirmation)
        let renewed = ActiveExecution(sessionID: "1", confirmationRevision: "new", threadID: "t", lastConfirmedAt: "2026-09-25T00:56:00Z", deadline: "2026-09-25T01:56:00Z")
        XCTAssertFalse(Snapshot(serverTime: "2026-09-25T00:56:00Z", threads: [], active: renewed).needsConfirmation)
    }
    func testGroupsFollowWebDelegationAndPriority() {
        let snapshot = Snapshot(serverTime: "", threads: [
            BrainThread(id: "ai", title: "AI", delegation: "ai", priority: 3),
            BrainThread(id: "waiting", title: "待機", delegation: nil, priority: 4),
            BrainThread(id: "colleague", title: "他の人", delegation: "colleague", priority: 1),
            BrainThread(id: "current", title: "実行中", delegation: nil, priority: 2),
        ], active: ActiveExecution(sessionID: "1", confirmationRevision: "r", threadID: "current", lastConfirmedAt: "", deadline: ""))
        XCTAssertEqual(snapshot.waitingThreads.map(\.id), ["current", "waiting"])
        XCTAssertEqual(snapshot.delegatedThreads.map(\.id), ["colleague", "ai"])
    }
    func testLargeSessionID() throws {
        let data = Data(#"{"session_id":"9007199254740993","confirmation_revision":"d9b421e8-9a1a-4b6a-8b69-42a138652f34","thread_id":"x","last_confirmed_at":"2026-09-24T00:00:00Z","deadline":"2026-09-24T01:00:00Z"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ActiveExecution.self, from: data).sessionID, "9007199254740993")
    }
}
