import Foundation

enum TrendingParser {
    static func matches(_ pattern: String, _ input: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = input as NSString
        return regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }
    static func clean(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a,b) in [("&amp;","&"),("&quot;","\""),("&#39;","'"),("&lt;","<"),("&gt;",">"),("&nbsp;"," ")] { s = s.replacingOccurrences(of: a, with: b) }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func parse(_ html: String, period: String) -> [Repository] {
        matches("<article[^>]*class=\"[^\"]*Box-row[^\"]*\"[^>]*>(.*?)</article>", html).compactMap { block in
            guard let name = matches("href=\"/([^\"]+)/stargazers\"", block).first,
                  name.split(separator: "/").count == 2 else { return nil }
            func count(_ pattern: String) -> Int { Int(clean(matches(pattern, block).first ?? "").replacingOccurrences(of: ",", with: "")) ?? 0 }
            let gain = count(period == "day" ? "([0-9,]+) stars? today" : "([0-9,]+) stars? this \(period)")
            return Repository(fullName: name, description: clean(matches("<p[^>]*>(.*?)</p>", block).first ?? ""), language: matches("itemprop=\"programmingLanguage\"[^>]*>(.*?)</span>", block).first.map(clean), stars: count("href=\"/[^\"]+/stargazers\"[^>]*>(.*?)</a>"), forks: count("href=\"/[^\"]+/forks\"[^>]*>(.*?)</a>"), gain: gain, period: period)
        }
    }
}
