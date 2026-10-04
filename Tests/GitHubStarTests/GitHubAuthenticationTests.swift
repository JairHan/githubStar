import Foundation

final class MockGitHubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    static var responseHeaders: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let headers = Self.responseHeaders.merging(["Content-Type": "application/json"]) { first, _ in first }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
struct GitHubAuthenticationTests {
    static func run() async throws {
        precondition(GitHubOAuthConfiguration.clientID(bundled: "  PublisherClient  ", developmentOverride: "OldLocalClient") == "PublisherClient")
        precondition(GitHubOAuthConfiguration.clientID(bundled: nil, developmentOverride: " DevClient ") == "DevClient")
        precondition(GitHubOAuthConfiguration.clientID(bundled: "", developmentOverride: " ").isEmpty)
        print("PASS: bundled publisher OAuth ID takes precedence over local development settings")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let repo = Repository(fullName: "octocat/Hello-World", description: "", language: nil, stars: 10, forks: 2)
        let authenticated = GitHubClient(token: "test-token-only", session: session)
        var requests: [String] = []
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.host == "api.github.com")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-only")
            precondition(request.url?.path == "/user/starred/octocat/Hello-World")
            requests.append(request.httpMethod!)
            if request.httpMethod == "PUT" { precondition(request.value(forHTTPHeaderField: "Content-Length") == "0") }
            return (204, Data())
        }
        let starred = try await authenticated.isStarred(repo)
        precondition(starred)
        try await authenticated.setStarred(repo, starred: true)
        try await authenticated.setStarred(repo, starred: false)
        precondition(requests == ["GET", "PUT", "DELETE"])
        MockGitHubProtocol.handler = { _ in (404, Data()) }
        let unstarred = try await authenticated.isStarred(repo)
        precondition(!unstarred)
        do { try await authenticated.setStarred(repo, starred: true); preconditionFailure("Mutation 404 must fail") }
        catch GitHubError.message { }
        MockGitHubProtocol.handler = { _ in (401, Data()) }
        do { _ = try await authenticated.isStarred(repo); preconditionFailure("401 must fail") }
        catch GitHubError.unauthorized { }
        MockGitHubProtocol.handler = { _ in (403, Data()) }
        do { try await authenticated.setStarred(repo, starred: false); preconditionFailure("403 must fail") }
        catch GitHubError.message { }
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.path == "/user/starred")
            precondition(request.url?.query?.contains("page=2") == true)
            return (200, Data("[{\"full_name\":\"octocat/Hello-World\",\"description\":null,\"language\":null,\"stargazers_count\":10,\"forks_count\":2}]".utf8))
        }
        let page = try await authenticated.starred(page: 2)
        precondition(page.items.first?.fullName == repo.fullName && !page.hasMore)
        MockGitHubProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (200, Data())
        }
        _ = try await authenticated.fetch(URL(string: "https://github.com/trending")!)
        print("PASS: authenticated Star/Unstar, 404 state, failed writes, 401, paginated Stars, no token sent to Trending")
        let oauth = GitHubOAuthClient(session: session)
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.host == "github.com")
            precondition(request.url?.path == "/login/device/code")
            precondition(request.httpMethod == "POST")
            return (200, Data("{\"device_code\":\"test-device\",\"user_code\":\"ABCD-EFGH\",\"expires_in\":30,\"interval\":1}".utf8))
        }
        let code = try await oauth.requestCode(clientID: "test-client")
        precondition(code.user_code == "ABCD-EFGH")
        var polls = 0
        MockGitHubProtocol.handler = { request in
            precondition(request.url?.path == "/login/oauth/access_token")
            polls += 1
            if polls == 1 { return (200, Data("{\"error\":\"authorization_pending\"}".utf8)) }
            return (200, Data("{\"access_token\":\"test-oauth-only\",\"scope\":\"public_repo\",\"expires_in\":3600}".utf8))
        }
        let credential = try await oauth.poll(clientID: "test-client", code: code)
        precondition(credential.token == "test-oauth-only" && !credential.isExpired && polls == 2)
        MockGitHubProtocol.handler = { _ in (200, Data("{\"error\":\"access_denied\"}".utf8)) }
        do { _ = try await oauth.poll(clientID: "test-client", code: code); preconditionFailure("Rejected OAuth must fail") }
        catch GitHubError.message { }
        MockGitHubProtocol.handler = { _ in (200, Data("{\"access_token\":\"test-oauth-only\",\"scope\":\"read:user\"}".utf8)) }
        do { _ = try await oauth.poll(clientID: "test-client", code: code); preconditionFailure("Missing Star scope must fail") }
        catch GitHubError.message { }
        let task = Task { try await oauth.poll(clientID: "test-client", code: code) }
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Canceled OAuth must fail") }
        catch is CancellationError { }
        let expired = DeviceAuthorization(device_code: "test-device", user_code: "ABCD-EFGH", expires_in: 0, interval: 1)
        do { _ = try await oauth.poll(clientID: "test-client", code: expired); preconditionFailure("Expired code must fail") }
        catch GitHubError.message { }
        precondition(GitHubCredential(token: "test-only", expiresAt: Date().addingTimeInterval(-1)).isExpired)
        print("PASS: device authorization, pending polling, scope validation, denial, cancellation, code/token expiry")
    }
}
