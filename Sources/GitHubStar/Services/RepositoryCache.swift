import Foundation

actor RepositoryCache {
    struct Snapshot: Codable, Sendable {
        let items: [Repository]
        let total: Int
        let date: Date
        var incomplete: Bool? = nil
    }
    private let directory: URL
    private let lifetime: TimeInterval = 7 * 86400
    init(directory: URL) { self.directory = directory }

    func snapshot(for key: String, now: Date = Date()) throws -> Snapshot? {
        guard let snapshot = try read()[key], now.timeIntervalSince(snapshot.date) < lifetime else { return nil }
        return snapshot
    }
    func save(_ snapshot: Snapshot, for key: String, now: Date = Date()) throws {
        var snapshots = try read().filter { now.timeIntervalSince($0.value.date) < lifetime }
        snapshots[key] = snapshot
        let newest = snapshots.sorted { $0.value.date > $1.value.date }.prefix(80)
        snapshots = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshots).write(to: directory.appendingPathComponent("cache.json"), options: .atomic)
    }
    private func read() throws -> [String: Snapshot] {
        let url = directory.appendingPathComponent("cache.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        // A damaged cache can be replaced by the next successful network response.
        return (try? JSONDecoder().decode([String: Snapshot].self, from: data)) ?? [:]
    }
}
