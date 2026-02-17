import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var onWindowChange: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowChange: onWindowChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onWindowChange = context.coordinator.notifyWindowChange
        context.coordinator.notifyWindowChange(view.window)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trackingView = nsView as? TrackingView else { return }
        trackingView.onWindowChange = context.coordinator.notifyWindowChange
        context.coordinator.notifyWindowChange(trackingView.window)
    }

    final class Coordinator {
        private let onWindowChange: (NSWindow?) -> Void
        private weak var lastWindow: NSWindow?

        init(onWindowChange: @escaping (NSWindow?) -> Void) {
            self.onWindowChange = onWindowChange
        }

        func notifyWindowChange(_ window: NSWindow?) {
            if window == nil, lastWindow == nil {
                return
            }
            if lastWindow === window {
                return
            }
            lastWindow = window
            onWindowChange(window)
        }
    }

    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
