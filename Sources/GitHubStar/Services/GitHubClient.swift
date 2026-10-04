import Foundation

enum GitHubError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct GitHubClient {
    func fetch(_ url: URL, api: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("GitHubStar-macOS", forHTTPHeaderField: "User-Agent")
        if api {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.message("服务器响应无效。") }
        if http.statusCode == 403 || http.statusCode == 429 { throw GitHubError.message("GitHub 请求额度暂时耗尽，请稍后重试。匿名搜索的额度较低。") }
        guard (200..<300).contains(http.statusCode) else { throw GitHubError.message("GitHub 返回 HTTP \(http.statusCode)，请检查查询语法或稍后重试。") }
        return data
    }
    func trending(weekly: Bool, language: String) async throws -> [Repository] {
        var url = URLComponents(string: "https://github.com/trending")!
        if !language.isEmpty { url.path += "/" + language.lowercased().replacingOccurrences(of: " ", with: "-") }
        url.queryItems = [URLQueryItem(name: "since", value: weekly ? "weekly" : "daily")]
        let data = try await fetch(url.url!)
        let items = TrendingParser.parse(String(decoding: data, as: UTF8.self), period: weekly ? "week" : "day")
        guard !items.isEmpty else { throw GitHubError.message("该语言暂无 Trending 数据，或 GitHub 页面结构发生变化。请切换全部语言后重试。") }
        return weekly ? items.sorted { ($0.gain ?? 0) > ($1.gain ?? 0) } : items
    }
    func search(query: String, language: String, page: Int) async throws -> SearchPage {
        var parts = [query.isEmpty ? "stars:>1" : query]
        if !language.isEmpty { parts.append("language:\"\(language)\"") }
        var url = URLComponents(string: "https://api.github.com/search/repositories")!
        url.queryItems = [URLQueryItem(name: "q", value: parts.joined(separator: " ")), URLQueryItem(name: "sort", value: "stars"), URLQueryItem(name: "order", value: "desc"), URLQueryItem(name: "per_page", value: "30"), URLQueryItem(name: "page", value: String(page))]
        let data = try await fetch(url.url!, api: true)
        let result = try JSONDecoder().decode(APIResult.self, from: data)
        return SearchPage(items: result.items.map { $0.repository }, total: result.total_count, incomplete: result.incomplete_results)
    }
}
struct SearchPage { let items: [Repository]; let total: Int; let incomplete: Bool }
private struct APIResult: Decodable { let items: [APIRepo]; let total_count: Int; let incomplete_results: Bool }
private struct APIRepo: Decodable {
    let full_name: String
    let description: String?
    let language: String?
    let stargazers_count: Int
    let forks_count: Int
    let topics: [String]?
    var repository: Repository { Repository(fullName: full_name, description: description ?? "", language: language, stars: stargazers_count, forks: forks_count, topics: topics ?? []) }
}
