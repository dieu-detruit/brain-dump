import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized, unavailable, invalidResponse, invalidNotification, credentials, configuration, rateLimited
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登録が解除されています。Web版で登録し直してください。"
        case .credentials: return "Watchをロック解除して、もう一度お試しください。"
        case .configuration: return "接続先が設定されていません。ビルド設定を確認してください。"
        case .rateLimited: return "しばらく待ってからお試しください。"
        case .invalidNotification: return "この通知からは回答できません。アプリで状態を確認してください。"
        case .invalidResponse, .unavailable: return "接続できませんでした。状態を更新してからお試しください。"
        }
    }
}
struct PairingReply: Decodable {
    let pairingID: String; let code: String; let expiresAt: String
    enum CodingKeys: String, CodingKey { case pairingID = "pairing_id", code, expiresAt = "expires_at" }
}
struct PairingStatus: Decodable {
    let status: String; let deviceID: String?
    enum CodingKeys: String, CodingKey { case status, deviceID = "device_id" }
}
struct StatusReply: Decodable { let status: String }

protocol WatchAPI {
    func snapshot(token: String) async throws -> Snapshot
    func apply(_ command: Mutation, token: String) async throws -> MutationResult
    func startPairing(_ credentials: WatchCredentials) async throws -> PairingReply
    func pairingStatus(_ credentials: WatchCredentials) async throws -> PairingStatus
    func registerPush(_ pushToken: String, token: String) async throws
}

final class APIClient: WatchAPI {
    private let baseURL: URL?
    private let session: URLSession
    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? (Bundle.main.object(forInfoDictionaryKey: "WatchAPIURL") as? String).flatMap(URL.init(string:))
        self.session = session
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil, data: Data? = nil, conflict: Bool = false) async throws -> T {
        guard let baseURL, baseURL.scheme == "https", baseURL.host != nil else { throw APIError.configuration }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = data
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if response.statusCode == 401 { throw APIError.unauthorized }
        if response.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(response.statusCode) || (conflict && response.statusCode == 409) else { throw APIError.unavailable }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
    func snapshot(token: String) async throws -> Snapshot { try await request("state", token: token) }
    func apply(_ command: Mutation, token: String) async throws -> MutationResult {
        try await request("execution", method: "POST", token: token, data: JSONEncoder().encode(command), conflict: true)
    }
    func startPairing(_ credentials: WatchCredentials) async throws -> PairingReply {
        try await request("pairings", method: "POST", data: JSONEncoder().encode([
            "pairing_secret": credentials.pairingSecret, "device_token_hash": credentials.tokenHash,
        ]))
    }
    func pairingStatus(_ credentials: WatchCredentials) async throws -> PairingStatus {
        guard let id = credentials.pairingID else { throw APIError.invalidResponse }
        return try await request("pairings/status", method: "POST", data: JSONEncoder().encode([
            "pairing_id": id, "pairing_secret": credentials.pairingSecret,
        ]))
    }
    func registerPush(_ pushToken: String, token: String) async throws {
        let environment = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String
        let _: StatusReply = try await request("push-token", method: "PUT", token: token, data: JSONEncoder().encode([
            "token": pushToken, "environment": environment == "production" ? "production" : "sandbox",
        ]))
    }
}
