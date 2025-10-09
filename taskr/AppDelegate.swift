// taskr/taskr/AppDelegate.swift
import SwiftUI
import AppKit
import SwiftData
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    private var helpWindowController: NSWindowController?
    private var automationWindow: NSWindow?

    var taskManager: TaskManager?
    var modelContainer: ModelContainer?
    var isRunningScreenshotAutomation: Bool = false

    // Track standalone window presence to auto-toggle activation policy
    private var standaloneWindowCount: Int = 0

    private var globalEventMonitor: Any?
    // Hotkey: Control (⌃) + Option (⌥) + N
    private let hotkeyCode = CGKeyCode(kVK_ANSI_N)
    private let hotkeyModifiers = NSEvent.ModifierFlags([.control, .option])

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showDockIcon = UserDefaults.standard.bool(forKey: showDockIconPreferenceKey)
        setDockIconVisibility(show: showDockIcon)

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        let preferredIconName = UserDefaults.standard.string(forKey: menuBarIconPreferenceKey)
        let initialIcon = MenuBarIcon(rawValue: preferredIconName ?? "") ?? MenuBarIcon.defaultIcon
        updateStatusItemIcon(systemSymbolName: initialIcon.systemName)

        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(togglePopover)
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
    }
    
    func setupPopoverAfterDependenciesSet() {
        guard let taskManager = self.taskManager, let modelContainer = self.modelContainer else {
            fatalError("TaskManager or ModelContainer not set in AppDelegate before setting up popover.")
        }
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 380, height: 450)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(taskManager)
                .modelContainer(modelContainer)
                .environmentObject(self)
        )
    }

    @objc func togglePopover() {
        print("AppDelegate: togglePopover() called.")
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
            } else {
                let currentPolicy = NSApp.activationPolicy()
                if currentPolicy == .accessory {
                    NSApp.activate(ignoringOtherApps: true)
                }
                popover?.show(
                    relativeTo: button.bounds,
                    of: button,
                    preferredEdge: .minY
                )
                popover?.contentViewController?.view.window?.makeKey()
            }
        }
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
        if effectiveShow {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func showHelpWindow() {
        if let existing = helpWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let helpView = HelpView()
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

    @discardableResult
    func enableGlobalHotkey(_ enable: Bool, showAlertIfNotGranted: Bool = true) -> Bool {
        if enable {
            if globalEventMonitor != nil {
                print("AppDelegate: Hotkey monitor already active.")
                return true
            }
            print("AppDelegate: Attempting to enable global hotkey...")

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
                
                let receivedKeyCode = event.keyCode
                let receivedDeviceIndependentModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                print("""
                    --- Hotkey Event Received ---
                    Expected KeyCode for 'N': \(self.hotkeyCode), Received KeyCode: \(receivedKeyCode)
                    Expected Modifiers (Control+Option) (raw): \(self.hotkeyModifiers.rawValue), Received Modifiers (raw): \(receivedDeviceIndependentModifiers.rawValue)
                    Expected Modifiers (desc): \(self.hotkeyModifiers), Received Modifiers (desc): \(receivedDeviceIndependentModifiers)
                    Is KeyCode Match: \(receivedKeyCode == self.hotkeyCode)
                    Is Modifiers Match: \(receivedDeviceIndependentModifiers == self.hotkeyModifiers)
                    --- End Hotkey Event ---
                    """)

                if receivedKeyCode == self.hotkeyCode && receivedDeviceIndependentModifiers == self.hotkeyModifiers {
                    print("AppDelegate: Global hotkey (Control+Option+N) DETECTED!")
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
