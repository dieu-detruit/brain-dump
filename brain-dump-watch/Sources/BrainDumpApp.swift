import SwiftUI
@main
struct BrainDumpApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { WindowGroup { ExecutionView() } }
}
