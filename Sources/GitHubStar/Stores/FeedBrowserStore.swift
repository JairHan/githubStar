import AppKit
import Combine
import WebKit

/// A window owns its browser so switching sidebar sections retains the page and scroll position.
@MainActor
final class FeedBrowserStore: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var currentURL = FeedNavigationPolicy.home
    @Published private(set) var error: String?

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var started = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            }
        ]
    }

    private func updateState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        currentURL = webView.url ?? FeedNavigationPolicy.home
    }

    func start() { guard !started else { return }; started = true; goHome() }
    func goHome() { error = nil; webView.load(URLRequest(url: FeedNavigationPolicy.home)) }
    func reload() { error = nil; if webView.url == nil { goHome() } else { webView.reload() } }
    func goBack() { error = nil; webView.goBack() }
    func goForward() { error = nil; webView.goForward() }
    func openInBrowser() { NSWorkspace.shared.open(currentURL) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        switch FeedNavigationPolicy.destination(for: url) {
        case .embedded:
            // Target-blank links reuse this window instead of creating a second browser.
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else { decisionHandler(.allow) }
        case .browser:
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            } else if navigationAction.targetFrame?.isMainFrame != false {
                error = "此页面需要跳转到外部网站，请在浏览器中继续。"
            }
        case .blocked:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { show(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { show(failure) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = "动态页面已停止响应，请刷新后重试。" }

    private func show(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        error = "无法加载 GitHub 页面：\(failure.localizedDescription)"
    }
}
