import SwiftUI
struct PairingView: View {
    let credentials: WatchCredentials?
    var body: some View {
        Section("Watchを登録") {
            Text("Web版の「Watch」を開き、このコードを入力してください。")
            if let code = credentials?.code {
                Text(code).font(.title2.monospacedDigit())
                if let expiry = credentials?.expiresAt, let date = ExecutionModel.date(expiry) {
                    Text(date, style: .timer).font(.caption)
                }
            } else { Text("登録コードを取得しています…") }
        }
    }
}
