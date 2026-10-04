import Foundation

struct GitHubUser: Decodable, Equatable {
    let login: String
    let name: String?
}
struct GitHubCredential: Codable {
    let token: String
    let expiresAt: Date?
    var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
}
struct DeviceAuthorization: Decodable {
    let device_code: String
    let user_code: String
    let expires_in: Int
    let interval: Int
}
struct OAuthTokenResponse: Decodable {
    let access_token: String?
    let expires_in: Int?
    let scope: String?
    let error: String?
    var credential: GitHubCredential? {
        guard let token = access_token, !token.isEmpty else { return nil }
        return GitHubCredential(token: token, expiresAt: expires_in.map { Date().addingTimeInterval(Double($0)) })
    }
}
