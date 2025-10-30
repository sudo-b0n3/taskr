// taskr/taskr/taskrApp.swift
import Foundation
import SwiftUI
import SwiftData

private struct ScreenshotAutomationConfig: Decodable {
    let capture: Bool
    let theme: String?
}

@main
struct taskrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var taskManager: TaskManager
    let container: ModelContainer

    init() {
        let environment = ProcessInfo.processInfo.environment
        let configURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(screenshotAutomationConfigFilename)
        var configCaptureEnabled = false
        var configTheme: String?
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(ScreenshotAutomationConfig.self, from: data) {
            configCaptureEnabled = config.capture
            configTheme = config.theme
        }
        let isScreenshotCapture = environment["SCREENSHOT_CAPTURE"] == "1" || configCaptureEnabled
        let screenshotThemeRaw = environment["SCREENSHOT_THEME"] ?? configTheme
        if isScreenshotCapture {
            UserDefaults.standard.set(true, forKey: showDockIconPreferenceKey)
            UserDefaults.standard.set(false, forKey: globalHotkeyEnabledPreferenceKey)
            UserDefaults.standard.set(false, forKey: addRootTasksToTopPreferenceKey)
            UserDefaults.standard.set(false, forKey: addSubtasksToTopPreferenceKey)
        }

        let modelContainerInstance: ModelContainer
        do {
            let schema = Schema([
                Task.self,
                TaskTemplate.self,
            ])
            let config: ModelConfiguration
            if isScreenshotCapture {
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                config = ModelConfiguration("TaskrAppModel", schema: schema)
            }
            modelContainerInstance = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not configure the model container: \(error)")
        }
        self.container = modelContainerInstance
        
        let taskManagerInstance = TaskManager(modelContext: modelContainerInstance.mainContext)
        if isScreenshotCapture {
            if let screenshotThemeRaw,
               let screenshotTheme = AppTheme(rawValue: screenshotThemeRaw) {
                taskManagerInstance.setTheme(screenshotTheme)
            } else if let screenshotThemeRaw {
                print("Screenshot automation: theme '\(screenshotThemeRaw)' not recognized; falling back to stored selection.")
            }
            taskManagerInstance.prepareForScreenshotCapture()
        }
        _taskManager = StateObject(wrappedValue: taskManagerInstance)
        
        appDelegate.taskManager = taskManagerInstance
        appDelegate.modelContainer = modelContainerInstance
        appDelegate.isRunningScreenshotAutomation = isScreenshotCapture
        appDelegate.setupPopoverAfterDependenciesSet()

#if DEBUG
        configureUITestAutomationIfNeeded(taskManager: taskManagerInstance, appDelegate: appDelegate)
#endif

        if isScreenshotCapture {
            let automationDelegate = appDelegate
            DispatchQueue.main.async {
                automationDelegate.showAutomationWindowIfNeeded(manager: taskManagerInstance, container: modelContainerInstance)
            }
        }
    }

    var body: some Scene {
        WindowGroup("Taskr", id: "MainWindow") {
            ContentView(isStandalone: true)
                .environmentObject(taskManager)
                .environmentObject(taskManager.inputState)
                .modelContainer(container)
                .environmentObject(appDelegate)
                .background(WindowConfigurator(
                    autosaveName: "TaskrMainWindowAutosave",
                    initialSize: NSSize(width: 720, height: 560),
                    palette: taskManager.themePalette,
                    frosted: taskManager.frostedBackgroundEnabled,
                    usesSystemAppearance: taskManager.selectedTheme == .system
                ))
        }
        Settings {
            SettingsView(
                updateIconAction: appDelegate.updateStatusItemIcon,
                setDockIconVisibilityAction: appDelegate.setDockIconVisibility,
                // Wrap the call to match the expected (Bool) -> Bool signature
                enableGlobalHotkeyAction: { enable in
                    // When called from SettingsView, we want the alert if permissions fail
                    return appDelegate.enableGlobalHotkey(enable, showAlertIfNotGranted: true)
                }
            )
        }
        .modelContainer(container)
        .environmentObject(taskManager)
        .environmentObject(taskManager.inputState)
        .commands {
            CommandGroup(replacing: .help) {
                Button("taskr Help…") {
                    appDelegate.showHelpWindow()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Selected Tasks") {
                    taskManager.copySelectedTasksToPasteboard()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(taskManager.selectedTaskIDs.isEmpty || taskManager.isTaskInputFocused)
            }
        }
    }
}

#if DEBUG
private func configureUITestAutomationIfNeeded(taskManager: TaskManager, appDelegate: AppDelegate) {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flagIndex = arguments.firstIndex(of: "-UITestDeepClear") else { return }
    let depth: Int
    if arguments.indices.contains(flagIndex + 1), let parsed = Int(arguments[flagIndex + 1]) {
        depth = max(1, parsed)
    } else {
        depth = 18
    }

    let components = Array(repeating: "test", count: depth)
    let path = "/" + components.joined(separator: "/")

    DispatchQueue.main.async {
        appDelegate.togglePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            taskManager.addTaskFromPath(pathOverride: path)
            let ids = taskManager.snapshotVisibleTaskIDs()
            for id in ids {
                taskManager.toggleTaskCompletion(taskID: id)
            }
            taskManager.clearCompletedTasks()
        }
    }
}
#endif
