import SwiftUI

enum WatchTheme {
    static let paper = Color(red: 243 / 255, green: 240 / 255, blue: 232 / 255)
    static let ink = Color(red: 36 / 255, green: 35 / 255, blue: 31 / 255)
    static let orange = Color(red: 228 / 255, green: 105 / 255, blue: 69 / 255)
    static let muted = Color(red: 119 / 255, green: 114 / 255, blue: 105 / 255)
    static let card = Color(red: 1, green: 253 / 255, blue: 248 / 255)
}

struct ExecutionView: View {
    @StateObject private var model = ExecutionModel()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Brain Dump").font(.headline)
                if model.credentials?.deviceID == nil {
                    PairingView(credentials: model.credentials)
                } else {
                    heading("今やっている")
                    if let active = model.snapshot?.active,
                       let thread = model.snapshot?.threads.first(where: { $0.id == active.threadID }) {
                        Text(thread.title)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .foregroundStyle(WatchTheme.paper).background(WatchTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                        Button("続けている") { Task { await model.confirm() } }
                            .tint(WatchTheme.orange)
                            .disabled(model.isSending || model.isStale)
                    } else { Text("実行中のThreadはありません").font(.footnote) }
                    if model.isStale { Text("未更新").font(.footnote).foregroundStyle(WatchTheme.orange) }
                    if let notice = model.notice { Text(notice).font(.footnote) }
                    threadGroup("待機中", caption: "まだ誰にも渡していない", threads: model.snapshot?.waitingThreads ?? [])
                    threadGroup("進行中", caption: "AI・他の人に任せている", threads: model.snapshot?.delegatedThreads ?? [])
                    if model.snapshot?.threads.isEmpty == true { Text("Web版でThreadを作成してください").font(.footnote) }
                    if model.notificationsDenied {
                        Text("通知がオフです。Watchの通知設定から許可してください。").font(.footnote)
                        Button("通知設定を再確認") { Task { await model.enableNotifications() } }
                    }
                }
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(WatchTheme.orange)
                    Button("再試行") { Task { await model.refresh() } }.disabled(model.isSending || model.loading)
                }
                if model.isSending || model.loading { ProgressView().tint(WatchTheme.orange) }
            }
            .padding(.horizontal, 10).padding(.bottom, 16)
        }
        .foregroundStyle(WatchTheme.ink)
        .background(WatchTheme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
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
    private func heading(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(WatchTheme.muted).padding(.top, 6)
    }
    private func threadGroup(_ title: String, caption: String, threads: [BrainThread]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(title)
            Text(caption).font(.caption2).foregroundStyle(WatchTheme.muted)
            if threads.isEmpty { Text("なし").font(.footnote).foregroundStyle(WatchTheme.muted) }
            ForEach(threads) { thread in
                Button { Task { await model.switchTo(thread) } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thread.title).fixedSize(horizontal: false, vertical: true)
                        if thread.id == model.snapshot?.active?.threadID {
                            Text("今やっている").font(.caption2).foregroundStyle(WatchTheme.orange)
                        } else if let delegation = thread.delegation {
                            Text(delegation == "ai" ? "AI" : "他の人").font(.caption2).foregroundStyle(WatchTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(model.isSending || model.isStale || thread.id == model.snapshot?.active?.threadID)
            }
        }
    }
}
