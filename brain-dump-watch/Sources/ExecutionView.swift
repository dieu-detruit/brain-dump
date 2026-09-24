import SwiftUI
struct ExecutionView: View {
    @StateObject private var model = ExecutionModel()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            List {
                if model.credentials?.deviceID == nil {
                    PairingView(credentials: model.credentials)
                } else {
                    Section("今やっている") {
                        if let active = model.snapshot?.active,
                           let thread = model.snapshot?.threads.first(where: { $0.id == active.threadID }) {
                            Text(thread.title).fixedSize(horizontal: false, vertical: true)
                            Button("続けている") { Task { await model.confirm() } }
                                .disabled(model.isSending || model.isStale)
                        } else { Text("実行中のThreadはありません") }
                    }
                    if model.isStale { Text("未更新").foregroundStyle(.orange) }
                    if let notice = model.notice { Text(notice).font(.footnote) }
                    Section("切り替える") {
                        ForEach(model.snapshot?.threads ?? []) { thread in
                            Button { Task { await model.switchTo(thread) } } label: {
                                VStack(alignment: .leading) {
                                    Text(thread.title).fixedSize(horizontal: false, vertical: true)
                                    Text(thread.delegation == "ai" ? "AI" : thread.delegation == "colleague" ? "他の人" : "待機中")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.disabled(model.isSending || model.isStale || thread.id == model.snapshot?.active?.threadID)
                        }
                        if model.snapshot?.threads.isEmpty == true { Text("Web版でThreadを作成してください") }
                    }
                    if model.notificationsDenied {
                        Text("通知がオフです。Watchの通知設定から許可してください。").font(.footnote)
                        Button("通知設定を再確認") { Task { await model.enableNotifications() } }
                    }
                }
                if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                if model.isSending || model.loading { ProgressView() }
                Button("更新") { Task { await model.refresh() } }.disabled(model.isSending || model.loading)
            }
            .navigationTitle("Brain Dump")
            .task(id: phase) {
                guard phase == .active else { return }
                model.becameActive()
                while !Task.isCancelled {
                    await model.refresh()
                    let seconds: UInt64 = model.credentials?.deviceID == nil ? 3 : 15
                    do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
                }
            }
        }
    }
}
