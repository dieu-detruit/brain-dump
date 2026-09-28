import XCTest
@testable import BrainDumpWatch

final class ThreadMutationTests: XCTestCase {
    func testWaitingAndIdleAreExplicitNullsAndCompletionDoesNotSendDelegation() throws {
        let thread = BrainThread(id: "t", title: "作業", delegation: nil, priority: 1)
        for action in ["delegate", "complete"] {
            let command = ThreadMutation(operationID: "op", action: action, thread: thread, expected: nil, delegation: nil)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
            XCTAssertTrue(json["expected"] is NSNull)
            let previous = try XCTUnwrap(json["expected_thread"] as? [String: Any])
            XCTAssertTrue(previous["delegation"] is NSNull)
            if action == "delegate" { XCTAssertTrue(json["delegation"] is NSNull) }
            else { XCTAssertNil(json["delegation"]) }
        }
    }
}
