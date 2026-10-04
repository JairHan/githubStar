import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RepositoryStore
    @ObservedObject var account: GitHubAccountStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "star.circle.fill").font(.system(size: 32)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GitHub Star").font(.headline)
                    Text("你的开源发现窗口").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.vertical, 24)
            List(selection: $store.feed) {
                Section("发现") {
                    ForEach([Feed.activity, .daily, .weekly, .allTime, .search]) { feed in
                        Label(feed.title, systemImage: feed.icon).tag(feed)
                    }
                }
                Section("资料库") {
                    Label("我的 Stars", systemImage: "star.fill").tag(Feed.saved)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 8) {
                Label("为好项目留一颗星", systemImage: "sparkles").font(.caption)
                Text("探索 · Star · 构建").font(.caption2).foregroundStyle(.secondary)
                Button { account.showsLogin = true } label: {
                    Label(account.user.map { "@" + $0.login } ?? "登录 GitHub", systemImage: "person.crop.circle")
                }.buttonStyle(.plain).font(.callout)
                SettingsLink { Label("设置与数据说明", systemImage: "gearshape") }.buttonStyle(.plain).font(.caption).padding(.top, 8)
            }.padding(18).foregroundStyle(.secondary)
        }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
    }
}
