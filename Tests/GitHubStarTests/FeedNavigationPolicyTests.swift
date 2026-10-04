import Foundation

enum FeedNavigationPolicyTests {
    static func run() {
        let cases: [(String, FeedNavigationPolicy.Destination)] = [
            ("https://github.com/feed", .embedded),
            ("https://github.com/login?return_to=%2Ffeed", .embedded),
            ("https://github.com:443/JairHan/githubStar", .embedded),
            ("https://github.com.evil.example/feed", .browser),
            ("https://evilgithub.com/feed", .browser),
            ("https://example.com", .browser),
            ("http://github.com/feed", .browser),
            ("https://github.com:8443/feed", .browser),
            ("https://user:password@github.com/feed", .blocked),
            ("file:///etc/passwd", .blocked),
            ("javascript:alert(1)", .blocked),
            ("customapp://open", .blocked)
        ]
        for (address, expected) in cases {
            precondition(FeedNavigationPolicy.destination(for: URL(string: address)!) == expected, address)
        }
        precondition(Feed.activity.title == "GitHub 动态")
        print("PASS: Feed navigation host, protocol, port and credential boundaries")
    }
}
