import SwiftUI
import Combine

@MainActor
final class ReadmeStore: ObservableObject {
    @Published private(set) var document: ReadmeDocument?
    @Published private(set) var blocks: [ReadmeBlock] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var isMissing = false
    private let account: GitHubAccountStore
    private let session: URLSession
    private var generation = UUID()
    private var subscription: AnyCancellable?
    private var cache: [String: (date: Date, document: ReadmeDocument, blocks: [ReadmeBlock])] = [:]

    init(account: GitHubAccountStore, session: URLSession = .shared) {
        self.account = account; self.session = session
        subscription = account.$sessionID.dropFirst().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }
    private func reset() {
        generation = UUID(); document = nil; blocks = []; cache = [:]
        isLoading = false; error = nil; isMissing = false
    }
    func load(_ repo: Repository, refresh: Bool = false) async {
        generation = UUID()
        let request = generation, accountSession = account.sessionID, key = repo.id.lowercased()
        document = nil; blocks = []; error = nil; isMissing = false; isLoading = false
        if !refresh, let cached = cache[key], Date().timeIntervalSince(cached.date) < 300 {
            document = cached.document; blocks = cached.blocks; return
        }
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await GitHubClient(token: account.accessToken, session: session).readme(fullName: repo.fullName)
            let parsed = await Task.detached { ReadmeBlock.parse(result.markdown) }.value
            try Task.checkCancellation()
            guard request == generation, accountSession == account.sessionID else { return }
            document = result; blocks = parsed
            if cache.count >= 20, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache[oldest] = nil }
            cache[key] = (Date(), result, parsed)
        } catch {
            guard request == generation, accountSession == account.sessionID, !Task.isCancelled else { return }
            if case GitHubError.notFound = error { isMissing = true }
            else { self.error = error.localizedDescription }
            account.handleUnauthorized(error, session: accountSession)
        }
    }
}
