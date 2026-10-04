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
    case daily, weekly, allTime, search, saved
    var id: String { rawValue }
    var title: String {
        switch self { case .daily: "今日热门"; case .weekly: "每周涨星"; case .allTime: "总星榜"; case .search: "搜索仓库"; case .saved: "我的收藏" }
    }
    var icon: String {
        switch self { case .daily: "flame"; case .weekly: "chart.line.uptrend.xyaxis"; case .allTime: "star"; case .search: "magnifyingglass"; case .saved: "bookmark" }
    }
    var subtitle: String {
        switch self {
        case .daily: "发现今天备受关注的开源项目"
        case .weekly: "GitHub Trending 周榜 · 按本周新增 Star 排序"
        case .allTime: "按累计 Star 排序，探索广受欢迎的仓库"
        case .search: "搜索名称、描述，或使用 GitHub 查询语法"
        case .saved: "值得留意的项目，保存在这台 Mac 上"
        }
    }
}
