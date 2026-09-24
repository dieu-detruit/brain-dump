import XCTest
@testable import BrainDumpWatch
final class CredentialStoreTests: XCTestCase {
    func testLateUnauthorizedResponseCannotEraseNewCredentials() throws {
        let store = CredentialStore(service: "BrainDumpWatchTest-" + UUID().uuidString)
        defer { try? store.clear() }
        try store.save(WatchCredentials(pairingSecret: "old", deviceToken: "old-token"))
        try store.save(WatchCredentials(pairingSecret: "new", deviceToken: "new-token"))
        XCTAssertFalse(try store.clear(ifTokenMatches: "old-token"))
        XCTAssertEqual(try store.load()?.deviceToken, "new-token")
        XCTAssertTrue(try store.clear(ifTokenMatches: "new-token"))
        XCTAssertNil(try store.load())
    }
}
