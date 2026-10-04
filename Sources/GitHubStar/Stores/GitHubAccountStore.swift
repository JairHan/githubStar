import SwiftUI

@MainActor
final class GitHubAccountStore: ObservableObject {
    @Published var developmentClientID: String = UserDefaults.standard.string(forKey: "githubOAuthClientID") ?? "" {
        didSet { UserDefaults.standard.set(developmentClientID, forKey: "githubOAuthClientID") }
    }
    @Published private(set) var user: GitHubUser?
    @Published private(set) var isBusy = false
    @Published private(set) var userCode: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var sessionID = UUID()
    @Published var showsLogin = false
    private var credential: GitHubCredential?
    private let keychain = KeychainCredentialStore()
    private var loginTask: Task<Void, Never>?
    private var operation = UUID()
    private var didRestore = false
    var bundledClientID: String? { Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String }
    var clientID: String { GitHubOAuthConfiguration.clientID(bundled: bundledClientID, developmentOverride: developmentClientID) }
    var hasBundledClientID: Bool { !(bundledClientID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isSignedIn: Bool { user != nil && credential != nil }
    var accessToken: String? { credential?.isExpired == false ? credential?.token : nil }
    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        let current = operation
        do {
            guard let saved = try keychain.read() else { return }
            if saved.isExpired { error = "登录已过期，请重新授权。"; try keychain.delete(); return }
            let profile = try await GitHubClient(token: saved.token).currentUser()
            guard current == operation else { return }
            credential = saved; user = profile; sessionID = UUID()
        } catch {
            guard current == operation else { return }
            self.error = "恢复登录失败：\(error.localizedDescription)"
        }
    }
    func login() {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { error = "此构建尚未启用 GitHub 登录，请联系发行者获取已配置的版本。"; return }
        cancelLogin()
        let current = operation
        error = nil; isBusy = true
        loginTask = Task {
            defer { if operation == current { isBusy = false; userCode = nil; expiresAt = nil } }
            do {
                let oauth = GitHubOAuthClient()
                let code = try await oauth.requestCode(clientID: id)
                try Task.checkCancellation()
                guard operation == current else { return }
                userCode = code.user_code
                expiresAt = Date().addingTimeInterval(Double(code.expires_in))
                NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!)
                let saved = try await oauth.poll(clientID: id, code: code)
                let profile = try await GitHubClient(token: saved.token).currentUser()
                try Task.checkCancellation()
                guard operation == current else { return }
                try keychain.save(saved)
                credential = saved; user = profile; sessionID = UUID(); showsLogin = false
            } catch {
                guard operation == current, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func cancelLogin() {
        operation = UUID(); loginTask?.cancel(); loginTask = nil
        isBusy = false; userCode = nil; expiresAt = nil
    }
    func logout() {
        cancelLogin()
        do { try keychain.delete() }
        catch { self.error = error.localizedDescription; return }
        credential = nil; user = nil; error = nil; sessionID = UUID()
    }
}
