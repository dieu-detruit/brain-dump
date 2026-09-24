import Foundation
import UserNotifications

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    static func command(from payload: [AnyHashable: Any]) throws -> Mutation {
        guard let session = payload["session_id"] as? String,
              !session.isEmpty, session.count <= 19, session.allSatisfy({ $0.isASCII && $0.isNumber }),
              let revision = payload["confirmation_revision"] as? String, UUID(uuidString: revision) != nil,
              let operation = payload["operation_id"] as? String, UUID(uuidString: operation) != nil else { throw APIError.invalidNotification }
        return Mutation(operationID: operation, action: "confirm", expected: .init(sessionID: session, confirmationRevision: revision), targetThreadID: nil)
    }
    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let confirm = UNNotificationAction(identifier: "CONFIRM", title: "続けている", options: [])
        let change = UNNotificationAction(identifier: "SWITCH", title: "切り替える", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "EXECUTION_CHECK_IN", actions: [confirm, change], intentIdentifiers: [], options: [])])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == "CONFIRM" else {
            completionHandler()
            return // Foreground action and notification taps open the main thread list.
        }
        Task {
            defer { completionHandler() }
            var requestToken: String?
            do {
                let command = try Self.command(from: response.notification.request.content.userInfo)
                guard let credential = try CredentialStore.shared.load(), credential.deviceID != nil else { throw APIError.unauthorized }
                requestToken = credential.deviceToken
                let result = try await APIClient().apply(command, token: credential.deviceToken)
                if result.status != "applied" { await Self.showFailure("実行状況が変わりました。アプリで確認してください。") }
            } catch {
                if case APIError.unauthorized = error, let token = requestToken { _ = try? CredentialStore.shared.clear(ifTokenMatches: token) }
                await Self.showFailure("回答を保存できませんでした。アプリで状態を確認してください。")
            }
        }
    }
    static func showFailure(_ message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Brain Dump"
        content.body = message
        content.sound = .default
        // No check-in category: failure notifications cannot themselves trigger confirmation.
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "check-in-failed", content: content, trigger: nil))
    }
}
