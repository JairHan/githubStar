import SwiftUI

@main
struct GitHubStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var account: GitHubAccountStore
    @StateObject private var store: RepositoryStore
    @StateObject private var activity: ActivityStore
    init() {
        let account = GitHubAccountStore()
        _account = StateObject(wrappedValue: account)
        _store = StateObject(wrappedValue: RepositoryStore(account: account))
        _activity = StateObject(wrappedValue: ActivityStore(account: account))
    }
    private var commandRepository: Repository? {
        if store.feed == .activity {
            guard let repo = activity.selectedRepository, repo.fullName.lowercased() == activity.selected?.repo.name.lowercased() else { return nil }
            return repo
        }
        return store.selected
    }
    var body: some Scene {
        WindowGroup("GitHub Star") {
            ContentView(store: store, account: account, activity: activity)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(.indigo)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新当前页面") { store.refreshID = UUID() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.feed == .activity ? activity.isLoading : store.isLoading)
                Button("在 GitHub 打开") { if let repo = commandRepository { NSWorkspace.shared.open(repo.url) } }.keyboardShortcut("o", modifiers: .command).disabled(commandRepository == nil)
                Button("Star / 取消 Star") { if let repo = commandRepository { store.requestStar(repo) } }.keyboardShortcut("d", modifiers: .command).disabled(commandRepository == nil)
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
