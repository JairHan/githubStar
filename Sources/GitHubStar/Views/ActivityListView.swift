import SwiftUI

struct ActivityListView: View {
    @ObservedObject var activity: ActivityStore
    @ObservedObject var account: GitHubAccountStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GitHub 动态").font(.system(size: 28, weight: .bold))
                        Text(account.user.map { "@\($0.login) 收到的事件动态" } ?? "关注开源社区的新动向")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "newspaper").font(.system(size: 30, weight: .light)).foregroundStyle(.indigo)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("筛选已加载动态：用户、仓库、关键词", text: $activity.query).textFieldStyle(.plain)
                    if !activity.query.isEmpty {
                        Button { activity.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Picker("类型", selection: $activity.category) {
                        ForEach(ActivityCategory.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 170)
                    Spacer()
                    Text("最近 30 天 · 最多 300 条").font(.caption).foregroundStyle(.secondary)
                }
                Text("显示 GitHub 事件动态；网页 Feed 的推荐内容不包含在此列表中。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
            if let error = activity.error {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                    Spacer()
                    Button("重试") { Task { await activity.load() } }
                }.font(.caption).padding(12).background(.orange.opacity(0.08))
            }
            if account.accessToken == nil {
                VStack(spacing: 16) {
                    ContentUnavailableView(account.isSignedIn ? "登录已过期" : "登录后查看动态", systemImage: "person.crop.circle",
                        description: Text("使用应用的 GitHub 授权即可查看，无需额外网页登录。"))
                    Button(account.isSignedIn ? "重新授权" : "登录 GitHub") { account.showsLogin = true }.buttonStyle(.borderedProminent)
                }.frame(maxHeight: .infinity)
            } else if activity.visibleItems.isEmpty {
                if activity.isLoading { ProgressView("正在获取 GitHub 动态…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    ContentUnavailableView(activity.error == nil ? "暂无匹配的动态" : "暂时无法获取动态", systemImage: "newspaper",
                        description: Text(activity.items.isEmpty ? "最近可能没有收到事件。GitHub 动态接口存在更新延迟，可以稍后刷新。" : "试试其他关键词或类型，或加载更多动态。"))
                        .frame(maxHeight: .infinity)
                }
            } else {
                List(selection: $activity.selectedID) {
                    ForEach(activity.visibleItems) { event in
                        ActivityRow(event: event).tag(event.id)
                            .contextMenu {
                                Button("打开这条动态") { NSWorkspace.shared.open(event.url) }
                                Button("打开仓库") { NSWorkspace.shared.open(event.repositoryURL) }
                            }
                    }
                }.listStyle(.inset)
                    .overlay(alignment: .topTrailing) { if activity.isLoading { ProgressView().controlSize(.small).padding(12) } }
            }
            HStack {
                Text("\(activity.visibleItems.count) / \(activity.items.count) 条动态")
                if let date = activity.updatedAt { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2) }
                Spacer()
                if activity.hasMore { Button("加载更多") { Task { await activity.load(more: true) } }.disabled(activity.isLoading) }
            }.font(.caption).foregroundStyle(.secondary).padding(12).background(.bar)
        }
        .onChange(of: activity.query) { _, _ in activity.reconcileSelection() }
        .onChange(of: activity.category) { _, _ in activity.reconcileSelection() }
    }
}

private struct ActivityRow: View {
    let event: GitHubEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.icon).font(.title3).foregroundStyle(.indigo).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.actor.login).font(.headline).lineLimit(1)
                    Spacer()
                    Text(event.created_at, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(event.summary).font(.caption).foregroundStyle(.secondary)
                Text(event.repo.name).font(.system(.body, design: .monospaced)).lineLimit(1)
                if let detail = event.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }.padding(.vertical, 9)
    }
}
