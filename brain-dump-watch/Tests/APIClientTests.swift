import XCTest
@testable import BrainDumpWatch
final class APIClientTests: XCTestCase {
    func testHTTPFailureIsNotASuccess() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailureProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://test.invalid/watch-api")!, session: URLSession(configuration: config))
        do {
            _ = try await api.snapshot(token: "secret")
            XCTFail("503 was treated as success")
        } catch APIError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
private final class FailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"error\":\"unavailable\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
