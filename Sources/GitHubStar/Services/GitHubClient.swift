import Foundation

enum GitHubError: LocalizedError {
    case message(String)
    case unauthorized
    var errorDescription: String? { switch self { case .message(let s): return s; case .unauthorized: return "GitHub 登录已失效，请重新授权。" } }
}
struct GitHubClient {
    var token: String? = nil
    var session: URLSession = .shared
    func fetch(_ url: URL, api: Bool = false) async throws -> Data {
        try await fetchResponse(url, api: api).0
    }
    private func fetchResponse(_ url: URL, api: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("GitHubStar-macOS", forHTTPHeaderField: "User-Agent")
        if api {
            if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.message("服务器响应无效。") }
        if http.statusCode == 401 { throw GitHubError.unauthorized }
        if http.statusCode == 403 || http.statusCode == 429 { throw GitHubError.message("GitHub 拒绝请求：权限不足或请求额度耗尽，请检查授权或稍后重试。") }
        guard (200..<300).contains(http.statusCode) else { throw GitHubError.message("GitHub 返回 HTTP \(http.statusCode)，请检查查询语法或稍后重试。") }
        return (data, http)
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

    func currentUser() async throws -> GitHubUser {
        guard token != nil else { throw GitHubError.unauthorized }
        let data = try await fetch(URL(string: "https://api.github.com/user")!, api: true)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }
    func receivedEvents(login: String, page: Int) async throws -> ActivityPage {
        guard token != nil else { throw GitHubError.unauthorized }
        guard (1...3).contains(page), !login.isEmpty,
              login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw GitHubError.message("动态请求参数无效。")
        }
        var url = URLComponents(string: "https://api.github.com")!
        url.path = "/users/" + login + "/received_events"
        url.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))]
        let (data, response) = try await fetchResponse(url.url!, api: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode([GitHubEvent].self, from: data)
        let next = response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") ?? (events.count == 100)
        return ActivityPage(items: events, hasMore: next && page < 3)
    }
    func repository(fullName: String) async throws -> Repository {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
            $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }) else {
            throw GitHubError.message("仓库名称无效。")
        }
        var url = URLComponents(string: "https://api.github.com")!
        url.path = "/repos/" + fullName
        let data = try await fetch(url.url!, api: true)
        return try JSONDecoder().decode(APIRepo.self, from: data).repository
    }
    func starred(page: Int) async throws -> StarredPage {
        guard token != nil else { throw GitHubError.unauthorized }
        let data = try await fetch(URL(string: "https://api.github.com/user/starred?sort=created&direction=desc&per_page=100&page=\(page)")!, api: true)
        let repos = try JSONDecoder().decode([APIRepo].self, from: data).map { $0.repository }
        return StarredPage(items: repos, hasMore: repos.count == 100)
    }
    func isStarred(_ repo: Repository) async throws -> Bool {
        let status = try await starRequest(repo, method: "GET")
        return status == 204
    }
    func setStarred(_ repo: Repository, starred: Bool) async throws {
        _ = try await starRequest(repo, method: starred ? "PUT" : "DELETE")
    }
    private func starRequest(_ repo: Repository, method: String) async throws -> Int {
        guard let token else { throw GitHubError.unauthorized }
        var url = URLComponents(string: "https://api.github.com")!
        url.path = "/user/starred/" + repo.fullName
        var request = URLRequest(url: url.url!)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubStar-macOS", forHTTPHeaderField: "User-Agent")
        if method == "PUT" { request.httpBody = Data(); request.setValue("0", forHTTPHeaderField: "Content-Length") }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.message("服务器响应无效。") }
        if http.statusCode == 401 { throw GitHubError.unauthorized }
        if http.statusCode == 204 || (method == "GET" && http.statusCode == 404) { return http.statusCode }
        if http.statusCode == 403 { throw GitHubError.message("无法更新 Star：权限不足或 GitHub 限流，请检查授权后重试。") }
        throw GitHubError.message("Star 请求失败（HTTP \(http.statusCode)），请稍后重试。")
    }
}
struct StarredPage { let items: [Repository]; let hasMore: Bool }
struct SearchPage { let items: [Repository]; let total: Int; let incomplete: Bool }
private struct APIResult: Decodable { let items: [APIRepo]; let total_count: Int; let incomplete_results: Bool }
struct APIRepo: Decodable {
    let full_name: String
    let description: String?
    let language: String?
    let stargazers_count: Int
    let forks_count: Int
    let topics: [String]?
    var repository: Repository { Repository(fullName: full_name, description: description ?? "", language: language, stars: stargazers_count, forks: forks_count, topics: topics ?? []) }
}
