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
                TaskTag.self,
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
                .environmentObject(taskManager.selectionManager)
                .modelContainer(container)
                .environmentObject(appDelegate)
                .background(WindowConfigurator(
                    autosaveName: "TaskrMainWindowAutosave",
                    initialSize: NSSize(width: 720, height: 560),
                    palette: taskManager.themePalette,
                    frosted: taskManager.frostedBackgroundEnabled,
                    frostOpacity: taskManager.frostedBackgroundLevel.opacity,
                    usesSystemAppearance: taskManager.selectedTheme == .system,
                    allowBackgroundDrag: false,
                    onWindowAvailable: { window in
                        appDelegate.registerMainWindow(window)
                    }
                ))
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])  // Prevent auto-open on launch; window opens via openWindow(id:)
        Settings {
            SettingsView()
        }
        .modelContainer(container)
        .environmentObject(taskManager)
        .environmentObject(taskManager.inputState)
        .environmentObject(taskManager.selectionManager)
        .environmentObject(appDelegate)
        .commands {
            CommandGroup(replacing: .help) {
                Button("taskr Help…") {
                    appDelegate.showHelpWindow()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
            CommandGroup(after: .pasteboard) {
                CopySelectionCommands(taskManager: taskManager, selectionManager: taskManager.selectionManager)
            }
        }
    }
}

private struct CopySelectionCommands: View {
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var selectionManager: SelectionManager

    var body: some View {
        Button("Copy Selected Tasks") {
            taskManager.copySelectedTasksToPasteboard()
        }
        .keyboardShortcut("c", modifiers: [.command])
        .disabled(selectionManager.selectedTaskIDs.isEmpty || taskManager.isTaskInputFocused)
    }
}

#if DEBUG
private let uiTestPanelReopenFocusResultFilename = "taskr_ui_panel_focus_result.txt"
private let uiTestPanelReopenFocusResultPathEnvironmentKey = "UITEST_PANEL_FOCUS_RESULT_PATH"

private func configureUITestAutomationIfNeeded(taskManager: TaskManager, appDelegate: AppDelegate) {
    let arguments = ProcessInfo.processInfo.arguments

    if let flagIndex = arguments.firstIndex(of: "-UITestDeepClear") {
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

    if arguments.contains("-UITestPanelReopenFocus") {
        runPanelReopenFocusAutomation(taskManager: taskManager, appDelegate: appDelegate)
    }
}

private func runPanelReopenFocusAutomation(taskManager: TaskManager, appDelegate: AppDelegate) {
    UserDefaults.standard.set(MenuBarPresentationStyle.panel.rawValue, forKey: menuBarPresentationStylePreferenceKey)
    writePanelReopenFocusResult("pending")

    DispatchQueue.main.async {
        appDelegate.resetMenuBarPresentation()
        appDelegate.togglePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ensureAtLeastOneLiveTask(taskManager: taskManager)
            guard let firstTaskID = taskManager.snapshotVisibleTaskIDs().first else {
                writePanelReopenFocusResult("fail")
                return
            }
            taskManager.replaceSelection(with: firstTaskID)
            let firstOpenKeyState = taskManager.liveListWindowIsKeyForUITest
            appDelegate.togglePopover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appDelegate.togglePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let reopenedKeyState = taskManager.liveListWindowIsKeyForUITest
                    writePanelReopenFocusResult(firstOpenKeyState && reopenedKeyState ? "pass" : "fail")
                }
            }
        }
    }
}

@MainActor
private func ensureAtLeastOneLiveTask(taskManager: TaskManager) {
    if taskManager.snapshotVisibleTaskIDs().isEmpty {
        taskManager.addTaskFromPath(pathOverride: "/focus-probe")
    }
}

private func writePanelReopenFocusResult(_ value: String) {
    let environment = ProcessInfo.processInfo.environment
    let url: URL
    if let explicitPath = environment[uiTestPanelReopenFocusResultPathEnvironmentKey],
       !explicitPath.isEmpty {
        url = URL(fileURLWithPath: explicitPath)
    } else {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(uiTestPanelReopenFocusResultFilename)
    }
    try? value.write(to: url, atomically: true, encoding: .utf8)
}

#else
private func configureUITestAutomationIfNeeded(taskManager: TaskManager, appDelegate: AppDelegate) {
}
#endif
