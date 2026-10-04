import Foundation

enum GitHubActivityTests {
    static let fixture = """
    [
      {"id":"1","type":"WatchEvent","actor":{"login":"alice"},"repo":{"name":"swiftlang/swift"},"payload":{"action":"started"},"created_at":"2026-10-04T12:00:00Z"},
      {"id":"2","type":"ReleaseEvent","actor":{"login":"bob"},"repo":{"name":"owner/project"},"payload":{"action":"published","release":{"name":"Version 2","tag_name":"v2","html_url":"https://github.com/owner/project/releases/tag/v2"}},"created_at":"2026-10-04T11:00:00Z"},
      {"id":"3","type":"PushEvent","actor":{"login":"bob"},"repo":{"name":"owner/project"},"payload":{"ref":"refs/heads/main","head":"sha-without-commits"},"created_at":"2026-10-04T10:00:00Z"},
      {"id":"4","type":"FutureEvent","actor":{"login":"alice"},"repo":{"name":"owner/project"},"payload":{"comment":{"html_url":"https://evil.example/steal"}},"created_at":"2026-10-04T09:00:00Z"},
      {"id":"5","type":"IssuesEvent","actor":{"login":"bob"},"repo":{"name":"owner/project"},"payload":{"action":"closed","issue":{"title":"Fix crash","html_url":"https://github.com/owner/project/issues/42"}},"created_at":"2026-10-04T08:00:00Z"}
    ]
    """
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); MockGitHubProtocol.responseHeaders = [:] }
        let client = GitHubClient(token: "activity-test-only", session: session)
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.host == "api.github.com")
            precondition(request.url?.path == "/users/test-user/received_events")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer activity-test-only")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains(URLQueryItem(name: "page", value: "2")))
            precondition(query.contains(URLQueryItem(name: "per_page", value: "100")))
            return (200, Data(fixture.utf8))
        }
        let page = try await client.receivedEvents(login: "test-user", page: 2)
        precondition(page.items.count == 5 && !page.hasMore)
        precondition(page.items[0].category == .stars && page.items[0].summary == "Star 了仓库")
        precondition(page.items[1].detail == "Version 2" && page.items[1].url.path == "/owner/project/releases/tag/v2")
        precondition(page.items[2].summary == "推送了代码" && page.items[2].detail == "main")
        precondition(page.items[3].url.host == "github.com" && page.items[3].summary == "更新了仓库动态")
        precondition(page.items[4].detail == "Fix crash" && page.items[4].summary == "关闭了 Issue")
        MockGitHubProtocol.responseHeaders = ["Link": "<https://api.github.com/users/test-user/received_events?page=3>; rel=\"next\""]
        let shortPageWithNext = try await client.receivedEvents(login: "test-user", page: 2)
        precondition(shortPageWithNext.items.count < 100 && shortPageWithNext.hasMore)
        MockGitHubProtocol.responseHeaders = [:]
        MockGitHubProtocol.handler = { _ in
            let first = try JSONSerialization.jsonObject(with: Data(fixture.utf8)) as! [[String: Any]]
            return (200, try JSONSerialization.data(withJSONObject: Array(repeating: first[0], count: 100)))
        }
        let fullPage = try await client.receivedEvents(login: "test-user", page: 1)
        let lastPage = try await client.receivedEvents(login: "test-user", page: 3)
        precondition(fullPage.hasMore && !lastPage.hasMore)
        MockGitHubProtocol.handler = { _ in (200, Data("[]".utf8)) }
        let empty = try await client.receivedEvents(login: "test-user", page: 1)
        precondition(empty.items.isEmpty && !empty.hasMore)
        MockGitHubProtocol.handler = { _ in (401, Data()) }
        do { _ = try await client.receivedEvents(login: "test-user", page: 1); preconditionFailure("Expired auth must fail") }
        catch GitHubError.unauthorized { }
        do { _ = try await GitHubClient(session: session).receivedEvents(login: "test-user", page: 1); preconditionFailure("Login required") }
        catch GitHubError.unauthorized { }
        do { _ = try await client.receivedEvents(login: "test-user", page: 4); preconditionFailure("300 event limit") }
        catch GitHubError.message { }
        do { _ = try await client.repository(fullName: "../user"); preconditionFailure("Invalid repo") }
        catch GitHubError.message { }
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.host == "api.github.com" && request.url?.path == "/repos/swiftlang/swift")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer activity-test-only")
            return (200, Data("{\"full_name\":\"swiftlang/swift\",\"description\":\"Swift language\",\"language\":\"C++\",\"stargazers_count\":70000,\"forks_count\":10000}".utf8))
        }
        let repo = try await client.repository(fullName: "swiftlang/swift")
        precondition(repo.stars == 70000 && repo.fullName == "swiftlang/swift")
        print("PASS: native activity auth reuse, pagination, empty feed, expiry, event variants and repository details")
    }
}
