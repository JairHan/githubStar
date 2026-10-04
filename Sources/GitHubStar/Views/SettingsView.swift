import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("数据来源") {
                Text("热门及涨星：GitHub Trending。每周涨星仅对周榜内仓库按新增 Star 排序。")
                Text("总星榜及搜索：GitHub REST API。每页 30 条，最多浏览 1,000 条。匿名请求可能触发限流，稍后重试即可。")
                Link("查看 GitHub Trending", destination: URL(string: "https://github.com/trending?since=weekly")!)
            }
            Section("本地数据") {
                Text("收藏及最近榜单缓存保存在 Application Support/GitHubStar。断网时会显示缓存及获取时间。收藏中的统计值为收藏时的快照。")
            }
            Section("快捷键") {
                Text("⌘F 搜索　⌘R 刷新　⌘O 打开仓库　⌘D 收藏")
            }
        }.formStyle(.grouped).padding().font(.callout)
    }
}
