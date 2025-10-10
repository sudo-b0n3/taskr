// taskr/taskr/WindowConfigurator.swift
import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    let autosaveName: String
    let initialSize: NSSize
    let palette: ThemePalette
    let frosted: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureIfPossible(view: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureIfPossible(view: nsView, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(palette: palette, frosted: frosted)
    }

    private func configureIfPossible(view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        // Set autosave so macOS remembers size/position between launches
        window.setFrameAutosaveName(autosaveName)

        // Only set an initial size the first time we configure
        let initializedKey = autosaveName + ".initialized"
        if !UserDefaults.standard.bool(forKey: initializedKey) {
            window.setContentSize(initialSize)
            UserDefaults.standard.set(true, forKey: initializedKey)
        }

        // Ensure the window is resizable and looks standard
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        coordinator.bind(to: window)
        coordinator.updateAppearance(palette: palette, frosted: frosted)
    }

    final class Coordinator {
        private(set) var palette: ThemePalette
        private(set) var frosted: Bool
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private weak var overlayView: NSView?

        init(palette: ThemePalette, frosted: Bool) {
            self.palette = palette
            self.frosted = frosted
        }

        func bind(to window: NSWindow) {
            guard self.window !== window else { return }
            teardown()
            self.window = window
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.applyAppearance()
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.applyAppearance()
                },
                center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { [weak self] _ in
                    self?.applyAppearance()
                },
                center.addObserver(forName: NSWindow.didResignMainNotification, object: window, queue: .main) { [weak self] _ in
                    self?.applyAppearance()
                },
                center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.applyAppearance()
                },
                center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.applyAppearance()
                }
            ]
            applyAppearance()
        }

        func updateAppearance(palette: ThemePalette, frosted: Bool) {
            self.palette = palette
            self.frosted = frosted
            applyAppearance()
        }

        private func applyAppearance() {
            guard let window else { return }
            window.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            let headerColor = frosted ? palette.headerBackground.withAlphaComponent(0.6) : palette.headerBackground
            window.backgroundColor = headerColor
            if let titlebarView = locateTitlebarView(in: window) {
                let overlay = ensureOverlay(in: titlebarView)
                overlay.layer?.backgroundColor = headerColor.cgColor
                overlay.layer?.zPosition = -1

                if titlebarView.layer == nil {
                    titlebarView.wantsLayer = true
                }
                titlebarView.layer?.backgroundColor = headerColor.cgColor

                // Reduce vibrancy by disabling material on any visual effect views we control.
                for visualEffect in titlebarView.subviews.compactMap({ $0 as? NSVisualEffectView }) {
                    visualEffect.state = frosted ? .active : .inactive
                    visualEffect.material = frosted ? .hudWindow : (palette.isDark ? .menu : .titlebar)
                }
            }
            window.invalidateShadow()
        }

        func teardown() {
            let center = NotificationCenter.default
            observers.forEach { center.removeObserver($0) }
            observers.removeAll()
            window = nil
        }

        deinit {
            teardown()
        }

        private func locateTitlebarView(in window: NSWindow) -> NSView? {
            guard let contentSuper = window.contentView?.superview else { return nil }
            var current: NSView? = contentSuper
            while let view = current {
                if NSStringFromClass(type(of: view)).contains("NSTitlebarView") {
                    return view
                }
                current = view.superview
            }
            return nil
        }

        private func ensureOverlay(in titlebarView: NSView) -> NSView {
            if let overlayView, overlayView.superview === titlebarView {
                return overlayView
            }
            let overlay = NSView(frame: titlebarView.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            let color = frosted ? palette.headerBackground.withAlphaComponent(0.6) : palette.headerBackground
            overlay.layer?.backgroundColor = color.cgColor
            titlebarView.addSubview(overlay, positioned: .below, relativeTo: nil)
            overlayView = overlay
            return overlay
        }
    }
}
