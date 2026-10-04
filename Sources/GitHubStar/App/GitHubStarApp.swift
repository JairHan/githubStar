import SwiftUI

@main
struct GitHubStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = RepositoryStore()
    var body: some Scene {
        WindowGroup("GitHub Star") {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(.indigo)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新仓库") { store.refreshID = UUID() }.keyboardShortcut("r", modifiers: .command)
                Button("在 GitHub 打开") { if let repo = store.selected { NSWorkspace.shared.open(repo.url) } }.keyboardShortcut("o", modifiers: .command)
                Button("收藏 / 取消收藏") { if let repo = store.selected { store.toggleSave(repo) } }.keyboardShortcut("d", modifiers: .command)
            }
        }
        Settings { SettingsView().frame(width: 440) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
