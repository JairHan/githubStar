import SwiftUI

struct ActivityDetailView: View {
    @ObservedObject var activity: ActivityStore
    @ObservedObject var store: RepositoryStore
    @ObservedObject var account: GitHubAccountStore

    var body: some View {
        Group {
            if let event = activity.selected {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("\(event.actor.login) \(event.summary)", systemImage: event.icon).font(.headline)
                        Text(event.created_at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        if let detail = event.detail, !detail.isEmpty { Text(detail).font(.callout).lineLimit(6).textSelection(.enabled) }
                        Button("在 GitHub 查看动态") { NSWorkspace.shared.open(event.url) }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    Divider()
                    if let repo = activity.selectedRepository, repo.fullName.lowercased() == event.repo.name.lowercased() {
                        RepositoryDetailView(repo: repo, saved: store.isSaved(repo), signedIn: account.isSignedIn,
                            busy: store.starIsBusy(repo), error: store.starError, onSave: { store.requestStar(repo) })
                            .task(id: repo.id + account.sessionID.uuidString) { await store.checkStar(repo) }
                    } else if activity.isLoadingRepository {
                        ProgressView("正在加载仓库详情…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = activity.repositoryError {
                        VStack(spacing: 16) {
                            ContentUnavailableView("无法加载仓库详情", systemImage: "network", description: Text(error))
                            Button("重试") { Task { await activity.loadSelectedRepository() } }
                            Button("在 GitHub 打开仓库") { NSWorkspace.shared.open(event.repositoryURL) }
                        }.frame(maxHeight: .infinity)
                    } else { Spacer() }
                }
            } else {
                ContentUnavailableView("选择一条动态", systemImage: "newspaper", description: Text("查看事件和相关仓库，发现值得 Star 的项目。"))
            }
        }.task(id: activity.detailKey) { await activity.loadSelectedRepository() }
    }
}
