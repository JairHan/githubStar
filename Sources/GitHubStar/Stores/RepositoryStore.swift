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
    @Published private(set) var starErrorID: String?
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
    @Published private(set) var isShowingCached = false
    @Published private(set) var cacheWarning: String?
    private let session: URLSession
    private var client: GitHubClient { GitHubClient(token: account.accessToken, session: session) }
    private let cache: RepositoryCache
    private var displayedCacheKey: String?
    private var generation = UUID()
    var key: String { "\(feed.rawValue)|\(feed == .saved ? "" : language)|\(feed == .search ? submittedQuery : "")|\(refreshID)" }
    var cacheKey: String { "\(feed.rawValue)|\(language)|\(feed == .search ? submittedQuery : "")" }
    var canLoadMore: Bool { if feed == .saved { return starsHasMore }; return (feed == .allTime || feed == .search) && page * 30 < min(total, 1000) && !items.isEmpty }
    var selected: Repository? { items.first { $0.id == selectedID } }
    init(account: GitHubAccountStore, session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.account = account
        self.session = session
        cache = RepositoryCache(directory: cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GitHubStar", isDirectory: true))
        accountSubscription = account.$sessionID.dropFirst().sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.generation = UUID()
                self.starredRepos = []; self.starStates = [:]; self.changingStars = []; self.checkingStars = [:]
                self.starError = nil; self.starErrorID = nil; self.starsHasMore = false; self.isLoading = false
                self.items = []; self.selectedID = nil; self.updatedAt = nil
                self.displayedCacheKey = nil; self.isShowingCached = false; self.incomplete = false
                self.total = 0; self.page = 1; self.error = nil; self.cacheWarning = nil; self.starRevision = UUID()
                self.refreshID = UUID()
            }
        }
    }
    func submitSearch() {
        if feed == .saved { filterStars(); return }
        searchAll()
    }
    func searchAll() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        feed = .search
        refreshID = UUID()
    }
    func isSaved(_ repo: Repository) -> Bool { starStates[repo.id.lowercased()] == true }
    func starState(_ repo: Repository) -> Bool? { starStates[repo.id.lowercased()] }
    func starError(for repo: Repository) -> String? { starErrorID == repo.id.lowercased() ? starError : nil }
    func starActionTitle(_ repo: Repository) -> String {
        guard account.isSignedIn else { return "登录 GitHub 后 Star" }
        guard let state = starState(repo) else { return "查询 Star 状态" }
        return state ? "取消 Star" : "Star"
    }
    func starIsBusy(_ repo: Repository) -> Bool { changingStars.contains(repo.id.lowercased()) || checkingStars[repo.id.lowercased()] != nil }
    @discardableResult
    func requestStar(_ repo: Repository) -> Task<Void, Never>? {
        guard account.isSignedIn else { account.showsLogin = true; return nil }
        guard let state = starState(repo) else {
            return Task { await checkStar(repo) }
        }
        let desired = !state
        return Task { await setStar(repo, desired: desired) }
    }
    func checkStar(_ repo: Repository) async {
        guard let token = account.accessToken else { return }
        let id = repo.id.lowercased(), session = account.sessionID, request = UUID()
        guard !changingStars.contains(id) else { return }
        checkingStars[id] = request
        if starErrorID == id { starError = nil; starErrorID = nil }
        defer { if checkingStars[id] == request { checkingStars[id] = nil } }
        do {
            let value = try await GitHubClient(token: token, session: self.session).isStarred(repo)
            try Task.checkCancellation()
            guard session == account.sessionID, checkingStars[id] == request else { return }
            starStates[id] = value
        } catch {
            guard !Task.isCancelled, session == account.sessionID, checkingStars[id] == request else { return }
            starErrorID = id; starError = error.localizedDescription
            account.handleUnauthorized(error, session: session)
        }
    }
    private func setStar(_ repo: Repository, desired: Bool) async {
        let id = repo.id.lowercased(), session = account.sessionID
        guard !starIsBusy(repo) else { return }
        guard let token = account.accessToken else { account.showsLogin = true; starErrorID = id; starError = "登录已过期，请重新授权。"; return }
        changingStars.insert(id); starError = nil; starErrorID = nil
        defer { if session == account.sessionID { changingStars.remove(id) } }
        do {
            let authenticated = GitHubClient(token: token, session: self.session)
            // Read server state before changing it; the loaded library may be paginated.
            let current = try await authenticated.isStarred(repo)
            try Task.checkCancellation()
            guard session == account.sessionID else { return }
            if current != desired { try await authenticated.setStarred(repo, starred: desired) }
            try Task.checkCancellation()
            guard session == account.sessionID else { return }
            starStates[id] = desired
            starRevision = UUID()
            if !desired { starredRepos.removeAll { $0.id.lowercased() == id } }
            else if !starredRepos.contains(where: { $0.id.lowercased() == id }) { starredRepos.insert(repo, at: 0) }
            if feed == .saved { filterStars(); refreshID = UUID() }
        } catch {
            guard session == account.sessionID else { return }
            starErrorID = id; starError = error.localizedDescription
            account.handleUnauthorized(error, session: session)
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
        if !more { filterStars() }
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let nextPage = more ? page + 1 : 1
            let result = try await GitHubClient(token: token, session: self.session).starred(page: nextPage)
            try Task.checkCancellation()
            guard generation == requestGeneration, session == account.sessionID else { return }
            guard revision == starRevision else { if feed == .saved { refreshID = UUID() }; return }
            if !more {
                for repo in starredRepos where !changingStars.contains(repo.id.lowercased()) { starStates[repo.id.lowercased()] = nil }
                starredRepos = []
            }
            let existing = Set(starredRepos.map { $0.id.lowercased() })
            starredRepos += result.items.filter { !existing.contains($0.id.lowercased()) }
            for repo in result.items where !changingStars.contains(repo.id.lowercased()) { starStates[repo.id.lowercased()] = true }
            starsHasMore = result.hasMore; page = nextPage; updatedAt = Date()
            filterStars()
        } catch {
            guard !Task.isCancelled, generation == requestGeneration, session == account.sessionID else { return }
            self.error = error.localizedDescription
            account.handleUnauthorized(error, session: session)
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
        let requestSession = account.sessionID
        error = nil
        if requestFeed == .activity { displayedCacheKey = nil; items = []; selectedID = nil; isLoading = false; return }
        if requestFeed == .saved { displayedCacheKey = nil; incomplete = false; isShowingCached = false; await loadStars(more: more, generation: requestGeneration); return }
        if requestFeed == .search && requestQuery.isEmpty { displayedCacheKey = nil; incomplete = false; isShowingCached = false; items = []; total = 0; selectedID = nil; isLoading = false; updatedAt = nil; return }
        let requestToken = account.accessToken
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        if !more {
            cacheWarning = nil
            if displayedCacheKey != requestCacheKey {
                items = []; selectedID = nil; total = 0; page = 1; updatedAt = nil; incomplete = false; isShowingCached = false
                displayedCacheKey = requestCacheKey
            }
            if items.isEmpty {
                do {
                    let snapshot = try await cache.snapshot(for: requestCacheKey)
                    guard generation == requestGeneration, !Task.isCancelled else { return }
                    if let snapshot {
                        items = snapshot.items; total = snapshot.total; updatedAt = snapshot.date
                        incomplete = snapshot.incomplete ?? false; isShowingCached = true; reconcileSelection()
                    }
                } catch {
                    guard generation == requestGeneration, !Task.isCancelled else { return }
                    cacheWarning = "无法读取离线缓存：\(error.localizedDescription)"
                }
            }
        }
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
            isShowingCached = false
            reconcileSelection()
            if !more && (requestFeed == .daily || requestFeed == .weekly || requestToken == nil) {
                let snapshot = RepositoryCache.Snapshot(items: items, total: total, date: Date(), incomplete: result.incomplete)
                do { try await cache.save(snapshot, for: requestCacheKey) }
                catch {
                    guard generation == requestGeneration else { return }
                    cacheWarning = "本次数据未能保存为离线缓存：\(error.localizedDescription)"
                }
            }
        } catch is CancellationError { }
        catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            if !items.isEmpty { isShowingCached = true }
            self.error = (items.isEmpty ? "" : "当前显示上次数据。") + error.localizedDescription
            account.handleUnauthorized(error, session: requestSession)
        }
    }
}
