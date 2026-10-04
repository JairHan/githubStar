import Foundation

enum FeedNavigationPolicy {
    static let home = URL(string: "https://github.com/feed")!

    enum Destination: Equatable { case embedded, browser, blocked }

    static func destination(for url: URL) -> Destination {
        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http",
              url.host != nil, url.user == nil, url.password == nil else { return .blocked }
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
           url.port == nil || url.port == 443 { return .embedded }
        return .browser
    }
}
