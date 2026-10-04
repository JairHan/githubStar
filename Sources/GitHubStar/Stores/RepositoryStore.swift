import SwiftUI
import Combine

@MainActor
final class RepositoryStore: ObservableObject {
    @Published var feed: Feed = .daily
    @Published var language = ""
    @Published var query = ""
    @Published var submittedQuery = ""
    @Published var items: [Repository] = []
    @Published var selectedID: String?
    @Published private(set) var starredRepos: [Repository] = []
    @Published private(set) var starStates: [String: Bool] = [:]
    @Published private(set) var changingStars: Set<String> = []
    @Published private(set) var checkingStars: [String: UUID] = [:]
    @Published private(set) var starError: String?
    private var starsHasMore = false
    private var starRevision = UUID()
    let account: GitHubAccountStore
    private var accountSubscription: AnyCancellable?
    @Published var isLoading = false
    @Published var error: String?
    @Published var updatedAt: Date?
    @Published var total = 0
    @Published var page = 1
    @Published var incomplete = false
    @Published var refreshID = UUID()
    private var client: GitHubClient { GitHubClient(token: account.accessToken) }
    private let directory: URL
    private var generation = UUID()
    var key: String { "\(feed.rawValue)|\(language)|\(submittedQuery)|\(refreshID)" }
    var cacheKey: String { "\(feed.rawValue)|\(language)|\(feed == .search ? submittedQuery : "")" }
    var canLoadMore: Bool { if feed == .saved { return starsHasMore }; return (feed == .allTime || feed == .search) && items.count < min(total, 1000) && !items.isEmpty }
    var selected: Repository? { items.first { $0.id == selectedID } }
    init(account: GitHubAccountStore) {
        self.account = account
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GitHubStar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        accountSubscription = account.$sessionID.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.generation = UUID()
                self.starredRepos = []; self.starStates = [:]; self.changingStars = []; self.checkingStars = [:]
                self.starError = nil; self.starsHasMore = false; self.isLoading = false
                self.items = []; self.selectedID = nil; self.updatedAt = nil
                self.refreshID = UUID()
            }
        }
    }
    func submitSearch() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        feed = .search
        refreshID = UUID()
    }
    func isSaved(_ repo: Repository) -> Bool { starStates[repo.id.lowercased()] == true }
    func starIsBusy(_ repo: Repository) -> Bool { changingStars.contains(repo.id.lowercased()) || checkingStars[repo.id.lowercased()] != nil }
    func requestStar(_ repo: Repository) {
        guard account.isSignedIn else { account.showsLogin = true; return }
        let desired = !isSaved(repo)
        Task { await setStar(repo, desired: desired) }
    }
    func checkStar(_ repo: Repository) async {
        guard let token = account.accessToken else { return }
        let id = repo.id.lowercased(), session = account.sessionID, request = UUID()
        guard !changingStars.contains(id) else { return }
        checkingStars[id] = request
        defer { if checkingStars[id] == request { checkingStars[id] = nil } }
        do {
            let value = try await GitHubClient(token: token).isStarred(repo)
            try Task.checkCancellation()
            guard session == account.sessionID, checkingStars[id] == request else { return }
            starStates[id] = value; starError = nil
        } catch {
            guard !Task.isCancelled, session == account.sessionID else { return }
            starError = error.localizedDescription
        }
    }
    private func setStar(_ repo: Repository, desired: Bool) async {
        let id = repo.id.lowercased(), session = account.sessionID
        guard !starIsBusy(repo) else { return }
        guard let token = account.accessToken else { account.showsLogin = true; starError = "登录已过期，请重新授权。"; return }
        changingStars.insert(id); starError = nil
        defer { if session == account.sessionID { changingStars.remove(id) } }
        do {
            let authenticated = GitHubClient(token: token)
            // Read server state before changing it; the loaded library may be paginated.
            let current = try await authenticated.isStarred(repo)
            guard session == account.sessionID else { return }
            if current != desired { try await authenticated.setStarred(repo, starred: desired) }
            guard session == account.sessionID else { return }
            starStates[id] = desired
            starRevision = UUID()
            if !desired { starredRepos.removeAll { $0.id.lowercased() == id } }
            else if !starredRepos.contains(where: { $0.id.lowercased() == id }) { starredRepos.insert(repo, at: 0) }
            if feed == .saved { filterStars(); refreshID = UUID() }
        } catch {
            guard session == account.sessionID else { return }
            starError = error.localizedDescription
        }
    }
    func filterStars() {
        guard feed == .saved else { return }
        items = starredRepos.filter { (language.isEmpty || $0.language == language) && (query.isEmpty || ($0.fullName + " " + $0.description).localizedCaseInsensitiveContains(query)) }
        total = items.count
        reconcileSelection()
    }
    private func loadStars(more: Bool, generation requestGeneration: UUID) async {
        guard let token = account.accessToken else {
            items = []; selectedID = nil; total = 0; starsHasMore = false; updatedAt = nil; isLoading = false
            if account.isSignedIn { error = "登录已过期，请重新授权。" }
            return
        }
        let session = account.sessionID, revision = starRevision
        if !more { items = []; selectedID = nil; total = 0; updatedAt = nil; starsHasMore = false; page = 1; filterStars() }
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let nextPage = more ? page + 1 : 1
            let result = try await GitHubClient(token: token).starred(page: nextPage)
            try Task.checkCancellation()
            guard generation == requestGeneration, session == account.sessionID else { return }
            guard revision == starRevision else { if feed == .saved { refreshID = UUID() }; return }
            if !more { starredRepos = [] }
            let existing = Set(starredRepos.map { $0.id.lowercased() })
            starredRepos += result.items.filter { !existing.contains($0.id.lowercased()) }
            for repo in result.items where !changingStars.contains(repo.id.lowercased()) { starStates[repo.id.lowercased()] = true }
            starsHasMore = result.hasMore; page = nextPage; updatedAt = Date()
            filterStars()
        } catch {
            guard !Task.isCancelled, generation == requestGeneration, session == account.sessionID else { return }
            self.error = error.localizedDescription
        }
    }
    private func reconcileSelection() {
        if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
    }
    func load(more: Bool = false) async {
        let requestGeneration: UUID
        if more { guard !isLoading, canLoadMore else { return }; requestGeneration = generation }
        else { generation = UUID(); requestGeneration = generation }
        let requestFeed = feed, requestLanguage = language, requestQuery = submittedQuery, requestCacheKey = cacheKey
        error = nil
        if requestFeed == .saved { await loadStars(more: more, generation: requestGeneration); return }
        if requestFeed == .search && requestQuery.isEmpty { items = []; total = 0; selectedID = nil; isLoading = false; updatedAt = nil; return }
        if !more {
            items = []; total = 0; page = 1; updatedAt = nil
            if account.accessToken == nil, let snapshot = readCache()[requestCacheKey] { items = snapshot.items; total = snapshot.total; updatedAt = snapshot.date; reconcileSelection() }
        }
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let nextPage = more ? page + 1 : 1
            let result: SearchPage
            switch requestFeed {
            case .daily, .weekly:
                let repos = try await client.trending(weekly: requestFeed == .weekly, language: requestLanguage)
                result = SearchPage(items: repos, total: repos.count, incomplete: false)
            default: result = try await client.search(query: requestFeed == .search ? requestQuery : "", language: requestLanguage, page: nextPage)
            }
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            if more {
                let ids = Set(items.map(\.id))
                items += result.items.filter { !ids.contains($0.id) }
            } else { items = result.items }
            page = nextPage; total = result.total; incomplete = result.incomplete; updatedAt = Date()
            reconcileSelection()
            if !more && account.accessToken == nil {
                var cache = readCache()
                cache[requestCacheKey] = Snapshot(items: items, total: total, date: updatedAt!)
                cache = cache.filter { Date().timeIntervalSince($0.value.date) < 7 * 86400 }
                if let data = try? JSONEncoder().encode(cache) { try? data.write(to: directory.appendingPathComponent("cache.json"), options: .atomic) }
            }
        } catch is CancellationError { }
        catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            self.error = (items.isEmpty ? "" : "当前显示上次缓存。") + error.localizedDescription
        }
    }
    private struct Snapshot: Codable { let items: [Repository]; let total: Int; let date: Date }
    private func readCache() -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("cache.json")) else { return [:] }
        return (try? JSONDecoder().decode([String: Snapshot].self, from: data)) ?? [:]
    }
}
