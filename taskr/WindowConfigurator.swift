// taskr/taskr/WindowConfigurator.swift
import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    let autosaveName: String
    let initialSize: NSSize
    let palette: ThemePalette
    let frosted: Bool
    let frostOpacity: Double
    let usesSystemAppearance: Bool
    let allowBackgroundDrag: Bool
    var onWindowAvailable: ((NSWindow) -> Void)? = nil

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
        Coordinator(
            palette: palette,
            frosted: frosted,
            frostOpacity: frostOpacity,
            usesSystemAppearance: usesSystemAppearance,
            allowBackgroundDrag: allowBackgroundDrag
        )
    }

    private func configureIfPossible(view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        // Set autosave so macOS remembers size/position between launches
        window.setFrameAutosaveName(autosaveName)
        onWindowAvailable?(window)

        // Only set an initial size the first time we configure
        let initializedKey = autosaveName + ".initialized"
        if !UserDefaults.standard.bool(forKey: initializedKey) {
            window.setContentSize(initialSize)
            UserDefaults.standard.set(true, forKey: initializedKey)
        }

        // Ensure the window is resizable and looks standard
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = allowBackgroundDrag
        window.isOpaque = false
        coordinator.bind(to: window)
        coordinator.updateAppearance(
            palette: palette,
            frosted: frosted,
            frostOpacity: frostOpacity,
            usesSystemAppearance: usesSystemAppearance,
            allowBackgroundDrag: allowBackgroundDrag
        )
    }

    final class Coordinator {
        private(set) var palette: ThemePalette
        private(set) var frosted: Bool
        private(set) var frostOpacity: Double
        private(set) var usesSystemAppearance: Bool
        private(set) var allowBackgroundDrag: Bool
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private weak var overlayView: NSView?
        private weak var overlayTintView: NSView?

        init(palette: ThemePalette, frosted: Bool, frostOpacity: Double, usesSystemAppearance: Bool, allowBackgroundDrag: Bool) {
            self.palette = palette
            self.frosted = frosted
            self.frostOpacity = frostOpacity
            self.usesSystemAppearance = usesSystemAppearance
            self.allowBackgroundDrag = allowBackgroundDrag
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

        func updateAppearance(palette: ThemePalette, frosted: Bool, frostOpacity: Double, usesSystemAppearance: Bool, allowBackgroundDrag: Bool) {
            self.palette = palette
            self.frosted = frosted
            self.frostOpacity = frostOpacity
            self.usesSystemAppearance = usesSystemAppearance
            self.allowBackgroundDrag = allowBackgroundDrag
            applyAppearance()
        }

        private func applyAppearance() {
            guard let window else { return }
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unifiedCompact
            window.isMovableByWindowBackground = allowBackgroundDrag
            if usesSystemAppearance {
                window.appearance = nil
            } else {
                window.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            }
            let headerColor = frosted ? palette.headerBackground.withAlphaComponent(frostOpacity) : palette.headerBackground
            window.backgroundColor = headerColor
            if let titlebarView = locateTitlebarView(in: window) {
                let overlay = ensureOverlay(in: titlebarView)
                updateOverlay(overlay, with: headerColor)
                overlay.layer?.zPosition = -1

                if titlebarView.layer == nil {
                    titlebarView.wantsLayer = true
                }
                titlebarView.layer?.backgroundColor = headerColor.cgColor

                // Reduce vibrancy by disabling material on any visual effect views we control.
                for visualEffect in titlebarView.subviews.compactMap({ $0 as? NSVisualEffectView }).filter({ $0 !== overlay }) {
                    visualEffect.state = .active
                    visualEffect.material = frosted ? .hudWindow : .contentBackground
                    visualEffect.blendingMode = .withinWindow
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
            if let overlayView,
               overlayView.superview === titlebarView,
               frosted == (overlayView is NSVisualEffectView) {
                return overlayView
            }
            overlayView?.removeFromSuperview()
            overlayTintView?.removeFromSuperview()

            let overlay: NSView
            if frosted {
                let effectView = NSVisualEffectView(frame: titlebarView.bounds)
                effectView.autoresizingMask = [.width, .height]
                effectView.blendingMode = .withinWindow
                effectView.state = .active
                effectView.material = .hudWindow
                effectView.wantsLayer = true
                overlay = effectView
                overlayTintView = nil
            } else {
                let view = NSView(frame: titlebarView.bounds)
                view.autoresizingMask = [.width, .height]
                view.wantsLayer = true
                overlay = view
                overlayTintView = nil
            }

            titlebarView.addSubview(overlay, positioned: .below, relativeTo: nil)
            self.overlayView = overlay
            return overlay
        }

        private func updateOverlay(_ overlay: NSView, with headerColor: NSColor) {
            if frosted, let effectView = overlay as? NSVisualEffectView {
                effectView.material = .hudWindow
                effectView.state = .active
                effectView.blendingMode = .withinWindow
                if effectView.layer == nil {
                    effectView.wantsLayer = true
                }
                effectView.layer?.backgroundColor = NSColor.clear.cgColor

                let tintView = ensureTintView(in: effectView)
                tintView.layer?.backgroundColor = headerColor.cgColor
            } else {
                overlay.layer?.backgroundColor = headerColor.cgColor
                overlayTintView?.removeFromSuperview()
                overlayTintView = nil
            }
        }

        private func ensureTintView(in effectView: NSVisualEffectView) -> NSView {
            if let tintView = overlayTintView,
               tintView.superview === effectView {
                return tintView
            }
            let tintView = NSView(frame: effectView.bounds)
            tintView.autoresizingMask = [.width, .height]
            tintView.wantsLayer = true
            effectView.addSubview(tintView, positioned: .above, relativeTo: nil)
            overlayTintView = tintView
            return tintView
        }
    }
}
