import SwiftUI

@main
struct GitHubStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var account: GitHubAccountStore
    @StateObject private var store: RepositoryStore
    init() {
        let account = GitHubAccountStore()
        _account = StateObject(wrappedValue: account)
        _store = StateObject(wrappedValue: RepositoryStore(account: account))
    }
    var body: some Scene {
        WindowGroup("GitHub Star") {
            ContentView(store: store, account: account)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(.indigo)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新当前页面") { store.refreshID = UUID() }.keyboardShortcut("r", modifiers: .command)
                Button("在 GitHub 打开") { if let repo = store.selected { NSWorkspace.shared.open(repo.url) } }.keyboardShortcut("o", modifiers: .command).disabled(store.feed == .activity || store.selected == nil)
                Button("Star / 取消 Star") { if let repo = store.selected { store.requestStar(repo) } }.keyboardShortcut("d", modifiers: .command).disabled(store.feed == .activity || store.selected == nil)
            }
        }
        Settings { SettingsView(account: account).frame(width: 520) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
