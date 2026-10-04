import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RepositoryStore
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
                    ForEach([Feed.daily, .weekly, .allTime, .search]) { feed in
                        Label(feed.title, systemImage: feed.icon).tag(feed)
                    }
                }
                Section("资料库") {
                    Label("我的收藏", systemImage: "bookmark").badge(store.favorites.count).tag(Feed.saved)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 8) {
                Label("为好项目留一颗星", systemImage: "sparkles").font(.caption)
                Text("探索 · 收藏 · 构建").font(.caption2).foregroundStyle(.secondary)
                SettingsLink { Label("设置与数据说明", systemImage: "gearshape") }.buttonStyle(.plain).font(.caption).padding(.top, 8)
            }.padding(18).foregroundStyle(.secondary)
        }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
    }
}
