import SwiftUI

struct ReadmeView: View {
    @ObservedObject var store: ReadmeStore
    let repo: Repository
    @ViewState private var height: CGFloat = 300
    @ViewState private var renderingError: String?

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
                if let renderingError {
                    Text(renderingError).font(.caption).foregroundStyle(.orange)
                    Button("重试") { Task { await store.load(repo, refresh: true) } }
                } else {
                    ReadmeWebView(document: document, onHeight: { value in
                        guard store.document?.id == document.id, abs(height - value) > 1 else { return }
                        height = value
                    }, onError: { message in
                        guard store.document?.id == document.id else { return }
                        renderingError = message
                    }).frame(height: max(120, height))
                }
            } else if store.isMissing {
                Text("此仓库暂无可读取的 README。").font(.caption).foregroundStyle(.secondary)
            } else if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("重试") { Task { await store.load(repo, refresh: true) } }
            }
            Link("在 GitHub 查看完整 README", destination: store.document?.sourceURL ?? URL(string: repo.url.absoluteString + "#readme")!)
                .font(.caption)
        }
        .onChange(of: store.document?.id) { _, _ in height = 300; renderingError = nil }
    }
}
