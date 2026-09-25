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
                    if model.snapshot?.needsConfirmation == true {
                        Text("まだやっている？ 実行中の作業をタップして確認してください。")
                            .font(.footnote).foregroundStyle(WatchTheme.orange)
                    }
                    if model.isStale { Text("未更新").font(.footnote).foregroundStyle(WatchTheme.orange) }
                    if let notice = model.notice { Text(notice).font(.footnote) }
                    threadGroup("待機中", threads: model.snapshot?.waitingThreads ?? [])
                    threadGroup("進行中", threads: model.snapshot?.delegatedThreads ?? [])
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
    private func threadGroup(_ title: String, threads: [BrainThread]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(title)
            if threads.isEmpty { Text("なし").font(.footnote).foregroundStyle(WatchTheme.muted) }
            ForEach(threads) { thread in
                let active = thread.id == model.snapshot?.active?.threadID
                Button { Task { await model.select(thread) } } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle().stroke(active ? WatchTheme.orange : WatchTheme.muted, lineWidth: 1.5)
                            Circle().fill(active ? WatchTheme.orange : WatchTheme.muted).frame(width: 5, height: 5)
                        }.frame(width: 17, height: 17)
                        Text(thread.title).font(.system(size: 14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WatchDelegationIcon(delegation: thread.delegation)
                            .foregroundStyle(active ? Color(red: 240 / 255, green: 179 / 255, blue: 159 / 255) : WatchTheme.muted)
                    }
                    .padding(10).frame(minHeight: 48)
                    .foregroundStyle(active ? WatchTheme.paper : WatchTheme.ink)
                    .background(active ? WatchTheme.ink : WatchTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(thread.title)、\(thread.delegation == "ai" ? "Agentに委任" : thread.delegation == "colleague" ? "他の人に委任" : "待機中")、\(active ? "実行中" : "未実行")")
                .accessibilityHint(active ? "タップで継続を確認" : "タップでこの作業に切り替え")
                .disabled(model.isSending || model.isStale)
            }
        }
    }
}

// A small outlined robot retains the same delegation vocabulary as the web's Bot icon.
private struct WatchDelegationIcon: View {
    let delegation: String?
    var body: some View {
        Group {
            if delegation == "ai" {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.5).frame(width: 16, height: 13).offset(y: 2)
                    Path { path in
                        path.move(to: CGPoint(x: 10, y: 5)); path.addLine(to: CGPoint(x: 10, y: 1)); path.addLine(to: CGPoint(x: 7, y: 1))
                        path.move(to: CGPoint(x: 0, y: 9)); path.addLine(to: CGPoint(x: 0, y: 14))
                        path.move(to: CGPoint(x: 20, y: 9)); path.addLine(to: CGPoint(x: 20, y: 14))
                        path.move(to: CGPoint(x: 7, y: 10)); path.addLine(to: CGPoint(x: 7, y: 13))
                        path.move(to: CGPoint(x: 13, y: 10)); path.addLine(to: CGPoint(x: 13, y: 13))
                    }.stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            } else {
                Image(systemName: delegation == "colleague" ? "person" : "moon").font(.system(size: 18))
            }
        }.frame(width: 20, height: 20).accessibilityHidden(true)
    }
}
