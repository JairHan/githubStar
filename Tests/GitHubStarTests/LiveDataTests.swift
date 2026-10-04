import Foundation

@main
struct DataValidation {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        FeedNavigationPolicyTests.run()
        try await GitHubAuthenticationTests.run()
        TrendingParserTests.weeklyStatsAndEntities()
        TrendingParserTests.rejectsNonRepositoryHTML()
        TrendingParserTests.dailyGainIsSeparateFromTotal()
        print("PASS: weekly totals, HTML entities, malformed pages, daily gains")
        if let path = ProcessInfo.processInfo.environment["GITHUBSTAR_TRENDING_FIXTURE"] {
            let html = try String(contentsOfFile: path, encoding: .utf8)
            let repos = TrendingParser.parse(html, period: "week")
            precondition(repos.count > 5)
            precondition(repos.allSatisfy { $0.stars > 0 && ($0.gain ?? 0) > 0 })
            precondition(Set(repos.map(\.id)).count == repos.count)
            print("PASS: real weekly HTML, \(repos.count) repositories")
        }
        if let clientID = ProcessInfo.processInfo.environment["GITHUBSTAR_OAUTH_CHECK_CLIENT_ID"] {
            let code = try await GitHubOAuthClient().requestCode(clientID: clientID)
            precondition(code.user_code.count == 9 && code.user_code.contains("-"))
            precondition(code.expires_in > 0 && code.interval > 0)
            print("PASS: registered OAuth App accepts real Device Flow requests (no account authorization performed)")
        }
        if ProcessInfo.processInfo.environment["GITHUBSTAR_LIVE_TEST"] == "1" {
            let client = GitHubClient()
            let result = try await client.search(query: "repo:swiftlang/swift", language: "", page: 1)
            precondition(result.items.first?.fullName == "swiftlang/swift")
            precondition((result.items.first?.stars ?? 0) > 1000)
            let weekly = try await client.trending(weekly: true, language: "")
            precondition(weekly.count > 5)
            precondition(zip(weekly, weekly.dropFirst()).allSatisfy { ($0.gain ?? 0) >= ($1.gain ?? 0) })
            print("PASS: live search and weekly feed sorted by gained stars")
        }
    }
}
