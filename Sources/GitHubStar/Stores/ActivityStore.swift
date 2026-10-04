import SwiftUI
import Combine

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var items: [GitHubEvent] = []
    @Published var selectedID: String?
    @Published var query = ""
    @Published var category: ActivityCategory = .all
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var hasMore = false
    @Published private(set) var selectedRepository: Repository?
    @Published private(set) var isLoadingRepository = false
    @Published private(set) var repositoryError: String?
    private let account: GitHubAccountStore
    private var subscription: AnyCancellable?
    private var page = 0
    private var generation = UUID()
    private var repositoryGeneration = UUID()
    private var repositories: [String: Repository] = [:]

    init(account: GitHubAccountStore) {
        self.account = account
        subscription = account.$sessionID.dropFirst().sink { [weak self] _ in self?.reset() }
    }
    var visibleItems: [GitHubEvent] {
        items.filter {
            (category == .all || $0.category == category) && (query.isEmpty ||
                ($0.actor.login + " " + $0.repo.name + " " + $0.summary + " " + ($0.detail ?? ""))
                    .localizedCaseInsensitiveContains(query))
        }
    }
    var selected: GitHubEvent? { visibleItems.first { $0.id == selectedID } }
    var detailKey: String { "\(selected?.repo.name ?? "")|\(account.sessionID)" }
    func reconcileSelection() {
        if !visibleItems.contains(where: { $0.id == selectedID }) { selectedID = visibleItems.first?.id }
    }
    private func reset() {
        generation = UUID(); repositoryGeneration = UUID()
        items = []; selectedID = nil; repositories = [:]; selectedRepository = nil
        error = nil; repositoryError = nil; updatedAt = nil; page = 0; hasMore = false
        isLoading = false; isLoadingRepository = false
    }
    func load(more: Bool = false) async {
        guard let user = account.user, let token = account.accessToken else { reset(); return }
        if more { guard !isLoading, hasMore else { return } }
        else { generation = UUID() }
        let request = generation, session = account.sessionID, nextPage = more ? page + 1 : 1
        isLoading = true; error = nil
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await GitHubClient(token: token).receivedEvents(login: user.login, page: nextPage)
            try Task.checkCancellation()
            guard request == generation, session == account.sessionID else { return }
            let previous = more ? items : []
            var ids = Set(previous.map(\.id))
            items = (previous + result.items.filter { ids.insert($0.id).inserted }).sorted { $0.created_at > $1.created_at }
            page = nextPage; hasMore = result.hasMore; updatedAt = Date()
            reconcileSelection()
        } catch {
            guard !Task.isCancelled, request == generation, session == account.sessionID else { return }
            self.error = error.localizedDescription
        }
    }
    func loadSelectedRepository() async {
        repositoryGeneration = UUID()
        let request = repositoryGeneration, session = account.sessionID
        selectedRepository = nil; repositoryError = nil; isLoadingRepository = false
        guard let event = selected, let token = account.accessToken else { return }
        let name = event.repo.name
        if let cached = repositories[name] { selectedRepository = cached; return }
        isLoadingRepository = true
        defer { if request == repositoryGeneration { isLoadingRepository = false } }
        do {
            let repo = try await GitHubClient(token: token).repository(fullName: name)
            try Task.checkCancellation()
            guard request == repositoryGeneration, session == account.sessionID, selected?.repo.name == name else { return }
            repositories[name] = repo; selectedRepository = repo
        } catch {
            guard !Task.isCancelled, request == repositoryGeneration, session == account.sessionID else { return }
            repositoryError = error.localizedDescription
        }
    }
}
