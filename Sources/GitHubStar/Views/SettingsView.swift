import SwiftUI

struct SettingsView: View {
    @ObservedObject var account: GitHubAccountStore
    @ViewState private var showsAccount = false
    var body: some View {
        Form {
            Section("GitHub 账号") {
                Text(account.user.map { "当前账号：@" + $0.login } ?? "尚未登录")
                Button("登录与 OAuth App 配置") { showsAccount = true }
                Text("登录后点击 Star / 取消 Star 会直接更新 GitHub。令牌保存在 macOS 钥匙串。登录过期后请重新授权。").font(.caption).foregroundStyle(.secondary)
            }
            Section("数据来源") {
                Text("热门及涨星：GitHub Trending。每周涨星仅对周榜内仓库按新增 Star 排序。")
                Text("总星榜及搜索：GitHub REST API。每页 30 条，最多浏览 1,000 条。")
                Text("我的 Stars：从 GitHub 读取，每页 100 条，关键词与语言筛选作用于已加载项目。")
                Link("查看 GitHub Trending", destination: URL(string: "https://github.com/trending?since=weekly")!)
            }
            Section("本地数据") {
                Text("公开榜单缓存保存在 Application Support/GitHubStar。旧版的本地收藏文件保留，但不会自动转成 GitHub Star。账号的 Stars 列表仅在内存中加载，退出后清空。")
            }
            Section("快捷键") { Text("⌘F 搜索　⌘R 刷新　⌘O 打开仓库　⌘D Star") }
        }.formStyle(.grouped).padding().font(.callout)
        .sheet(isPresented: $showsAccount, onDismiss: { account.cancelLogin() }) { AccountView(account: account).padding(24).frame(width: 520) }
    }
}
