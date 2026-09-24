import WatchKit
import Foundation
final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() { NotificationHandler.install() }
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do {
                guard let credentials = try CredentialStore.shared.load(), credentials.deviceID != nil else { return }
                try await APIClient().registerPush(hex, token: credentials.deviceToken)
            } catch { await NotificationHandler.showFailure("通知の登録に失敗しました。アプリを開き直してください。") }
        }
    }
    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        Task { await NotificationHandler.showFailure("通知を登録できませんでした。通信と通知設定を確認してください。") }
    }
}
