import Foundation

enum GitHubOAuthConfiguration {
    static func clientID(bundled: String?, developmentOverride: String) -> String {
        let embedded = (bundled ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !embedded.isEmpty { return embedded }
        return developmentOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
