import SwiftUI

struct ReadmeView: View {
    @ObservedObject var store: ReadmeStore
    let repo: Repository
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("README", systemImage: "doc.text").font(.headline)
                Spacer()
                if !store.isLoading {
                    Button { Task { await store.load(repo, refresh: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("重新加载 README").accessibilityLabel("重新加载 README")
                }
            }
            if store.isLoading { ProgressView("正在加载 README…").controlSize(.small) }
            else if let document = store.document {
                Text("文本预览 · 图片和完整排版请在 GitHub 查看").font(.caption2).foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(store.blocks) { block in
                        switch block.kind {
                        case .code:
                            ScrollView(.horizontal) {
                                Text(block.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(12)
                            }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        case .heading(let level):
                            Text(inline(block.text, baseURL: document.sourceURL)).font(level <= 2 ? .title3.bold() : .headline).textSelection(.enabled)
                        case .paragraph:
                            Text(inline(block.text, baseURL: document.sourceURL)).font(.callout).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if document.isTruncated { Text("README 较长，当前显示前 60,000 字符。").font(.caption).foregroundStyle(.secondary) }
                Link("在 GitHub 查看完整 README", destination: document.sourceURL).font(.caption)
            } else if store.isMissing {
                Text("此仓库暂无可读取的 README。").font(.caption).foregroundStyle(.secondary)
            } else if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("重试") { Task { await store.load(repo, refresh: true) } }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
    }
    private func inline(_ text: String, baseURL: URL) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace), baseURL: baseURL)) ?? AttributedString(text)
    }
}
