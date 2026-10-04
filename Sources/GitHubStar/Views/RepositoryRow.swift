import SwiftUI

struct RepositoryRow: View {
    let repo: Repository
    let rank: Int
    let saved: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", rank)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 24).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(repo.fullName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 2)
                    if saved { Image(systemName: "star.fill").foregroundStyle(.indigo).font(.caption) }
                }
                Text(repo.description.isEmpty ? "这个项目暂时没有描述。" : repo.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 16) {
                    if let language = repo.language { HStack(spacing: 5) { Circle().fill(languageColor(language)).frame(width: 7, height: 7); Text(language) } }
                    Label(repo.stars.formatted(), systemImage: "star")
                    if let gain = repo.gain { Text("+\(gain.formatted()) / \(repo.period == "week" ? "周" : "日")").foregroundStyle(.green) }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12)
    }
}
func languageColor(_ language: String) -> Color {
    switch language {
    case "Swift": .orange
    case "Python": .blue
    case "TypeScript": .cyan
    case "JavaScript": .yellow
    case "Rust": .brown
    case "Go": .teal
    default: .purple
    }
}
