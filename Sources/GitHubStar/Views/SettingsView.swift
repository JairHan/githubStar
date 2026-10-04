import SwiftUI

struct SettingsView: View {
    @ObservedObject var account: GitHubAccountStore
    @ViewState private var showsAccount = false
    var body: some View {
        Form {
            Section("GitHub 账号") {
                Text(account.user.map { "当前账号：@" + $0.login } ?? "尚未登录")
                Button("管理 GitHub 登录") { showsAccount = true }
                Text("登录后点击 Star / 取消 Star 会直接更新 GitHub。令牌保存在 macOS 钥匙串。登录过期后请重新授权。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("高级：开发者 OAuth 配置") {
                    if account.hasBundledClientID {
                        Text("当前版本已内置发行者的 OAuth App，无需额外配置。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("开发用 Client ID", text: $account.developmentClientID).textFieldStyle(.roundedBorder).disabled(account.isBusy)
                        Text("仅供开发与自编译使用。发行者应注册一次 OAuth App，启用 Device Flow，并在打包时内置公开 Client ID。不要填写 Client Secret。").font(.caption).foregroundStyle(.secondary)
                        Link("注册 GitHub OAuth App", destination: URL(string: "https://github.com/settings/applications/new")!)
                    }
                }
            }
            Section("GitHub 动态") {
                Text("动态使用 GitHub 官方网页，首次需要在页面内登录。网页登录会保留，与应用的 Star 授权独立；退出 Star 账号不会退出网页。")
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
