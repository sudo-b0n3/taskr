// taskr/taskr/taskrApp.swift
import SwiftUI
import SwiftData

@main
struct taskrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var taskManager: TaskManager
    let container: ModelContainer

    init() {
        let isScreenshotCapture = ProcessInfo.processInfo.environment["SCREENSHOT_CAPTURE"] == "1"
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
            taskManagerInstance.prepareForScreenshotCapture()
        }
        _taskManager = StateObject(wrappedValue: taskManagerInstance)
        
        appDelegate.taskManager = taskManagerInstance
        appDelegate.modelContainer = modelContainerInstance
        appDelegate.isRunningScreenshotAutomation = isScreenshotCapture
        appDelegate.setupPopoverAfterDependenciesSet()

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
                .modelContainer(container)
                .environmentObject(appDelegate)
                .background(WindowConfigurator(
                    autosaveName: "TaskrMainWindowAutosave",
                    initialSize: NSSize(width: 720, height: 560),
                    palette: taskManager.themePalette,
                    frosted: taskManager.frostedBackgroundEnabled
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
        .commands {
            CommandGroup(replacing: .help) {
                Button("taskr Help…") {
                    appDelegate.showHelpWindow()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }
    }
}
