import Foundation
import Security
import CryptoKit

struct KeychainError: Error, LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { APIError.credentials.errorDescription }
}

struct WatchCredentials: Codable {
    let pairingSecret: String
    let deviceToken: String
    var pairingID: String?
    var code: String?
    var expiresAt: String?
    var deviceID: String?
    static func make() throws -> WatchCredentials {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw APIError.credentials }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return try .init(pairingSecret: random(), deviceToken: random())
    }
    var tokenHash: String { SHA256.hash(data: Data(deviceToken.utf8)).map { String(format: "%02x", $0) }.joined() }
}

protocol CredentialStorage {
    func load() throws -> WatchCredentials?
    func save(_ value: WatchCredentials) throws
    func clear() throws
    func clear(ifTokenMatches token: String) throws -> Bool
}

final class CredentialStore: CredentialStorage {
    static let shared = CredentialStore()
    private let lock = NSRecursiveLock()
    private let query: [String: Any]
    init(service: String = "BrainDumpWatch") {
        query = [kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: service, kSecAttrAccount as String: "device"]
    }
    func load() throws -> WatchCredentials? {
        lock.lock(); defer { lock.unlock() }
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(operation: "load", status: status) }
        guard let data = result as? Data else { throw APIError.credentials }
        return try JSONDecoder().decode(WatchCredentials.self, from: data)
    }
    func save(_ value: WatchCredentials) throws {
        lock.lock(); defer { lock.unlock() }
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(operation: "save", status: status) }
    }
    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(operation: "clear", status: status) }
    }
    func clear(ifTokenMatches token: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard try load()?.deviceToken == token else { return false }
        try clear()
        return true
    }
}
