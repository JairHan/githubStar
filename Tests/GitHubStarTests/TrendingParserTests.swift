import Foundation

struct TrendingParserTests {
    static func realPageFixture() throws {
        let html = try String(contentsOfFile: "Tests/Fixtures/trending-weekly.html", encoding: .utf8)
        let repos = try TrendingParser.validatedParse(html, period: "week")
        precondition(repos.count == 2)
        precondition(repos.allSatisfy { ($0.stars ?? 0) > 0 && ($0.gain ?? 0) > 0 && $0.forks != nil })
        let changed = html.replacingOccurrences(of: " stars this week", with: " growth this week")
        let missingGains = try TrendingParser.validatedParse(changed, period: "week")
        precondition(missingGains.allSatisfy { $0.gain == nil })
        let malformed = html.replacingOccurrences(of: "/stargazers", with: "/changed-total-path")
        do { _ = try TrendingParser.validatedParse(malformed, period: "week"); preconditionFailure("Changed layout must fail") }
        catch GitHubError.message { }
        print("PASS: captured real Trending HTML and partial layout changes")
    }
    static func weeklyStatsAndEntities() {
        let html = """
        <article class="Box-row"><p>Hello &amp; Swift</p>
        <span itemprop="programmingLanguage">Swift</span>
        <a href="/apple/swift/stargazers"><svg><path /></svg> 12,345 </a>
        <a href="/apple/swift/forks"><svg></svg> 1,200 </a>
        <span><svg></svg> 678 stars this week</span></article>
        """
        let repos = TrendingParser.parse(html, period: "week")
        precondition(repos.count == 1)
        precondition(repos.first?.fullName == "apple/swift")
        precondition(repos.first?.description == "Hello & Swift")
        precondition(repos.first?.stars == 12345)
        precondition(repos.first?.forks == 1200)
        precondition(repos.first?.gain == 678)
        precondition(repos.first?.period == "week")
    }
    static func rejectsNonRepositoryHTML() {
        precondition(TrendingParser.parse("<article class=\"Box-row\">Sign in</article>", period: "week").isEmpty)
    }
    static func dailyGainIsSeparateFromTotal() {
        let html = "<article class=\"Box-row\"><a href=\"/a/b/stargazers\">10,000</a><span>25 stars today</span></article>"
        let repo = TrendingParser.parse(html, period: "day").first
        precondition(repo?.gain == 25)
        precondition(repo?.stars == 10000)
        precondition(repo?.forks == nil)
        let missing = "<article class=\"Box-row\"><a href=\"/a/b/stargazers\">unexpected</a></article>"
        precondition(TrendingParser.parse(missing, period: "week").first?.stars == nil)
        precondition(TrendingParser.parse(missing, period: "week").first?.gain == nil)
        do { _ = try TrendingParser.validatedParse(missing, period: "week"); preconditionFailure("Invalid total must fail") }
        catch { }
        let zero = "<article class=\"Box-row\"><a href=\"/a/b/stargazers\">0</a><span>0 stars today</span></article>"
        precondition(TrendingParser.parse(zero, period: "day").first?.gain == 0)
    }
}
