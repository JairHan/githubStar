import Foundation

@MainActor
enum ReadmeTests {
    static func response(_ html: String, path: String = "README.md") -> Data {
        Data("<div id=\"readme\" class=\"md\" data-path=\"\(path)\"><article class=\"markdown-body\">\(html)</article></div>".utf8)
    }
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); MockGitHubProtocol.responseHeaders = [:] }
        MockGitHubProtocol.responseHeaders = ["Content-Type": "application/vnd.github.html+json; charset=utf-8"]
        let credentials = MemoryCredentials(); credentials.value = nil
        let account = GitHubAccountStore(keychain: credentials, session: session)
        let store = ReadmeStore(account: account, session: session)
        let html = "<h1>Project</h1><table><tr><td>Cell</td></tr></table><details><summary>More</summary><p>Content</p></details>"
        var requests = 0
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.absoluteString == "https://api.github.com/repos/owner/project/readme")
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            precondition(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.html+json")
            requests += 1
            return (200, response(html, path: ".github/README.rst"))
        }
        await store.load(StoreTests.repo)
        precondition(store.document?.html.contains(html) == true && !store.isLoading)
        precondition(store.document?.sourceURL.absoluteString == "https://github.com/owner/project/blob/HEAD/.github/README.rst")
        precondition(store.document?.linkBaseURL.absoluteString == "https://github.com/owner/project/blob/HEAD/.github/")
        precondition(store.document?.imageBaseURL.absoluteString == "https://raw.githubusercontent.com/owner/project/HEAD/.github/")
        await store.load(StoreTests.repo)
        precondition(requests == 1)
        account.logout()
        precondition(store.document == nil)
        await store.load(StoreTests.repo)
        precondition(requests == 2)
        MockGitHubProtocol.handler = { _ in (404, Data()) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.isMissing && store.document == nil && store.error == nil)
        let longHTML = "<pre>" + String(repeating: "字", count: 60_001) + "</pre>"
        MockGitHubProtocol.handler = { _ in (200, response(longHTML)) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.document?.html.contains(longHTML) == true)
        MockGitHubProtocol.responseHeaders = ["Content-Type": "application/json"]
        MockGitHubProtocol.handler = { _ in (200, Data("{\"content\":\"unrendered source\"}".utf8)) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.error != nil && store.document == nil)
        MockGitHubProtocol.responseHeaders = ["Content-Type": "text/html"]
        MockGitHubProtocol.handler = { _ in (200, Data(repeating: 65, count: 8 * 1024 * 1024 + 1)) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.error?.contains("过大") == true && store.document == nil)
        MockGitHubProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer readme-test-only")
            return (200, response(html))
        }
        _ = try await GitHubClient(token: "readme-test-only", session: session).readme(fullName: StoreTests.repo.id)
        try await selectionIsolation()
        print("PASS: rendered README media type, HTML preserved, RST path, relative bases, cache reset, missing file, size bounds and selection isolation")
    }

    static func selectionIsolation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); HeldRequestProtocol.reset() }
        let credentials = MemoryCredentials(); credentials.value = nil
        let account = GitHubAccountStore(keychain: credentials, session: session)
        let store = ReadmeStore(account: account, session: session)
        let first = Task { await store.load(StoreTests.repo) }
        let firstRequest = try await HeldRequestProtocol.next()
        let other = Repository(fullName: "owner/other", description: "", language: nil, stars: nil, forks: nil)
        let second = Task { await store.load(other) }
        let secondRequest = try await HeldRequestProtocol.next()
        secondRequest.reply(status: 200, data: response("<h1>Second</h1>"), headers: ["Content-Type": "text/html"])
        await second.value
        firstRequest.reply(status: 200, data: response("<h1>First</h1>"), headers: ["Content-Type": "text/html"])
        await first.value
        precondition(store.document?.html.contains("Second") == true)
        let pending = Task { await store.load(other, refresh: true) }
        let pendingRequest = try await HeldRequestProtocol.next()
        account.logout()
        pendingRequest.reply(status: 200, data: response("<h1>Old account</h1>"), headers: ["Content-Type": "text/html"])
        await pending.value
        precondition(store.document == nil && !store.isLoading)
    }
}
