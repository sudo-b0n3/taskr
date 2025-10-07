// taskr/taskr/WindowConfigurator.swift
import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    let autosaveName: String
    let initialSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureIfPossible(view: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureIfPossible(view: nsView)
        }
    }

    private func configureIfPossible(view: NSView) {
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
    }
}
