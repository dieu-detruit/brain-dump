import XCTest
@testable import BrainDumpWatch
final class NotificationHandlerTests: XCTestCase {
    func testNotificationKeepsOriginalSessionAndOperation() throws {
        let command = try NotificationHandler.command(from: [
            "session_id": "9007199254740993",
            "confirmation_revision": "11111111-1111-4111-8111-111111111111",
            "operation_id": "22222222-2222-4222-8222-222222222222"
        ])
        XCTAssertEqual(command.expected?.sessionID, "9007199254740993")
        XCTAssertEqual(command.operationID, "22222222-2222-4222-8222-222222222222")
    }
    func testMalformedNotificationCannotConfirmCurrentThread() {
        XCTAssertThrowsError(try NotificationHandler.command(from: ["session_id": "1"]))
    }
}
