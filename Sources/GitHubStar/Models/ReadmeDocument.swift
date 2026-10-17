import Foundation

struct ReadmeDocument: Identifiable, Sendable {
    let id = UUID()
    let html: String
    let repositoryURL: URL
    let path: String

    var sourceURL: URL { repositoryURL.appendingPathComponent("blob/HEAD").appendingPathComponent(path) }
    var linkBaseURL: URL { sourceURL.deletingLastPathComponent().appendingPathComponent("") }
    var linkRootURL: URL { repositoryURL.appendingPathComponent("blob/HEAD/") }
    var imageRootURL: URL {
        URL(string: "https://raw.githubusercontent.com")!.appendingPathComponent(repositoryURL.path).appendingPathComponent("HEAD/")
    }
    var imageBaseURL: URL { imageRootURL.appendingPathComponent(path).deletingLastPathComponent().appendingPathComponent("") }

    static func readmePath(in html: String) -> String {
        let pattern = #"<div\b[^>]*\bid="readme"[^>]*\bdata-path="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return "README.md" }
        let path = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
        guard !path.hasPrefix("/"), path.split(separator: "/").allSatisfy({ $0 != ".." && $0 != "." }),
              !path.contains(":") else { return "README.md" }
        return path
    }
}
