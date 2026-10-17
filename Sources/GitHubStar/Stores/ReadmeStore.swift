import SwiftUI
import Combine

@MainActor
final class ReadmeStore: ObservableObject {
    @Published private(set) var document: ReadmeDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var isMissing = false
    private let account: GitHubAccountStore
    private let session: URLSession
    private var generation = UUID()
    private var subscription: AnyCancellable?
    private var cache: [String: (date: Date, document: ReadmeDocument)] = [:]

    init(account: GitHubAccountStore, session: URLSession = .shared) {
        self.account = account; self.session = session
        subscription = account.$sessionID.dropFirst().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }
    private func reset() {
        generation = UUID(); document = nil; cache = [:]
        isLoading = false; error = nil; isMissing = false
    }
    func load(_ repo: Repository, refresh: Bool = false) async {
        generation = UUID()
        let request = generation, accountSession = account.sessionID, key = repo.id.lowercased()
        document = nil; error = nil; isMissing = false; isLoading = false
        if !refresh, let cached = cache[key], Date().timeIntervalSince(cached.date) < 300 {
            document = cached.document; return
        }
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await GitHubClient(token: account.accessToken, session: session).readme(fullName: repo.fullName)
            try Task.checkCancellation()
            guard request == generation, accountSession == account.sessionID else { return }
            document = result
            if cache.count >= 20, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache[oldest] = nil }
            cache[key] = (Date(), result)
        } catch {
            guard request == generation, accountSession == account.sessionID, !Task.isCancelled else { return }
            if case GitHubError.notFound = error { isMissing = true }
            else { self.error = error.localizedDescription }
            account.handleUnauthorized(error, session: accountSession)
        }
    }
}
