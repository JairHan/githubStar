import SwiftUI

@MainActor
final class RepositoryStore: ObservableObject {
    @Published var feed: Feed = .daily
    @Published var language = ""
    @Published var query = ""
    @Published var submittedQuery = ""
    @Published var items: [Repository] = []
    @Published var selectedID: String?
    @Published var favorites: [Repository] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var updatedAt: Date?
    @Published var total = 0
    @Published var page = 1
    @Published var incomplete = false
    @Published var refreshID = UUID()
    private let client = GitHubClient()
    private let directory: URL
    private var generation = UUID()
    var key: String { "\(feed.rawValue)|\(language)|\(submittedQuery)|\(refreshID)" }
    var cacheKey: String { "\(feed.rawValue)|\(language)|\(feed == .search ? submittedQuery : "")" }
    var canLoadMore: Bool { (feed == .allTime || feed == .search) && items.count < min(total, 1000) && !items.isEmpty }
    var selected: Repository? { items.first { $0.id == selectedID } }
    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GitHubStar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("favorites.json")), let saved = try? JSONDecoder().decode([Repository].self, from: data) { favorites = saved }
    }
    func submitSearch() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        feed = .search
        refreshID = UUID()
    }
    func isSaved(_ repo: Repository) -> Bool { favorites.contains { $0.id == repo.id } }
    func toggleSave(_ repo: Repository) {
        if isSaved(repo) { favorites.removeAll { $0.id == repo.id } } else { favorites.insert(repo, at: 0) }
        do { try JSONEncoder().encode(favorites).write(to: directory.appendingPathComponent("favorites.json"), options: .atomic) }
        catch { self.error = "收藏保存失败：\(error.localizedDescription)" }
        if feed == .saved { showFavorites() }
    }
    private func showFavorites() {
        items = favorites.filter { (language.isEmpty || $0.language == language) && (query.isEmpty || ($0.fullName + " " + $0.description).localizedCaseInsensitiveContains(query)) }
        total = items.count
        reconcileSelection()
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
        if requestFeed == .saved { isLoading = false; updatedAt = nil; showFavorites(); return }
        if requestFeed == .search && requestQuery.isEmpty { items = []; total = 0; selectedID = nil; isLoading = false; updatedAt = nil; return }
        if !more {
            items = []; total = 0; page = 1; updatedAt = nil
            if let snapshot = readCache()[requestCacheKey] { items = snapshot.items; total = snapshot.total; updatedAt = snapshot.date; reconcileSelection() }
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
            if !more {
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
