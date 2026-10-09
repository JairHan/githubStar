import SwiftUI

struct ContentView: View {
    @ObservedObject var store: RepositoryStore
    @ObservedObject var account: GitHubAccountStore
    @ObservedObject var activity: ActivityStore
    @FocusState private var searchFocused: Bool
    private let languages = ["", "Swift", "Python", "TypeScript", "JavaScript", "Rust", "Go", "Java", "C", "C++", "Ruby", "Kotlin"]
    private var isRefreshing: Bool { store.feed == .activity ? activity.isLoading : store.isLoading }
    var body: some View {
        repositoryLayout
        .task(id: store.key) {
            if store.feed == .activity { await activity.load() }
            else { await store.load() }
        }
        .task { await account.restore() }
        .sheet(isPresented: $account.showsLogin, onDismiss: { account.cancelLogin() }) { AccountView(account: account).padding(24).frame(width: 520) }
    }
    @ToolbarContentBuilder private var pageToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { store.refreshID = UUID() } label: {
                Label(isRefreshing ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
            }
            .labelStyle(.titleAndIcon)
            .disabled(isRefreshing)
            .help("刷新当前页面（⌘R）")
        }
        ToolbarItem { Button { store.feed = .search; searchFocused = true } label: { Label("搜索", systemImage: "magnifyingglass") }.keyboardShortcut("f", modifiers: .command) }
    }
    private var repositoryLayout: some View {
        NavigationSplitView {
            SidebarView(store: store, account: account)
        } content: {
            Group {
                if store.feed == .activity {
                    ActivityListView(activity: activity, account: account)
                        .navigationSplitViewColumnWidth(min: 400, ideal: 570, max: 800)
                } else {
                    VStack(spacing: 0) {
                        header
                        if let error = store.error {
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text(error).font(.caption).textSelection(.enabled)
                                Spacer()
                                Button("重试") { store.refreshID = UUID() }
                            }.padding(12).background(.orange.opacity(0.08))
                        }
                        if store.items.isEmpty { emptyState.frame(maxHeight: .infinity) }
                        else {
                            List(selection: $store.selectedID) {
                                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, repo in
                                    RepositoryRow(repo: repo, rank: index + 1, saved: store.isSaved(repo))
                                        .tag(repo.id)
                                        .contextMenu {
                                            Button("在 GitHub 打开") { NSWorkspace.shared.open(repo.url) }
                                            Button(store.isSaved(repo) ? "取消 Star" : "Star") { store.requestStar(repo) }
                                            Button("复制仓库链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(repo.url.absoluteString, forType: .string) }
                                        }
                                }
                            }.listStyle(.inset).overlay(alignment: .topTrailing) { if store.isLoading { ProgressView().controlSize(.small).padding(12) } }
                        }
                        footer
                    }.navigationSplitViewColumnWidth(min: 400, ideal: 570, max: 800)
                }
            }
            .navigationTitle(store.feed.title)
            .toolbar { pageToolbar }
        } detail: {
            if store.feed == .activity {
                ActivityDetailView(activity: activity, store: store, account: account)
            } else if let repo = store.selected {
                RepositoryDetailView(repo: repo, saved: store.isSaved(repo), signedIn: account.isSignedIn, busy: store.starIsBusy(repo), error: store.starError, onSave: { store.requestStar(repo) })
                    .task(id: repo.id + account.sessionID.uuidString) { await store.checkStar(repo) }
            } else {
                ContentUnavailableView("选择一个仓库", systemImage: "square.stack.3d.up", description: Text("浏览项目详情，发现下一个灵感。"))
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.feed.title).font(.system(size: 28, weight: .bold))
                    Text(store.feed.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: store.feed.icon).font(.system(size: 30, weight: .light)).foregroundStyle(.indigo)
            }
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索仓库，例如 swift、AI、stars:>1000", text: $store.query)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .onSubmit { store.submitSearch() }
                    if !store.query.isEmpty {
                        Button { store.query = ""; if store.feed == .saved { store.filterStars() } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                Button("搜索") { store.submitSearch() }.buttonStyle(.borderedProminent)
            }
            HStack {
                Picker("语言", selection: $store.language) {
                    ForEach(languages, id: \.self) { Text($0.isEmpty ? "全部语言" : $0).tag($0) }
                }.labelsHidden().frame(width: 145)
                Spacer()
                if store.feed == .weekly { Label("周涨星 ↓", systemImage: "arrow.up.right").foregroundStyle(.green) }
                else if store.feed == .allTime || store.feed == .search { Label("总星数 ↓", systemImage: "star").foregroundStyle(.secondary) }
                else { Text(store.feed == .saved ? "GitHub Stars" : "Trending 排名").foregroundStyle(.secondary) }
            }.font(.caption)
        }.padding(22)
        .onChange(of: store.query) { _, _ in if store.feed == .saved { store.filterStars() } }
    }
    @ViewBuilder private var emptyState: some View {
        if store.isLoading { ProgressView("正在连接 GitHub…").frame(maxWidth: .infinity) }
        else if store.feed == .saved && !account.isSignedIn {
            VStack(spacing: 16) {
                ContentUnavailableView("登录后查看你的 Stars", systemImage: "person.crop.circle", description: Text("与 GitHub 账号同步，点击 Star 就能保存到 GitHub。"))
                Button("登录 GitHub") { account.showsLogin = true }.buttonStyle(.borderedProminent)
            }
        }
        else if store.feed == .search && store.submittedQuery.isEmpty {
            ContentUnavailableView("发现你感兴趣的项目", systemImage: "magnifyingglass", description: Text("输入关键词后按回车。支持 language:Swift、topic:ai 等查询。"))
        } else {
            ContentUnavailableView(store.error == nil ? "暂无仓库" : "暂时无法获取仓库", systemImage: store.feed == .saved ? "star" : "network", description: Text(store.feed == .saved ? "暂无匹配的已 Star 项目；可以加载更多，或在仓库详情中点击 Star。" : "试试其他关键词、语言，或点击刷新。"))
        }
    }
    private var footer: some View {
        HStack {
            Text((store.feed == .search || store.feed == .allTime) ? "已显示 \(store.items.count) / \(store.total.formatted()) 个" : "\(store.items.count) 个仓库").font(.caption).foregroundStyle(.secondary)
            if let date = store.updatedAt { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            if store.canLoadMore { Button("加载更多") { Task { await store.load(more: true) } }.disabled(store.isLoading) }
            if store.incomplete { Text("部分结果").font(.caption).foregroundStyle(.orange) }
        }.padding(12).background(.bar)
    }
}
