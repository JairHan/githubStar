import Foundation

struct GitHubOAuthClient {
    var session: URLSession = .shared
    func requestCode(clientID: String) async throws -> DeviceAuthorization {
        let data = try await post(path: "/login/device/code", fields: ["client_id": clientID, "scope": "public_repo"])
        if let result = try? JSONDecoder().decode(OAuthTokenResponse.self, from: data), let error = result.error { throw failure(error) }
        return try JSONDecoder().decode(DeviceAuthorization.self, from: data)
    }
    func poll(clientID: String, code: DeviceAuthorization) async throws -> GitHubCredential {
        let deadline = Date().addingTimeInterval(Double(code.expires_in))
        var interval = max(1, code.interval)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            let data = try await post(path: "/login/oauth/access_token", fields: ["client_id": clientID, "device_code": code.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            if let credential = response.credential {
                let scopes = Set((response.scope ?? "").split { $0 == "," || $0 == " " }.map(String.init))
                guard scopes.contains("public_repo") || scopes.contains("repo") else { throw GitHubError.message("未授予 Star 所需权限，请重新登录并完成授权。") }
                return credential
            }
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            default: throw failure(response.error ?? "unknown")
            }
        }
        throw failure("expired_token")
    }
    private func post(path: String, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://github.com" + path)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GitHubStar-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw GitHubError.message("GitHub 授权请求失败，请稍后重试。") }
        return data
    }
    private func failure(_ code: String) -> GitHubError {
        switch code {
        case "access_denied": .message("已拒绝授权，可重新开始登录。")
        case "expired_token": .message("验证码已过期，请重新开始登录。")
        case "incorrect_client_credentials": .message("Client ID 无效，请检查 OAuth App 配置。")
        case "device_flow_disabled": .message("请在 GitHub OAuth App 设置中启用 Device Flow。")
        default: .message("GitHub 授权未完成，请检查应用配置后重试。")
        }
    }
}
