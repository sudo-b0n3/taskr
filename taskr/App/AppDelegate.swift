// taskr/taskr/AppDelegate.swift
import SwiftUI
import AppKit
import SwiftData
import Carbon

/// Custom NSPanel subclass that can become key window for keyboard navigation
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    
    override func cancelOperation(_ sender: Any?) {
        // Close panel when Escape is pressed
        close()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var menuPanel: NSPanel?
    private var panelClickMonitor: Any?
    private var panelLocalClickMonitor: Any?
    private var helpWindowController: NSWindowController?
    private var automationWindow: NSWindow?
    private weak var mainWindow: NSWindow?
    private var mainWindowObserver: NSObjectProtocol?

    var taskManager: TaskManager?
    var modelContainer: ModelContainer?
    var isRunningScreenshotAutomation: Bool = false

    // Track standalone window presence to auto-toggle activation policy
    private var standaloneWindowCount: Int = 0

    private var globalEventMonitor: Any?
    private var statusItemClickMonitor: Any?  // Intercepts status item clicks to control highlight
    private var hotkeyConfiguration: HotkeyConfiguration {
        HotkeyPreferences.load()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showDockIcon = UserDefaults.standard.bool(forKey: showDockIconPreferenceKey)
        setDockIconVisibility(show: showDockIcon)

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        let preferredIconName = UserDefaults.standard.string(forKey: menuBarIconPreferenceKey)
        let initialIcon = MenuBarIcon(rawValue: preferredIconName ?? "") ?? MenuBarIcon.defaultIcon
        updateStatusItemIcon(systemSymbolName: initialIcon.systemName)

        if statusItem?.button != nil {
            // Don't set action - we handle clicks via local event monitor
            // This allows us to control highlight state and prevent default behavior
            setupStatusItemClickMonitor()
        }
        
        var hotkeyInitiallyEnabled = UserDefaults.standard.bool(forKey: globalHotkeyEnabledPreferenceKey)
        if UserDefaults.standard.object(forKey: globalHotkeyEnabledPreferenceKey) == nil {
            hotkeyInitiallyEnabled = false
            UserDefaults.standard.set(hotkeyInitiallyEnabled, forKey: globalHotkeyEnabledPreferenceKey)
        }
        
        if hotkeyInitiallyEnabled {
            if !enableGlobalHotkey(true, showAlertIfNotGranted: false) {
                UserDefaults.standard.set(false, forKey: globalHotkeyEnabledPreferenceKey)
            }
        }

        scheduleScreenshotAutomationPresentationIfNeeded()
        
        // Close any auto-opened windows (SwiftUI WindowGroup opens by default)
        // Skip this when running screenshot automation since we want that window open
        if !isRunningScreenshotAutomation {
            DispatchQueue.main.async {
                for window in NSApp.windows where window.title == "Taskr" {
                    window.close()
                }
            }
        }
    }
    
    func setupPopoverAfterDependenciesSet() {
        guard let taskManager = self.taskManager, let modelContainer = self.modelContainer else {
            fatalError("TaskManager or ModelContainer not set in AppDelegate before setting up popover.")
        }
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 380, height: 450)
        popover?.behavior = .transient
        popover?.delegate = self
        popover?.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(taskManager)
                .environmentObject(taskManager.inputState)
                .environmentObject(taskManager.selectionManager)
                .modelContainer(modelContainer)
                .environmentObject(self)
        )
    }
    
    /// Sets up a local event monitor to intercept clicks on the status item.
    /// By returning `nil` from the handler, we prevent the default NSStatusBarButton behavior
    /// (which would reset the highlight on mouse-up), allowing us to control highlight manually.
    private func setupStatusItemClickMonitor() {
        statusItemClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem?.button,
                  let buttonWindow = button.window else { 
                return event 
            }
            
            // Check if the click is on the status item button
            if event.window === buttonWindow {
                let locationInButton = button.convert(event.locationInWindow, from: nil)
                if button.bounds.contains(locationInButton) {
                    // Check logic based on event type
                    if event.type == .leftMouseDown {
                        self.togglePopover()
                        return nil // Prevent default behavior
                    } else if event.type == .rightMouseDown {
                        // For right click, only close if open, otherwise ignore (or show menu if implemented later)
                        let isPopoverOpen = self.popover?.isShown == true
                        let isPanelOpen = self.menuPanel?.isVisible == true
                        
                        if isPopoverOpen || isPanelOpen {
                            // If open, close it (toggle handles closing logic correctly)
                            self.togglePopover()
                            return nil
                        }
                        // If closed, return event to let system handle it (e.g. context menu if any)
                        return event
                    }
                }
            }
            
            // Pass through events not on our button
            return event
        }
    }
    
    // MARK: - NSPopoverDelegate
    
    func popoverDidClose(_ notification: Notification) {
        // Remove highlight when popover closes
        statusItem?.button?.isHighlighted = false
    }

    @objc func togglePopover() {
        print("AppDelegate: togglePopover() called.")
        let style = currentPresentationStyle
        
        switch style {
        case .popover:
            togglePopoverPresentation()
        case .panel:
            togglePanelPresentation()
        }
    }
    
    // MARK: - Presentation Style Helpers
    
    private var currentPresentationStyle: MenuBarPresentationStyle {
        let raw = UserDefaults.standard.string(forKey: menuBarPresentationStylePreferenceKey) ?? ""
        return MenuBarPresentationStyle(rawValue: raw) ?? .defaultStyle
    }
    
    private func togglePopoverPresentation() {
        if popover == nil {
            if self.taskManager != nil && self.modelContainer != nil {
                setupPopoverAfterDependenciesSet()
            } else {
                print("Warning: Trying to toggle popover but dependencies not yet set.")
                return
            }
        }
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
                button.isHighlighted = false
            } else {
                // Close panel if open
                closePanelIfNeeded()
                
                let currentPolicy = NSApp.activationPolicy()
                if currentPolicy == .accessory {
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                popover?.show(
                    relativeTo: button.bounds,
                    of: button,
                    preferredEdge: .minY
                )
                popover?.contentViewController?.view.window?.isMovableByWindowBackground = false
                popover?.contentViewController?.view.window?.makeKey()
                
                // Set highlight AFTER popover is shown to avoid it being reset
                DispatchQueue.main.async { [weak self] in
                    self?.statusItem?.button?.isHighlighted = true
                }
            }
        }
    }
    
    private func togglePanelPresentation() {
        if let panel = menuPanel, panel.isVisible {
            closePanelIfNeeded()
        } else {
            // Close popover if open
            if popover?.isShown == true {
                popover?.performClose(nil)
            }
            showPanel()
        }
    }
    
    private func setupPanelIfNeeded() {
        guard menuPanel == nil else { return }
        guard let taskManager = self.taskManager, let modelContainer = self.modelContainer else {
            print("Warning: Trying to setup panel but dependencies not yet set.")
            return
        }
        
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 450),
            styleMask: [.fullSizeContentView, .borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        
        // Create a visual effect view with a mask image for rounded corners (Calendr approach)
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 450))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.maskImage = Self.roundedCornerMask(radius: 12)
        
        let hostingView = NSHostingController(
            rootView: ContentView()
                .environmentObject(taskManager)
                .environmentObject(taskManager.inputState)
                .environmentObject(taskManager.selectionManager)
                .modelContainer(modelContainer)
                .environmentObject(self)
        )
        
        // Embed SwiftUI view inside the visual effect view
        hostingView.view.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(hostingView.view)
        NSLayoutConstraint.activate([
            hostingView.view.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.view.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.view.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.view.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])
        
        panel.contentView = visualEffectView
        
        menuPanel = panel
    }
    
    /// Creates a stretchable mask image with rounded corners for the panel
    private static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let diameter = radius * 2
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
    
    private func showPanel() {
        setupPanelIfNeeded()
        guard let panel = menuPanel else { return }
        
        positionPanelBelowStatusItem()
        
        // Activate the app to ensure proper focus
        NSApp.activate(ignoringOtherApps: true)
        
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        
        // Highlight the status item button while panel is open
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.isHighlighted = true
        }
        
        // Add click-outside monitor
        addPanelClickMonitor()
    }
    
    private func positionPanelBelowStatusItem() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let panel = menuPanel else { return }
        
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        
        // Get user's alignment preference
        let alignmentRaw = UserDefaults.standard.string(forKey: panelAlignmentPreferenceKey) ?? ""
        let alignment = PanelAlignment(rawValue: alignmentRaw) ?? .center
        
        // Calculate X position based on alignment
        var panelX: CGFloat
        switch alignment {
        case .left:
            // Panel's left edge aligns with button's left edge
            panelX = screenRect.minX
        case .center:
            // Panel is centered below the button
            panelX = screenRect.midX - panelWidth / 2
        case .right:
            // Panel's right edge aligns with button's right edge
            panelX = screenRect.maxX - panelWidth
        }
        
        let panelY = screenRect.minY - panelHeight  // Touch the menu bar
        
        // Ensure panel stays on screen
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            // Clamp to left edge
            if panelX < screenFrame.minX {
                panelX = screenFrame.minX + 8
            }
            // Clamp to right edge
            if panelX + panelWidth > screenFrame.maxX {
                panelX = screenFrame.maxX - panelWidth - 8
            }
        }
        
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
    }
    
    private func addPanelClickMonitor() {
        // Remove existing monitors if any
        removePanelClickMonitor()
        
        panelClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.menuPanel, panel.isVisible else { return }
            
            // Check if click is outside the panel
            let clickLocation = event.locationInWindow
            let panelFrame = panel.frame
            
            // For global events, locationInWindow is in screen coordinates
            if !panelFrame.contains(clickLocation) {
                DispatchQueue.main.async {
                    self.closePanelIfNeeded()
                }
            }
        }
        
        // Also monitor local clicks to handle clicks on status item
        panelLocalClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.menuPanel, panel.isVisible else { return event }
            
            // Check if click is on the status item button (to toggle)
            if let button = self.statusItem?.button,
               let buttonWindow = button.window,
               event.window === buttonWindow {
                // Let the normal toggle logic handle it
                return event
            }
            
            // Check if click is outside the panel
            if event.window !== panel {
                DispatchQueue.main.async {
                    self.closePanelIfNeeded()
                }
            }
            
            return event
        }
    }
    
    private func removePanelClickMonitor() {
        if let monitor = panelClickMonitor {
            NSEvent.removeMonitor(monitor)
            panelClickMonitor = nil
        }
        if let monitor = panelLocalClickMonitor {
            NSEvent.removeMonitor(monitor)
            panelLocalClickMonitor = nil
        }
    }
    
    private func closePanelIfNeeded() {
        menuPanel?.orderOut(nil)
        removePanelClickMonitor()
        // Remove highlight from status item button
        statusItem?.button?.isHighlighted = false
    }
    
    /// Resets menu bar presentation, closing any open popover/panel.
    /// Called when the user changes the presentation style preference.
    func resetMenuBarPresentation() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
        closePanelIfNeeded()
    }

    func updateStatusItemIcon(systemSymbolName: String) {
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: systemSymbolName,
                accessibilityDescription: "Taskr"
            )
        }
    }

    func setDockIconVisibility(show: Bool) {
        // Respect auto-promotion: if any standalone window is open, keep as regular
        let effectiveShow = show || (standaloneWindowCount > 0)
        let currentPolicy = NSApp.activationPolicy()
        
        if effectiveShow {
            if currentPolicy != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
            if currentPolicy != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func showHelpWindow() {
        if let existing = helpWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        guard let manager = taskManager else {
            print("Warning: taskManager unavailable; cannot show help window.")
            return
        }

        let helpView = HelpView()
            .environmentObject(manager)
        let hosting = NSHostingController(rootView: helpView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Taskr Help"
        window.setContentSize(NSSize(width: 640, height: 720))
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()

        let controller = NSWindowController(window: window)
        helpWindowController = controller

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.helpWindowController?.window === window {
                self.helpWindowController = nil
            }
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerMainWindow(_ window: NSWindow) {
        if let existing = mainWindow, existing !== window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.close()
            return
        }

        guard mainWindow !== window else { return }
        mainWindow = window

        if let observer = mainWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        mainWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            if self.mainWindow === window {
                self.mainWindow = nil
            }
        }
    }

    func showMainWindow(openWindow: () -> Void) {
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func standaloneWindowAppeared() {
        standaloneWindowCount += 1
        // Promote regardless of preference while window exists
        setDockIconVisibility(show: true)
        // Bring app to front so menu bar reflects activation
        NSApp.activate(ignoringOtherApps: true)
    }

    func standaloneWindowDisappeared() {
        standaloneWindowCount = max(0, standaloneWindowCount - 1)
        // Respect user preference when last window closes
        let showDockIcon = UserDefaults.standard.bool(forKey: showDockIconPreferenceKey)
        setDockIconVisibility(show: showDockIcon)
    }

    @IBAction func copy(_ sender: Any?) {
        guard let manager = taskManager, !manager.selectedTaskIDs.isEmpty else { return }
        manager.copySelectedTasksToPasteboard()
    }

    @discardableResult
    func enableGlobalHotkey(_ enable: Bool, showAlertIfNotGranted: Bool = true) -> Bool {
        if enable {
            if globalEventMonitor != nil {
                print("AppDelegate: Hotkey monitor already active.")
                return true
            }
            print("AppDelegate: Attempting to enable global hotkey...")
            let configuration = hotkeyConfiguration
            print("AppDelegate: Using hotkey \(configuration.displayString)")

            // Only surface the accessibility prompt when the caller explicitly requests it
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options: NSDictionary = [promptKey: showAlertIfNotGranted]
            let accessEnabled = AXIsProcessTrustedWithOptions(options)
            print("AppDelegate: Accessibility access check result: \(accessEnabled)")

            if !accessEnabled {
                print("AppDelegate: Accessibility access is not enabled for hotkey.")
                if showAlertIfNotGranted {
                    DispatchQueue.main.async {
                        self.showAccessibilityAlert()
                    }
                }
                return false
            }

            print("AppDelegate: Registering global event monitor...")
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return }
                let activeConfiguration = self.hotkeyConfiguration
                
                let receivedKeyCode = event.keyCode
                let receivedDeviceIndependentModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                print("""
                    --- Hotkey Event Received ---
                    Expected KeyCode: \(activeConfiguration.keyCode), Received KeyCode: \(receivedKeyCode)
                    Expected Modifiers (raw): \(activeConfiguration.modifiers.rawValue), Received Modifiers (raw): \(receivedDeviceIndependentModifiers.rawValue)
                    Expected Modifiers (desc): \(activeConfiguration.modifiers), Received Modifiers (desc): \(receivedDeviceIndependentModifiers)
                    Is KeyCode Match: \(receivedKeyCode == activeConfiguration.keyCode)
                    Is Modifiers Match: \(receivedDeviceIndependentModifiers == activeConfiguration.modifiers)
                    --- End Hotkey Event ---
                    """)

                if receivedKeyCode == activeConfiguration.keyCode && receivedDeviceIndependentModifiers == activeConfiguration.modifiers {
                    print("AppDelegate: Global hotkey \(activeConfiguration.displayString) DETECTED!")
                    DispatchQueue.main.async {
                        print("AppDelegate: Calling togglePopover from hotkey.")
                        self.togglePopover()
                    }
                }
            }
            
            if globalEventMonitor != nil {
                print("AppDelegate: Global hotkey monitor registered successfully.")
                return true
            } else {
                print("AppDelegate: FAILED to register global hotkey monitor.")
                return false
            }

        } else {
            if let monitor = globalEventMonitor {
                NSEvent.removeMonitor(monitor)
                globalEventMonitor = nil
                print("AppDelegate: Global hotkey disabled and monitor removed.")
            } else {
                print("AppDelegate: Global hotkey was already disabled (no monitor to remove).")
            }
            return true
        }
    }

    func updateHotkeyConfiguration(_ configuration: HotkeyConfiguration) {
        HotkeyPreferences.save(configuration)
        let hotkeyEnabled = UserDefaults.standard.bool(forKey: globalHotkeyEnabledPreferenceKey)

        if globalEventMonitor != nil {
            _ = enableGlobalHotkey(false)
        }

        if hotkeyEnabled {
            _ = enableGlobalHotkey(true, showAlertIfNotGranted: true)
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Taskr needs Accessibility permissions to enable the global hotkey.\n\nPlease grant access in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("Application terminating.")
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    private func scheduleScreenshotAutomationPresentationIfNeeded() {
        guard isRunningScreenshotAutomation else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.presentAutomationScenes()
        }
    }

    private func presentAutomationScenes(attempt: Int = 0) {
        setDockIconVisibility(show: true)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title == "Taskr" }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else if attempt < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.presentAutomationScenes(attempt: attempt + 1)
            }
        }
    }

    func showAutomationWindowIfNeeded(manager: TaskManager, container: ModelContainer) {
        guard isRunningScreenshotAutomation else { return }
        if automationWindow != nil { return }

        let automationView = ContentView(isStandalone: true)
            .environmentObject(manager)
            .environmentObject(manager.selectionManager)
            .modelContainer(container)
            .environmentObject(self)

        let hosting = NSHostingController(rootView: automationView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Taskr"
        window.setContentSize(NSSize(width: 720, height: 560))
        window.isReleasedWhenClosed = false
        automationWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.automationWindow === window {
                self.automationWindow = nil
            }
        }

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
