import SwiftUI
import AppKit

/// An NSView wrapper that enables click-through for its SwiftUI content.
/// Uses an invisible button overlay to capture clicks even when window is inactive.
struct ClickThroughWrapper<Content: View>: NSViewRepresentable {
    let content: Content
    let onTap: () -> Void
    
    init(onTap: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onTap = onTap
        self.content = content()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    func makeNSView(context: Context) -> ClickThroughContainerView<Content> {
        ClickThroughContainerView(rootView: content, coordinator: context.coordinator)
    }
    
    func updateNSView(_ nsView: ClickThroughContainerView<Content>, context: Context) {
        nsView.hostingView.rootView = content
        context.coordinator.onTap = onTap
    }
    
    class Coordinator {
        var onTap: () -> Void
        
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
        
        @objc func handleClick(_ sender: Any?) {
            onTap()
        }
    }
}

/// Container that overlays an invisible click-through button on top of SwiftUI content
final class ClickThroughContainerView<Content: View>: NSView {
    let hostingView: NSHostingView<Content>
    private let clickButton: ClickThroughButton
    
    init(rootView: Content, coordinator: ClickThroughWrapper<Content>.Coordinator) {
        hostingView = NSHostingView(rootView: rootView)
        clickButton = ClickThroughButton()
        
        super.init(frame: .zero)
        
        // Add hosting view for visual content
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        
        // Add invisible button on top for click handling
        clickButton.translatesAutoresizingMaskIntoConstraints = false
        clickButton.isBordered = false
        clickButton.isTransparent = true
        clickButton.title = ""
        clickButton.target = coordinator
        clickButton.action = #selector(ClickThroughWrapper<Content>.Coordinator.handleClick(_:))
        addSubview(clickButton)
        
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            clickButton.topAnchor.constraint(equalTo: topAnchor),
            clickButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            clickButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            clickButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// Custom button that accepts first mouse click when window is inactive
final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}


