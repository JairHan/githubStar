import AppKit
import WebKit
import SwiftUI

@main
struct ReadmeRenderingValidation {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ValidationDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class ValidationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var coordinator: ReadmeWebView.Coordinator!
    private var height: CGFloat = 0
    private var renderingError: String?
    private var opened: [URL] = []
    private var checks: [String] = []
    private let output = URL(fileURLWithPath: CommandLine.arguments[1])

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = ReadmeWebView.Coordinator(onHeight: { [weak self] value in self?.height = value },
            onError: { [weak self] message in self?.renderingError = message },
            openExternal: { [weak self] url in self?.opened.append(url) })
        webView = ReadmeWebView.makeWebView(coordinator: coordinator)
        window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 640, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "README Rendering Validation"
        window.contentView = webView
        window.orderBack(nil)
        Task {
            do { try await run(); finish(passed: true) }
            catch { finish(passed: false, error: error.localizedDescription) }
        }
    }
    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "ReadmeRenderingValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private func evaluate(_ script: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                continuation.resume(with: result)
            }
        }
    }
    private func waitForHeight() async throws {
        for _ in 0..<500 {
            if height > 0 { return }
            if let renderingError { throw NSError(domain: "ReadmeRenderingValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: renderingError]) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let state = try await evaluate("JSON.stringify({url:location.href,ready:document.readyState,text:document.body?.innerText,handler:typeof window.webkit?.messageHandlers?.readmeEvents})")
        throw NSError(domain: "ReadmeRenderingValidation", code: 3, userInfo: [NSLocalizedDescriptionKey: "No WebKit height callback: \(state)"])
    }
    private func run() async throws {
        let html = """
        <h1 id="user-content-project">Project</h1><p><strong>Bold</strong> and <em>italic</em></p>
        <ul><li>First<ul><li>Nested</li></ul></li></ul>
        <table><thead><tr><th>Feature</th><th>Status</th></tr></thead><tbody><tr><td>HTML rendering</td><td>Supported</td></tr></tbody></table>
        <details><summary>Expand details</summary><p>First hidden paragraph</p><p>Second hidden paragraph</p></details>
        <pre><code>let value = &lt;sample&gt;</code></pre>
        <img id="badge" alt="Test image" width="32" height="32" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32'%3E%3Crect width='32' height='32' fill='%235c5ce0'/%3E%3C/svg%3E">
        <img id="relative-image" src="assets/logo.png"><picture><source id="relative-srcset" srcset="images/dark.png 1x, images/dark@2x.png 2x"></picture>
        <a id="relative" href="guide.md">Guide</a><a id="root" href="/docs/index.md">Root</a>
        <a id="external" href="https://example.com/readme">External</a><a id="unsafe" href="file:///tmp/readme">Blocked</a>
        <script>document.documentElement.setAttribute('data-script-ran', 'yes')</script>
        """
        let document = ReadmeDocument(html: html, repositoryURL: URL(string: "https://github.com/owner/project")!, path: "docs/README.md")
        coordinator.load(document, in: webView)
        try await waitForHeight()
        let data = try await evaluate("JSON.stringify({title:document.querySelector('h1').textContent,cells:document.querySelectorAll('td').length,nested:document.querySelectorAll('ul ul li').length,code:document.querySelector('code').textContent,relative:document.getElementById('relative').href,root:document.getElementById('root').href,image:document.getElementById('relative-image').src,srcset:document.getElementById('relative-srcset').srcset,script:document.documentElement.getAttribute('data-script-ran')})") as! String
        let result = try JSONSerialization.jsonObject(with: Data(data.utf8)) as! [String: Any]
        try require(result["title"] as? String == "Project" && result["cells"] as? Int == 2 && result["nested"] as? Int == 1, "HTML elements did not render")
        try require(result["code"] as? String == "let value = <sample>", "Code escaping was lost")
        try require(result["relative"] as? String == "https://github.com/owner/project/blob/HEAD/docs/guide.md", "Relative link base is wrong")
        try require(result["root"] as? String == "https://github.com/owner/project/blob/HEAD/docs/index.md", "Root relative link is wrong")
        try require(result["image"] as? String == "https://raw.githubusercontent.com/owner/project/HEAD/docs/assets/logo.png", "Relative image base is wrong")
        try require((result["srcset"] as? String)?.contains("https://raw.githubusercontent.com/owner/project/HEAD/docs/images/dark@2x.png 2x") == true, "Picture srcset was not resolved")
        try require(result["script"] is NSNull && !webView.configuration.defaultWebpagePreferences.allowsContentJavaScript, "README script executed")
        checks.append("Headings, nested lists, tables, code, relative links/images/srcset and disabled README scripts")
        var imageLoaded = false
        for _ in 0..<100 {
            imageLoaded = (try await evaluate("document.getElementById('badge').naturalWidth > 0")) as? Bool == true
            if imageLoaded { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(imageLoaded, "Inline image failed to render")
        let collapsed = height
        _ = try await evaluate("document.querySelector('details').open = true; 0")
        for _ in 0..<100 {
            if height > collapsed { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(height > collapsed, "Expanding details did not update the SwiftUI content height")
        _ = try await evaluate("document.getElementById('external').click(); 0")
        for _ in 0..<100 {
            if !opened.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(opened.first?.absoluteString == "https://example.com/readme", "External link was not forwarded to the browser")
        _ = try await evaluate("document.getElementById('unsafe').click(); 0")
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(opened.count == 1 && webView.url?.absoluteString == "about:blank", "Unsafe link navigated")
        checks.append("Image pixels loaded, details height changed, external link forwarded, file URL blocked")
        try await snapshot(name: "fixture.png")
        for argument in CommandLine.arguments.dropFirst(2) {
            let file = URL(fileURLWithPath: argument)
            let html = try String(contentsOf: file, encoding: .utf8)
            let doc = ReadmeDocument(html: html, repositoryURL: URL(string: "https://github.com/owner/project")!, path: ReadmeDocument.readmePath(in: html))
            height = 0; renderingError = nil
            coordinator.load(doc, in: webView)
            try await waitForHeight()
            let textLength = try await evaluate("document.getElementById('readme-content').innerText.length") as? Int ?? 0
            try require(textLength > 100 && height > 100, "Real README did not display: \(file.lastPathComponent)")
            try await snapshot(name: file.deletingPathExtension().lastPathComponent + ".png")
            checks.append("Real HTML rendered: \(file.lastPathComponent), text characters \(textLength), height \(height)")
        }
        try await scrollingTests()
    }
    private func findWebView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.findWebView(in: $0) }.first
    }
    private func scrollingTests() async throws {
        let html = (0..<100).map { "<p>Scrollable README paragraph \($0)</p>" }.joined()
            + "<pre id='wide-code'>" + String(repeating: "long code line ", count: 80) + "</pre>"
        let document = ReadmeDocument(html: html, repositoryURL: URL(string: "https://github.com/owner/project")!, path: "README.md")
        let hosting = NSHostingView(rootView: ScrollValidationView(document: document))
        window.contentView = hosting
        window.setContentSize(NSSize(width: 640, height: 600))
        window.orderFront(nil)
        var embedded: WKWebView?
        for _ in 0..<200 {
            hosting.layoutSubtreeIfNeeded()
            embedded = findWebView(in: hosting)
            if let embedded, embedded.frame.height > 2000 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let embedded, let outer = embedded.enclosingScrollView else {
            throw NSError(domain: "ReadmeRenderingValidation", code: 4, userInfo: [NSLocalizedDescriptionKey: "SwiftUI outer scroll view was not found"])
        }
        webView = embedded
        var ready = false
        for _ in 0..<200 {
            ready = (try await evaluate("typeof window.__githubStarReadmeID === 'string'")) as? Bool == true
            if ready { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(ready, "Embedded README did not finish loading")
        let before = outer.contentView.bounds.origin.y
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            embedded.evaluateJavaScript("document.querySelector('p').dispatchEvent(new WheelEvent('wheel', {deltaY: 120, bubbles: true, cancelable: true})); 0", in: nil, in: .defaultClient) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let after = outer.contentView.bounds.origin.y
        try require(after > before, "Wheel over README did not move outer SwiftUI ScrollView (\(before) -> \(after))")
        checks.append("WebKit wheel over embedded README scrolls outer SwiftUI detail: \(before) -> \(after)")
        let horizontalAllowed = try await evaluate("document.getElementById('wide-code').dispatchEvent(new WheelEvent('wheel', {deltaX: 100, bubbles: true, cancelable: true}))") as? Bool
        try await Task.sleep(nanoseconds: 50_000_000)
        try require(horizontalAllowed == true && outer.contentView.bounds.origin.y == after, "Horizontal code scrolling was intercepted")
        _ = try await evaluate("document.querySelector('p').dispatchEvent(new WheelEvent('wheel', {deltaY: -60, bubbles: true, cancelable: true})); 0")
        try await Task.sleep(nanoseconds: 50_000_000)
        let upward = outer.contentView.bounds.origin.y
        try require(upward < after, "Scrolling up over README did not move the detail page")
        _ = try await evaluate("document.querySelector('p').dispatchEvent(new WheelEvent('wheel', {deltaY: 2, deltaMode: 1, bubbles: true, cancelable: true})); 0")
        try await Task.sleep(nanoseconds: 50_000_000)
        try require(abs(outer.contentView.bounds.origin.y - upward - 32) < 1, "Line-based wheel delta was not converted")
        _ = try await evaluate("document.querySelector('p').dispatchEvent(new WheelEvent('wheel', {deltaY: -100000, bubbles: true, cancelable: true})); 0")
        try await Task.sleep(nanoseconds: 50_000_000)
        try require(outer.contentView.bounds.origin.y == 0, "Wheel scrolling exceeded the document boundary")
        checks.append("Upward wheel, line-based deltas, top boundary and horizontal code event passthrough")
    }
    private func snapshot(name: String) async throws {
        let image = try await webView.takeSnapshot(configuration: nil)
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try representation.representation(using: .png, properties: [:])!.write(to: output.deletingLastPathComponent().appendingPathComponent(name))
    }
    private func finish(passed: Bool, error: String? = nil) {
        let report: [String: Any] = ["passed": passed, "checks": checks, "error": error ?? ""]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output) }
        NSApp.terminate(nil)
    }
}

private struct ScrollValidationView: View {
    let document: ReadmeDocument
    @ViewState private var height: CGFloat = 4000
    var body: some View {
        ScrollView {
            VStack {
                Text("Repository details").frame(height: 100)
                ReadmeWebView(document: document, onHeight: { height = $0 }, onError: { _ in })
                    .frame(height: height)
            }.padding(20)
        }
    }
}
