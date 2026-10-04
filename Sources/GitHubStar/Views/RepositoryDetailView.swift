import SwiftUI

struct RepositoryDetailView: View {
    let repo: Repository
    let saved: Bool
    let signedIn: Bool
    let busy: Bool
    let error: String?
    let onSave: () -> Void
    @ViewState private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "shippingbox").font(.system(size: 34, weight: .light)).foregroundStyle(.indigo).frame(width: 68, height: 68).background(.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 7) {
                    Text(repo.owner).font(.subheadline).foregroundStyle(.secondary)
                    Text(repo.name).font(.system(size: 28, weight: .bold)).textSelection(.enabled)
                    if let language = repo.language { Label(language, systemImage: "circle.fill").font(.caption).foregroundStyle(languageColor(language)) }
                }
                Text(repo.description.isEmpty ? "暂无项目描述" : repo.description).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                HStack(spacing: 10) {
                    metric("总 Star", value: repo.stars, icon: "star.fill", color: .orange)
                    metric("Fork", value: repo.forks, icon: "arrow.triangle.branch", color: .indigo)
                }
                if let gain = repo.gain {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(repo.period == "week" ? "本周新增 Star" : "今日新增 Star", systemImage: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(.secondary)
                        Text("+\(gain.formatted())").font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(.green)
                        Text("来自 GitHub Trending \(repo.period == "week" ? "周" : "日")榜，不代表全站所有仓库的涨星排名。").font(.caption2).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                if !repo.topics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("项目主题").font(.caption).foregroundStyle(.secondary)
                        Text(repo.topics.joined(separator: "  ·  ")).font(.caption).foregroundStyle(.indigo).textSelection(.enabled)
                    }
                }
                Divider()
                VStack(spacing: 10) {
                    Button { NSWorkspace.shared.open(repo.url) } label: { Label("在 GitHub 查看", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button(action: onSave) {
                        HStack {
                            if busy { ProgressView().controlSize(.small) }
                            Label(signedIn ? (saved ? "已 Star · 点击取消" : "Star 仓库") : "登录 GitHub 后 Star", systemImage: saved ? "star.fill" : "star")
                        }.frame(maxWidth: .infinity)
                    }.controlSize(.large).disabled(busy)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(repo.url.absoluteString, forType: .string); copied = true } label: { Label(copied ? "链接已复制" : "复制链接", systemImage: "link") }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
                }
                Text("Star 与取消 Star 将直接更新你的 GitHub 账号。").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 290).onChange(of: repo.id) { _, _ in copied = false }
    }
    private func metric(_ title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
