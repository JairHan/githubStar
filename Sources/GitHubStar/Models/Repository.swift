import Foundation

struct Repository: Codable, Identifiable, Hashable {
    var id: String { fullName }
    let fullName: String
    let description: String
    let language: String?
    let stars: Int
    let forks: Int
    var gain: Int?
    var period: String?
    var topics: [String] = []
    var url: URL { URL(string: "https://github.com/\(fullName)")! }
    var owner: String { fullName.components(separatedBy: "/").first ?? "" }
    var name: String { fullName.components(separatedBy: "/").last ?? fullName }
}

enum Feed: String, CaseIterable, Identifiable {
    case activity, daily, weekly, allTime, search, saved
    var id: String { rawValue }
    var title: String {
        switch self { case .activity: "GitHub 动态"; case .daily: "今日热门"; case .weekly: "每周涨星"; case .allTime: "总星榜"; case .search: "搜索仓库"; case .saved: "我的 Stars" }
    }
    var icon: String {
        switch self { case .activity: "newspaper"; case .daily: "flame"; case .weekly: "chart.line.uptrend.xyaxis"; case .allTime: "star"; case .search: "magnifyingglass"; case .saved: "star.fill" }
    }
    var subtitle: String {
        switch self {
        case .activity: "浏览 GitHub 官方动态与推荐"
        case .daily: "发现今天备受关注的开源项目"
        case .weekly: "GitHub Trending 周榜 · 按本周新增 Star 排序"
        case .allTime: "按累计 Star 排序，探索广受欢迎的仓库"
        case .search: "搜索名称、描述，或使用 GitHub 查询语法"
        case .saved: "GitHub 账号已 Star 的仓库 · 筛选已加载的项目"
        }
    }
}
