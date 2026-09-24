import XCTest
@testable import BrainDumpWatch
final class ModelsTests: XCTestCase {
    func testLargeSessionID() throws {
        let data = Data(#"{"session_id":"9007199254740993","confirmation_revision":"d9b421e8-9a1a-4b6a-8b69-42a138652f34","thread_id":"x","last_confirmed_at":"2026-09-24T00:00:00Z","deadline":"2026-09-24T01:00:00Z"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ActiveExecution.self, from: data).sessionID, "9007199254740993")
    }
}
