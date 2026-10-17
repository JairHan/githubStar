import Foundation

@MainActor
enum ReadmeTests {
    static func response(_ text: String, source: String = "https://github.com/owner/project/blob/main/README.md") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["content": Data(text.utf8).base64EncodedString(), "encoding": "base64", "size": text.utf8.count, "html_url": source])
    }
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let credentials = MemoryCredentials(); credentials.value = nil
        let account = GitHubAccountStore(keychain: credentials, session: session)
        let store = ReadmeStore(account: account, session: session)
        let markdown = "# Project\r\n\r\n- First\r\n- [Guide](docs/guide.md)\r\n\r\n```swift\r\nlet x = 1\r\n```"
        var requests = 0
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.absoluteString == "https://api.github.com/repos/owner/project/readme")
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            requests += 1
            return (200, try response(markdown))
        }
        await store.load(StoreTests.repo)
        precondition(store.document?.markdown == markdown && store.blocks.count == 3 && !store.isLoading)
        if case .heading(1) = store.blocks[0].kind { } else { preconditionFailure("Missing heading") }
        if case .code = store.blocks[2].kind { } else { preconditionFailure("Missing code block") }
        precondition(store.blocks[2].text == "let x = 1")
        await store.load(StoreTests.repo)
        precondition(requests == 1)
        account.logout()
        precondition(store.document == nil && store.blocks.isEmpty)
        await store.load(StoreTests.repo)
        precondition(requests == 2)
        MockGitHubProtocol.handler = { _ in (404, Data()) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.isMissing && store.document == nil && store.error == nil)
        MockGitHubProtocol.handler = { _ in (200, try response(String(repeating: "字", count: 60_001))) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.document?.isTruncated == true && store.document?.markdown.count == 60_000)
        MockGitHubProtocol.handler = { _ in (200, try response("text", source: "file:///tmp/readme")) }
        await store.load(StoreTests.repo, refresh: true)
        precondition(store.error != nil && store.document == nil)
        try await selectionIsolation()
        print("PASS: README API, native blocks, CRLF, cache reset, missing file, size bounds, URL validation and selection isolation")
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
        secondRequest.reply(status: 200, data: try response("# Second"))
        await second.value
        firstRequest.reply(status: 200, data: try response("# First"))
        await first.value
        precondition(store.document?.markdown == "# Second")
        let pending = Task { await store.load(other, refresh: true) }
        let pendingRequest = try await HeldRequestProtocol.next()
        account.logout()
        pendingRequest.reply(status: 200, data: try response("# Old account"))
        await pending.value
        precondition(store.document == nil && !store.isLoading)
    }
}
