import SwiftUI
import WebKit

struct GitHubFeedView: View {
    @ObservedObject var browser: FeedBrowserStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack).help("后退")
                Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward).help("前进")
                Button { browser.goHome() } label: { Label("动态首页", systemImage: "house") }
                Spacer()
                Text(browser.currentURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button { browser.openInBrowser() } label: { Label("在浏览器打开", systemImage: "arrow.up.right.square") }
            }.padding(12).background(.bar)
            HStack {
                Image(systemName: "person.crop.circle")
                Text("首次浏览动态，请在页面中登录 GitHub；之后会记住网页登录状态。")
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 8)
            if let error = browser.error {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                    Spacer()
                    Button("重试") { browser.reload() }
                }.font(.caption).padding(12).background(.orange.opacity(0.1))
            }
            ZStack(alignment: .top) {
                FeedWebView(webView: browser.webView)
                if browser.isLoading { ProgressView(value: browser.progress).progressViewStyle(.linear) }
            }
        }.onAppear { browser.start() }
    }
}

private struct FeedWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
