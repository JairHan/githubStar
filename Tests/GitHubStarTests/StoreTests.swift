import Foundation

final class MemoryCredentials: CredentialStore {
    var value: GitHubCredential? = GitHubCredential(token: "store-test-only", expiresAt: nil)
    var deleteCount = 0
    func read() throws -> GitHubCredential? { value }
    func save(_ credential: GitHubCredential) throws { value = credential }
    func delete() throws { value = nil; deleteCount += 1 }
}

@MainActor
enum StoreTests {
    static let profile = Data("{\"login\":\"test-user\"}".utf8)
    static let repo = Repository(fullName: "owner/project", description: "Project", language: "Swift", stars: 10, forks: 2)

    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let credentials = MemoryCredentials()
        let account = GitHubAccountStore(keychain: credentials, session: session)
        MockGitHubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await account.restore()
        precondition(!account.isSignedIn && account.canRetryRestore && credentials.value != nil)
        MockGitHubProtocol.handler = { _ in (200, profile) }
        await account.restore()
        precondition(account.isSignedIn && account.error == nil)
        let store = RepositoryStore(account: account, session: session)
        store.feed = .saved; store.query = "swift"; store.submitSearch()
        precondition(store.feed == .saved && store.submittedQuery.isEmpty)
        let filterKey = store.key
        store.language = "Swift"
        precondition(store.key == filterKey)
        store.searchAll()
        precondition(store.feed == .search && store.submittedQuery == "swift")
        precondition(store.starState(repo) == nil && store.starActionTitle(repo) == "查询 Star 状态")
        MockGitHubProtocol.handler = { request in
            precondition(request.httpMethod == "GET")
            return (204, Data())
        }
        await store.checkStar(repo)
        precondition(store.starState(repo) == true)
        let oldSession = account.sessionID
        MockGitHubProtocol.handler = { _ in (401, Data()) }
        await store.checkStar(repo)
        precondition(!account.isSignedIn && account.user == nil && account.showsLogin)
        precondition(credentials.value == nil && credentials.deleteCount == 1)
        precondition(store.starState(repo) == nil && store.items.isEmpty)
        account.handleUnauthorized(GitHubError.unauthorized, session: oldSession)
        precondition(credentials.deleteCount == 1)
        print("PASS: Store login recovery retry, unknown Star state, 401 invalidation and stale-session isolation")
        try await cacheTests(session: session)
        try await requestIsolationTests()
        try await starRaceTests()
        let expiring = MemoryCredentials()
        expiring.value = GitHubCredential(token: "expiry-test-only", expiresAt: Date().addingTimeInterval(0.5))
        let expires = GitHubAccountStore(keychain: expiring, session: session)
        MockGitHubProtocol.handler = { _ in (200, profile) }
        await expires.restore()
        precondition(expires.isSignedIn)
        for _ in 0..<200 {
            if expires.user == nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(expires.user == nil && expires.showsLogin && expiring.value == nil)
        print("PASS: local token expiry automatically clears the session and requests authorization")
    }

