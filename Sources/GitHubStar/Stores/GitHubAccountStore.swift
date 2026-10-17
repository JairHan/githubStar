import SwiftUI

@MainActor
final class GitHubAccountStore: ObservableObject {
    @Published var developmentClientID: String = UserDefaults.standard.string(forKey: "githubOAuthClientID") ?? "" {
        didSet { UserDefaults.standard.set(developmentClientID, forKey: "githubOAuthClientID") }
    }
    @Published private(set) var user: GitHubUser?
    @Published private(set) var isBusy = false
    @Published private(set) var isRestoring = false
    @Published private(set) var userCode: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var sessionID = UUID()
    @Published var showsLogin = false
    private var credential: GitHubCredential?
    private let keychain: any CredentialStore
    private let session: URLSession
    private var loginTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var operation = UUID()
    private var didRestore = false
    var bundledClientID: String? { Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String }
    var clientID: String { GitHubOAuthConfiguration.clientID(bundled: bundledClientID, developmentOverride: developmentClientID) }
    var hasBundledClientID: Bool { !(bundledClientID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    init(keychain: any CredentialStore = KeychainCredentialStore(), session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }
    var isSignedIn: Bool { user != nil && accessToken != nil }
    var accessToken: String? { credential?.isExpired == false ? credential?.token : nil }
    var canRetryRestore: Bool { !didRestore && !isRestoring && !isBusy }
    func restore() async {
        guard !didRestore, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        let current = operation
        do {
            guard let saved = try keychain.read() else { didRestore = true; return }
            if saved.isExpired { invalidateSession(); return }
            let profile = try await GitHubClient(token: saved.token, session: session).currentUser()
            try Task.checkCancellation()
            guard current == operation else { return }
            didRestore = true; error = nil
            credential = saved; user = profile; sessionID = UUID()
            scheduleExpiration()
        } catch {
            guard current == operation, !Task.isCancelled else { return }
            if case GitHubError.unauthorized = error { invalidateSession(); return }
            self.error = "恢复登录失败：\(error.localizedDescription)"
        }
    }
    func handleUnauthorized(_ failure: Error, session: UUID) {
        guard session == sessionID, case GitHubError.unauthorized = failure else { return }
        invalidateSession()
    }
    private func invalidateSession() {
        expiryTask?.cancel(); expiryTask = nil
        cancelLogin()
        credential = nil; user = nil; didRestore = true; sessionID = UUID()
        error = "GitHub 登录已失效，请重新授权。"
        do { try keychain.delete() }
        catch { self.error = "登录已失效；删除本机凭据失败：\(error.localizedDescription)" }
        showsLogin = true
    }
    private func scheduleExpiration() {
        expiryTask?.cancel()
        guard let expiresAt = credential?.expiresAt else { expiryTask = nil; return }
        let current = sessionID
        let delay = max(0, min(expiresAt.timeIntervalSinceNow, 86400))
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, current == self.sessionID else { return }
            if self.credential?.isExpired == true { self.invalidateSession() }
            else { self.scheduleExpiration() }
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
                let oauth = GitHubOAuthClient(session: session)
                let code = try await oauth.requestCode(clientID: id)
                try Task.checkCancellation()
                guard operation == current else { return }
                userCode = code.user_code
                expiresAt = Date().addingTimeInterval(Double(code.expires_in))
                NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!)
                let saved = try await oauth.poll(clientID: id, code: code)
                let profile = try await GitHubClient(token: saved.token, session: session).currentUser()
                try Task.checkCancellation()
                guard operation == current else { return }
                try keychain.save(saved)
                didRestore = true
                credential = saved; user = profile; sessionID = UUID(); showsLogin = false
                scheduleExpiration()
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
        didRestore = true
        expiryTask?.cancel(); expiryTask = nil
        credential = nil; user = nil; error = nil; sessionID = UUID()
    }
}
