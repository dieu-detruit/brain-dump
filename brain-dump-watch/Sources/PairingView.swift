import SwiftUI
struct PairingView: View {
    let credentials: WatchCredentials?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Webと接続").font(.headline)
            Text("初回だけ、Web版の「Watch」でこのコードを入力します。いつものアカウントに接続します。").font(.footnote)
            if let code = credentials?.code {
                Text(code).font(.title2.monospacedDigit())
                if let expiry = credentials?.expiresAt, let date = ExecutionModel.date(expiry) {
                    Text(date, style: .timer).font(.caption)
                }
            } else { Text("接続コードを取得しています…") }
        }
    }
}
