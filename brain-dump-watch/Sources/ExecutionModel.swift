import Foundation
import SwiftUI
import UserNotifications
import WatchKit

@MainActor
final class ExecutionModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var credentials: WatchCredentials?
    @Published private(set) var isSending = false
    @Published private(set) var isStale = false
    @Published private(set) var loading = false
    @Published private(set) var notice: String?
    @Published var errorMessage: String?
    @Published private(set) var notificationsDenied = false
    private let api: any WatchAPI
    private let store: any CredentialStorage
    private let requestNotifications: @MainActor () async throws -> Bool
    private var generation = 0
    private var lastNotificationAttempt = Date.distantPast
    init(api: any WatchAPI = APIClient(), store: any CredentialStorage = CredentialStore.shared,
         requestNotifications: @escaping @MainActor () async throws -> Bool = ExecutionModel.requestSystemNotifications) {
        self.api = api
        self.store = store
        self.requestNotifications = requestNotifications
    }
    func becameActive() { lastNotificationAttempt = .distantPast }


    func refresh() async {
        guard !loading && !isSending else { return }
        loading = true
        defer { loading = false }
        do {
            credentials = try store.load()
            if credentials?.deviceID == nil { try await pair(); return }
            guard let token = credentials?.deviceToken else { return }
            let captured = generation
            let next = try await api.snapshot(token: token)
            guard captured == generation else { return }
            snapshot = next
            isStale = false
            errorMessage = nil
            if Date().timeIntervalSince(lastNotificationAttempt) >= 60 { await enableNotifications() }
        } catch { failure(error) }
    }
    private func pair() async throws {
        var value = try store.load() ?? WatchCredentials.make()
        // Persist both secrets before making any network request.
        try store.save(value)
        if value.pairingID == nil {
            let reply = try await api.startPairing(value)
            value.pairingID = reply.pairingID
            value.code = reply.code
            value.expiresAt = reply.expiresAt
            try store.save(value)
        }
        credentials = value
        let status = try await api.pairingStatus(value)
        if status.status == "approved", let id = status.deviceID {
            value.deviceID = id
            try store.save(value)
            credentials = value
            snapshot = try await api.snapshot(token: value.deviceToken)
            await enableNotifications()
        } else if status.status == "expired" {
            try store.clear()
            credentials = nil
        }
        errorMessage = nil
    }
    func confirm() async {
        guard let active = snapshot?.active else { return }
        await perform(Mutation(operationID: UUID().uuidString, action: "confirm", expected: active.expected, targetThreadID: nil))
    }
    func select(_ thread: BrainThread) async {
        if thread.id == snapshot?.active?.threadID { await confirm() }
        else { await switchTo(thread) }
    }
    func switchTo(_ thread: BrainThread) async {
        guard thread.id != snapshot?.active?.threadID else { return }
        await perform(Mutation(operationID: UUID().uuidString, action: "switch", expected: snapshot?.active?.expected, targetThreadID: thread.id))
    }
    private func perform(_ command: Mutation) async {
        guard !isSending && !isStale, let token = credentials?.deviceToken else { return }
        isSending = true
        generation += 1
        errorMessage = nil
        notice = nil
        defer { isSending = false }
        do {
            let result = try await api.apply(command, token: token)
            snapshot = result.snapshot
            notice = result.status == "applied" ? (command.action == "confirm" ? "確認しました" : "切り替えました") : "実行状況が変わりました。選び直してください。"
        } catch { failure(error) }
    }
    private func failure(_ error: Error) {
        isStale = true
        errorMessage = error.localizedDescription
        if case APIError.unauthorized = error {
            do {
                if let token = credentials?.deviceToken { _ = try store.clear(ifTokenMatches: token) }
            } catch { errorMessage = error.localizedDescription }
            credentials = nil
            snapshot = nil
            lastNotificationAttempt = .distantPast
        }
    }
    func enableNotifications() async {
        guard credentials?.deviceID != nil else { return }
        lastNotificationAttempt = Date()
        do { notificationsDenied = try await requestNotifications() }
        catch { errorMessage = error.localizedDescription }
    }
    static func requestSystemNotifications() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        }
        let denied = (await center.notificationSettings()).authorizationStatus == .denied
        if !denied { WKApplication.shared().registerForRemoteNotifications() }
        return denied
    }
    nonisolated static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
