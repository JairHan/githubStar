import Foundation

struct TrendingParserTests {
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
    }
}
