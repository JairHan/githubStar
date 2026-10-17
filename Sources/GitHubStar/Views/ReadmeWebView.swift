import SwiftUI
import WebKit

struct ReadmeWebView: NSViewRepresentable {
    let document: ReadmeDocument
    let onHeight: (CGFloat) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHeight: onHeight, onError: onError) }
    func makeNSView(context: Context) -> WKWebView { Self.makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeight = onHeight
        context.coordinator.onError = onError
        context.coordinator.load(document, in: webView)
    }
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "readmeEvents", contentWorld: .defaultClient)
    }
    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(coordinator, contentWorld: .defaultClient, name: "readmeEvents")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.underPageBackgroundColor = .clear
        return webView
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onHeight: (CGFloat) -> Void
        var onError: (String) -> Void
        private let openExternal: (URL) -> Void
        private var documentID: UUID?
        private var navigation: WKNavigation?
        private var renderingScript: String?
        private weak var webView: WKWebView?

        init(onHeight: @escaping (CGFloat) -> Void, onError: @escaping (String) -> Void,
             openExternal: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
            self.onHeight = onHeight; self.onError = onError; self.openExternal = openExternal
        }
        func load(_ document: ReadmeDocument, in webView: WKWebView) {
            guard documentID != document.id else { return }
            documentID = document.id; self.webView = webView
            do {
                let script = try ReadmeHTMLRenderer.script(for: document)
                renderingScript = script
                let controller = webView.configuration.userContentController
                controller.removeAllUserScripts()
                controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
                navigation = webView.loadHTMLString(ReadmeHTMLRenderer.page(for: document), baseURL: nil)
            } catch { onError("README 渲染失败：\(error.localizedDescription)") }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === self.navigation, let renderingScript else { return }
            let current = documentID
            webView.evaluateJavaScript(renderingScript, in: nil, in: .defaultClient) { [weak self] result in
                guard let self, current == self.documentID else { return }
                if case .failure(let error) = result { self.onError("README 布局失败：\(error.localizedDescription)") }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let values = message.body as? [String: Any],
                  values["id"] as? String == documentID?.uuidString else { return }
            if let height = values["height"] as? Double, height.isFinite, height > 0 {
                onHeight(CGFloat(min(height, 200_000)))
            }
            if let delta = values["wheel"] as? Double, delta.isFinite,
               let scroll = webView?.enclosingScrollView, let container = scroll.documentView {
                let clip = scroll.contentView
                let mode = values["wheelMode"] as? Int ?? 0
                let unit: CGFloat = mode == 1 ? 16 : (mode == 2 ? clip.bounds.height : 1)
                var bounds = clip.bounds
                bounds.origin.y += CGFloat(delta) * unit * (container.isFlipped ? 1 : -1)
                clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
                scroll.reflectScrolledClipView(clip)
            }
            if let offset = values["scroll"] as? Double, offset.isFinite, let webView,
               let scroll = webView.enclosingScrollView, let container = scroll.documentView {
                let point = webView.convert(NSPoint(x: 0, y: offset), to: container)
                container.scrollToVisible(NSRect(x: point.x, y: point.y, width: 1, height: 32))
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.navigationType == .linkActivated {
                if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { openExternal(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(url.absoluteString == "about:blank" ? .allow : .cancel) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error, for: navigation) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error, for: navigation) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onError("README 渲染进程已退出，请重新加载。") }
        private func report(_ error: Error, for navigation: WKNavigation?) {
            guard navigation === self.navigation, (error as NSError).code != NSURLErrorCancelled else { return }
            onError("README 渲染失败：\(error.localizedDescription)")
        }
    }
}
