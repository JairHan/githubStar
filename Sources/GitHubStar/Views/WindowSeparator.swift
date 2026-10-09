import SwiftUI

/// Content columns draw their own separator so its origin matches the split view.
struct WindowSeparator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SeparatorView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.titlebarSeparatorStyle = .none
    }

    private final class SeparatorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarSeparatorStyle = .none
        }
    }
}