    static func cacheTests(session: URLSession) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = RepositoryCache(directory: directory)
        let now = Date()
        try await cache.save(.init(items: [repo], total: 1, date: now), for: "daily||", now: now)
        let expired = try await cache.snapshot(for: "daily||", now: now.addingTimeInterval(8 * 86400))
        precondition(expired == nil)
        let credentials = MemoryCredentials()
        let account = GitHubAccountStore(keychain: credentials, session: session)
        MockGitHubProtocol.handler = { _ in (200, profile) }
        await account.restore()
        let store = RepositoryStore(account: account, session: session, cacheDirectory: directory)
        MockGitHubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.load()
        precondition(store.items == [repo] && store.isShowingCached && store.error != nil)
        // Refresh must retain existing selection and content when the network fails.
        store.selectedID = repo.id
        await store.load()
        precondition(store.items == [repo] && store.selectedID == repo.id && !store.isLoading)
        store.feed = .weekly
        await store.load()
        precondition(store.items.isEmpty && store.selectedID == nil)
        // Authenticated search results are never written to the public cache.
        store.feed = .search; store.submittedQuery = "private-query"
        MockGitHubProtocol.handler = { _ in (200, searchResponse("owner/private")) }
        await store.load()
        let privateSnapshot = try await cache.snapshot(for: "search||private-query")
        precondition(privateSnapshot == nil)
        store.feed = .saved; store.query = ""; store.language = ""
        MockGitHubProtocol.handler = { _ in (200, Data("[\(repositoryJSON("owner/project"))]".utf8)) }
        await store.load()
        precondition(store.items == [repo] && store.starState(repo) == true)
        store.query = "no-match"; store.submitSearch()
        precondition(store.items.isEmpty && store.feed == .saved)
        print("PASS: logged-in offline cache, expiry, refresh selection, feed isolation and Stars filtering")
    }

    static func repositoryJSON(_ name: String) -> String {
        "{\"full_name\":\"\(name)\",\"description\":\"Project\",\"language\":\"Swift\",\"stargazers_count\":10,\"forks_count\":2}"
    }
    static func searchResponse(_ name: String) -> Data {
        Data("{\"items\":[\(repositoryJSON(name))],\"total_count\":1,\"incomplete_results\":false}".utf8)
    }

    static func requestIsolationTests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); HeldRequestProtocol.reset() }
        let credentials = MemoryCredentials(); credentials.value = nil
        let account = GitHubAccountStore(keychain: credentials, session: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RepositoryStore(account: account, session: session, cacheDirectory: directory)
        store.feed = .search; store.submittedQuery = "first"
        let first = Task { await store.load() }
        let firstRequest = try await HeldRequestProtocol.next()
        store.submittedQuery = "second"
        let second = Task { await store.load() }
        let secondRequest = try await HeldRequestProtocol.next()
        secondRequest.reply(status: 200, data: searchResponse("owner/second"))
        await second.value
        firstRequest.reply(status: 200, data: searchResponse("owner/first"))
        await first.value
        precondition(store.items.first?.fullName == "owner/second" && !store.isLoading)
        let pending = Task { await store.load() }
        let pendingRequest = try await HeldRequestProtocol.next()
        account.logout()
        pendingRequest.reply(status: 200, data: searchResponse("owner/old-account"))
        await pending.value
        precondition(store.items.isEmpty && store.selectedID == nil && !store.isLoading)
        print("PASS: out-of-order requests and logout while loading cannot restore stale results")
    }

    static func starRaceTests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); HeldRequestProtocol.reset() }
        let account = GitHubAccountStore(keychain: MemoryCredentials(), session: session)
        let restore = Task { await account.restore() }
        let profileRequest = try await HeldRequestProtocol.next()
        profileRequest.reply(status: 200, data: profile)
        await restore.value
        let store = RepositoryStore(account: account, session: session)
        let unknown = store.requestStar(repo)!
        let check = try await HeldRequestProtocol.next()
        precondition(check.request.httpMethod == "GET")
        check.reply(status: 204, data: Data())
        await unknown.value
        precondition(store.starState(repo) == true)
        store.feed = .saved
        let refresh = Task { await store.load() }
        let starsRequest = try await HeldRequestProtocol.next()
        let mutation = store.requestStar(repo)!
        let verify = try await HeldRequestProtocol.next()
        verify.reply(status: 204, data: Data())
        let remove = try await HeldRequestProtocol.next()
        precondition(remove.request.httpMethod == "DELETE")
        remove.reply(status: 204, data: Data())
        await mutation.value
        starsRequest.reply(status: 200, data: Data("[\(repositoryJSON(repo.id))]".utf8))
        await refresh.value
        precondition(store.starState(repo) == false && store.starredRepos.isEmpty && store.items.isEmpty)
        let failure = store.requestStar(repo)!
        let state = try await HeldRequestProtocol.next()
        state.reply(status: 404, data: Data())
        let write = try await HeldRequestProtocol.next()
        write.reply(status: 500, data: Data())
        await failure.value
        precondition(store.starState(repo) == false && store.starError(for: repo) != nil && !store.starIsBusy(repo))
        print("PASS: unknown Star only queries, stale Stars pages cannot undo Unstar, failed writes preserve state")
    }
}

final class HeldRequestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var pending: [HeldRequestProtocol] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.pending.append(self); Self.lock.unlock() }
    override func stopLoading() {}
    static func reset() { lock.lock(); pending = []; lock.unlock() }
    private static func take() -> HeldRequestProtocol? {
        lock.lock(); defer { lock.unlock() }
        return pending.isEmpty ? nil : pending.removeFirst()
    }
    static func next() async throws -> HeldRequestProtocol {
        for _ in 0..<300 {
            if let request = take() { return request }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw GitHubError.message("Timed out waiting for test request")
    }
    func reply(status: Int, data: Data, headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
