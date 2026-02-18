// taskr/taskr/taskrApp.swift
import Foundation
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

private let taskrStoreFileName = "TaskrAppModel.store"
private let legacyDefaultStoreFileName = "default.store"
private let taskrStoreDirectoryName = "Taskr"
private let pendingLegacyStoreBookmarkKey = "pendingLegacyStoreBookmark"
private let pendingLegacyStoreDirectoryBookmarkKey = "pendingLegacyStoreDirectoryBookmark"
private let pendingLegacyStoreFilenameKey = "pendingLegacyStoreFilename"
private let pendingLegacyStoreRelativePathKey = "pendingLegacyStoreRelativePath"
private let legacyRecoveryOptOutKey = "legacyRecoveryOptOut"

@MainActor
private func migrateLegacyStoreIntoCurrentContainerIfNeeded() {
    let fileManager = FileManager.default
    let currentStoreURL = currentContainerStoreURL()

    if fileManager.fileExists(atPath: currentStoreURL.path),
       storeHasAnyData(at: currentStoreURL) {
        return
    }

    do {
        try fileManager.createDirectory(
            at: currentStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    } catch {
        print("Store migration: unable to create destination directory: \(error)")
        return
    }

    // If destination exists but appears empty, allow migration to overwrite it.
    if fileManager.fileExists(atPath: currentStoreURL.path) {
        removeStoreWithSidecars(at: currentStoreURL, fileManager: fileManager)
    }

    for sourceStoreURL in legacyStoreCandidates() {
        guard sourceStoreURL.path != currentStoreURL.path else { continue }
        guard fileManager.fileExists(atPath: sourceStoreURL.path) else { continue }

        do {
            try copyStoreWithSidecars(from: sourceStoreURL, to: currentStoreURL, fileManager: fileManager)
            print("Store migration: migrated data from \(sourceStoreURL.path) to \(currentStoreURL.path)")
            return
        } catch {
            print("Store migration: failed to migrate from \(sourceStoreURL.path): \(error)")
        }
    }
}

private func currentContainerStoreURL() -> URL {
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupportURL
        .appendingPathComponent(taskrStoreDirectoryName, isDirectory: true)
        .appendingPathComponent(taskrStoreFileName, isDirectory: false)
}

private func legacyStoreCandidates() -> [URL] {
    var candidates: [URL] = []
    let currentAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    candidates.append(currentAppSupport.appendingPathComponent(taskrStoreFileName, isDirectory: false))
    candidates.append(
        currentAppSupport
            .appendingPathComponent(taskrStoreDirectoryName, isDirectory: true)
            .appendingPathComponent(taskrStoreFileName, isDirectory: false)
    )
    candidates.append(currentAppSupport.appendingPathComponent(legacyDefaultStoreFileName, isDirectory: false))

    let hostAppSupport = URL(fileURLWithPath: "/Users", isDirectory: true)
        .appendingPathComponent(NSUserName(), isDirectory: true)
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
    candidates.append(hostAppSupport.appendingPathComponent(taskrStoreFileName, isDirectory: false))
    candidates.append(
        hostAppSupport
            .appendingPathComponent(taskrStoreDirectoryName, isDirectory: true)
            .appendingPathComponent(taskrStoreFileName, isDirectory: false)
    )
    candidates.append(hostAppSupport.appendingPathComponent(legacyDefaultStoreFileName, isDirectory: false))

    var seen = Set<String>()
    return candidates.filter { seen.insert($0.path).inserted }
}

private func copyStoreWithSidecars(from sourceStoreURL: URL, to destinationStoreURL: URL, fileManager: FileManager) throws {
    if fileManager.fileExists(atPath: destinationStoreURL.path) {
        return
    }

    try fileManager.copyItem(at: sourceStoreURL, to: destinationStoreURL)

    let sourceShm = URL(fileURLWithPath: sourceStoreURL.path + "-shm")
    let sourceWal = URL(fileURLWithPath: sourceStoreURL.path + "-wal")
    let destinationShm = URL(fileURLWithPath: destinationStoreURL.path + "-shm")
    let destinationWal = URL(fileURLWithPath: destinationStoreURL.path + "-wal")

    if fileManager.fileExists(atPath: sourceShm.path), !fileManager.fileExists(atPath: destinationShm.path) {
        do {
            try fileManager.copyItem(at: sourceShm, to: destinationShm)
        } catch {
            print("Store migration: unable to copy SHM sidecar from \(sourceShm.path): \(error)")
        }
    }

    if fileManager.fileExists(atPath: sourceWal.path), !fileManager.fileExists(atPath: destinationWal.path) {
        do {
            try fileManager.copyItem(at: sourceWal, to: destinationWal)
        } catch {
            print("Store migration: unable to copy WAL sidecar from \(sourceWal.path): \(error)")
        }
    }
}

private func removeStoreWithSidecars(at storeURL: URL, fileManager: FileManager) {
    let urls = [
        storeURL,
        URL(fileURLWithPath: storeURL.path + "-wal"),
        URL(fileURLWithPath: storeURL.path + "-shm"),
    ]
    for url in urls where fileManager.fileExists(atPath: url.path) {
        try? fileManager.removeItem(at: url)
    }
}

@MainActor
private func restoreStoreFromPendingBookmarkIfNeeded() {
    let defaults = UserDefaults.standard
    var sourceURL: URL
    var sourceDirectoryURLForSelection: URL?
    var preferredFilenameForSelection: String?
    var securityScopeURLs: [URL] = []
    if let fileBookmark = defaults.data(forKey: pendingLegacyStoreBookmarkKey) {
        var isStale = false
        guard let resolvedFileURL = try? URL(
            resolvingBookmarkData: fileBookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            clearPendingRecoverySelection(defaults: defaults)
            return
        }
        sourceURL = resolvedFileURL
        securityScopeURLs.append(resolvedFileURL)
        var hasDirectoryScopeBookmark = false
        if let directoryBookmark = defaults.data(forKey: pendingLegacyStoreDirectoryBookmarkKey) {
            var isDirectoryBookmarkStale = false
            if let sourceDirectoryURL = try? URL(
                resolvingBookmarkData: directoryBookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isDirectoryBookmarkStale
            ) {
                securityScopeURLs.append(sourceDirectoryURL)
                hasDirectoryScopeBookmark = true
            }
        }
        if !hasDirectoryScopeBookmark {
            print("Store recovery: missing directory bookmark for selected store; re-selection required for WAL/SHM access.")
            clearPendingRecoverySelection(defaults: defaults)
            return
        }
    } else if let directoryBookmark = defaults.data(forKey: pendingLegacyStoreDirectoryBookmarkKey) {
        let preferredRelativePath = defaults.string(forKey: pendingLegacyStoreRelativePathKey)
            ?? defaults.string(forKey: pendingLegacyStoreFilenameKey)
            ?? ""
        guard !preferredRelativePath.isEmpty else {
            clearPendingRecoverySelection(defaults: defaults)
            return
        }
        var isStale = false
        guard let sourceDirectoryURL = try? URL(
            resolvingBookmarkData: directoryBookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            clearPendingRecoverySelection(defaults: defaults)
            return
        }
        sourceURL = sourceDirectoryURL.appendingPathComponent(preferredRelativePath, isDirectory: false)
        sourceDirectoryURLForSelection = sourceDirectoryURL
        preferredFilenameForSelection = preferredRelativePath
        securityScopeURLs.append(sourceDirectoryURL)
    } else {
        return
    }

    let destinationURL = currentContainerStoreURL()
    let fileManager = FileManager.default
    var scopedURLs: [URL] = []
    var seenScopePaths = Set<String>()
    for candidateURL in securityScopeURLs where seenScopePaths.insert(candidateURL.path).inserted {
        if candidateURL.startAccessingSecurityScopedResource() {
            scopedURLs.append(candidateURL)
        }
    }
    defer {
        for scopedURL in scopedURLs {
            scopedURL.stopAccessingSecurityScopedResource()
        }
    }

    if let sourceDirectoryURLForSelection {
        if let selectedSourceURL = preferredRecoveryStoreURL(
            in: sourceDirectoryURLForSelection,
            preferredFilename: preferredFilenameForSelection
        ) {
            sourceURL = selectedSourceURL
        } else {
            clearPendingRecoverySelection(defaults: defaults)
            return
        }
    }

    guard fileManager.fileExists(atPath: sourceURL.path) else {
        clearPendingRecoverySelection(defaults: defaults)
        return
    }
    print("Store recovery: restoring from \(sourceURL.path)")

    var didRestore = false
    do {
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        // Stage recovery in a temp location first so a failed restore cannot wipe a good store.
        let stagingDirectory = destinationDirectory.appendingPathComponent(".recovery-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        let stagedStoreURL = stagingDirectory.appendingPathComponent(destinationURL.lastPathComponent, isDirectory: false)
        try copyStoreWithSidecars(from: sourceURL, to: stagedStoreURL, fileManager: fileManager)

        removeStoreWithSidecars(at: destinationURL, fileManager: fileManager)
        try moveStoreWithSidecars(from: stagedStoreURL, to: destinationURL, fileManager: fileManager)
        didRestore = true
    } catch {
        print("Store recovery: failed to restore from selected store: \(error)")
    }

    if didRestore, storeHasAnyData(at: destinationURL) {
        clearPendingRecoverySelection(defaults: defaults)
    } else if didRestore {
        print("Store recovery: restored file but destination store still appears empty.")
    }
}

private func clearPendingRecoverySelection(defaults: UserDefaults) {
    defaults.removeObject(forKey: pendingLegacyStoreBookmarkKey)
    defaults.removeObject(forKey: pendingLegacyStoreDirectoryBookmarkKey)
    defaults.removeObject(forKey: pendingLegacyStoreFilenameKey)
    defaults.removeObject(forKey: pendingLegacyStoreRelativePathKey)
}

@MainActor
private func preferredRecoveryStoreURL(in directoryURL: URL, preferredFilename: String?) -> URL? {
    let fileManager = FileManager.default
    var candidateRelativePaths: [String] = []
    candidateRelativePaths.append("\(taskrStoreDirectoryName)/\(taskrStoreFileName)")
    candidateRelativePaths.append("\(taskrStoreDirectoryName)/\(legacyDefaultStoreFileName)")
    candidateRelativePaths.append(taskrStoreFileName)
    candidateRelativePaths.append(legacyDefaultStoreFileName)
    if let preferredFilename, !preferredFilename.isEmpty {
        candidateRelativePaths.append(preferredFilename)
    }

    var seen = Set<String>()
    let candidates = candidateRelativePaths
        .filter { seen.insert($0).inserted }
        .map { directoryURL.appendingPathComponent($0, isDirectory: false) }
        .filter { fileManager.fileExists(atPath: $0.path) }

    guard !candidates.isEmpty else { return nil }
    print("Store recovery: candidate stores = \(candidates.map { $0.path })")
    let selected = candidates[0]
    print("Store recovery: selected candidate by priority = \(selected.path)")
    return selected
}

private func relativePath(from directoryURL: URL, to fileURL: URL) -> String {
    let basePath = directoryURL.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
    if filePath.hasPrefix(prefix) {
        return String(filePath.dropFirst(prefix.count))
    }
    return fileURL.lastPathComponent
}

@MainActor
private func storeHasAnyData(at storeURL: URL) -> Bool {
    do {
        let schema = Schema([
            Task.self,
            TaskTemplate.self,
            TaskTag.self,
        ])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = container.mainContext
        let taskCount = (try? modelContext.fetchCount(FetchDescriptor<Task>())) ?? 0
        let templateCount = (try? modelContext.fetchCount(FetchDescriptor<TaskTemplate>())) ?? 0
        return taskCount > 0 || templateCount > 0
    } catch {
        print("Store recovery: unable to validate restored store contents: \(error)")
        return false
    }
}

private func moveStoreWithSidecars(from sourceStoreURL: URL, to destinationStoreURL: URL, fileManager: FileManager) throws {
    try fileManager.moveItem(at: sourceStoreURL, to: destinationStoreURL)

    let sourceWal = URL(fileURLWithPath: sourceStoreURL.path + "-wal")
    let sourceShm = URL(fileURLWithPath: sourceStoreURL.path + "-shm")
    let destinationWal = URL(fileURLWithPath: destinationStoreURL.path + "-wal")
    let destinationShm = URL(fileURLWithPath: destinationStoreURL.path + "-shm")

    if fileManager.fileExists(atPath: sourceWal.path) {
        try fileManager.moveItem(at: sourceWal, to: destinationWal)
    }
    if fileManager.fileExists(atPath: sourceShm.path) {
        try fileManager.moveItem(at: sourceShm, to: destinationShm)
    }
}

private func scheduleLegacyRecoveryPromptIfNeeded(modelContext: ModelContext) {
    if isRunningAutomatedTests() {
        return
    }

    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: legacyRecoveryOptOutKey) else { return }
    guard hasLikelyPriorTaskrUsage(defaults: defaults) else { return }
    guard storeAppearsEmpty(modelContext: modelContext) else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Recover Existing Taskr Data?"
        alert.informativeText = """
        No tasks were found in the new sandboxed location.

        If you used Taskr before this update, choose your previous store file from:
        ~/Library/Application Support/

        Select TaskrAppModel.store if present, otherwise default.store.
        """
        alert.addButton(withTitle: "Choose Store File")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            presentLegacyStorePickerAndQueueRestore(defaults: defaults)
        case .alertThirdButtonReturn:
            defaults.set(true, forKey: legacyRecoveryOptOutKey)
        default:
            break
        }
    }
}

private func isRunningAutomatedTests() -> Bool {
    let processInfo = ProcessInfo.processInfo
    let environment = processInfo.environment
    let arguments = processInfo.arguments

    if environment["XCTestConfigurationFilePath"] != nil {
        return true
    }
    if environment["XCTestBundlePath"] != nil {
        return true
    }
    if environment["XCTestSessionIdentifier"] != nil {
        return true
    }
    if arguments.contains("--uitests") {
        return true
    }
    return processInfo.processName == "xctest"
}

private func hasLikelyPriorTaskrUsage(defaults: UserDefaults) -> Bool {
    let keys = [
        selectedThemePreferenceKey,
        showDockIconPreferenceKey,
        globalHotkeyEnabledPreferenceKey,
        addRootTasksToTopPreferenceKey,
        addSubtasksToTopPreferenceKey,
        collapsedTaskIDsPreferenceKey,
    ]
    return keys.contains { defaults.object(forKey: $0) != nil }
}

private func storeAppearsEmpty(modelContext: ModelContext) -> Bool {
    let taskCount = (try? modelContext.fetchCount(FetchDescriptor<Task>())) ?? 0
    let templateCount = (try? modelContext.fetchCount(FetchDescriptor<TaskTemplate>())) ?? 0
    return taskCount == 0 && templateCount == 0
}

@MainActor
private func presentLegacyStorePickerAndQueueRestore(defaults: UserDefaults) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if let storeType = UTType(filenameExtension: "store") {
        panel.allowedContentTypes = [storeType]
    } else {
        panel.allowedContentTypes = [.data]
    }
    panel.message = "Choose your Application Support folder or a .store file"
    panel.prompt = "Use Selection"

    guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory)
    guard exists else { return }

    if isDirectory.boolValue {
        let directoryURL = selectedURL
        guard let selectedSourceURL = preferredRecoveryStoreURL(
            in: directoryURL,
            preferredFilename: nil
        ) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "No Valid Taskr Store Found"
            alert.informativeText = "The selected folder did not contain a Taskr store with any Taskr data."
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return
        }
        print("Store recovery: selected folder source \(selectedSourceURL.path)")
        let selectedRelativePath = relativePath(from: directoryURL, to: selectedSourceURL)
        guard !selectedRelativePath.isEmpty else {
            return
        }
        guard
              let directoryBookmark = try? directoryURL.bookmarkData(
                  options: [.withSecurityScope],
                  includingResourceValuesForKeys: nil,
                  relativeTo: nil
              ) else { return }
        defaults.set(directoryBookmark, forKey: pendingLegacyStoreDirectoryBookmarkKey)
        defaults.set(selectedRelativePath, forKey: pendingLegacyStoreRelativePathKey)
        defaults.set(selectedSourceURL.lastPathComponent, forKey: pendingLegacyStoreFilenameKey)
        defaults.removeObject(forKey: pendingLegacyStoreBookmarkKey)
    } else {
        guard let fileBookmark = try? selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        let selectedDirectoryURL = selectedURL.deletingLastPathComponent()
        guard let directoryBookmark = try? selectedDirectoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        defaults.set(fileBookmark, forKey: pendingLegacyStoreBookmarkKey)
        defaults.set(directoryBookmark, forKey: pendingLegacyStoreDirectoryBookmarkKey)
        defaults.set(selectedURL.lastPathComponent, forKey: pendingLegacyStoreFilenameKey)
        defaults.set(selectedURL.lastPathComponent, forKey: pendingLegacyStoreRelativePathKey)
    }

    let restartAlert = NSAlert()
    restartAlert.alertStyle = .informational
    restartAlert.messageText = "Restart Required"
    restartAlert.informativeText = "Taskr will quit now and restore data from the selected file on next launch."
    restartAlert.addButton(withTitle: "Quit Taskr")
    _ = restartAlert.runModal()
    NSApp.terminate(nil)
}

@main
struct taskrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var taskManager: TaskManager
    let container: ModelContainer

    init() {
        restoreStoreFromPendingBookmarkIfNeeded()
        migrateLegacyStoreIntoCurrentContainerIfNeeded()

        let modelContainerInstance: ModelContainer
        do {
            let schema = Schema([
                Task.self,
                TaskTemplate.self,
                TaskTag.self,
            ])
            let config = ModelConfiguration(schema: schema, url: currentContainerStoreURL())
            modelContainerInstance = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not configure the model container: \(error)")
        }
        self.container = modelContainerInstance
        
        let taskManagerInstance = TaskManager(modelContext: modelContainerInstance.mainContext)
        _taskManager = StateObject(wrappedValue: taskManagerInstance)
        
        appDelegate.taskManager = taskManagerInstance
        appDelegate.modelContainer = modelContainerInstance
        appDelegate.setupPopoverAfterDependenciesSet()
        scheduleLegacyRecoveryPromptIfNeeded(modelContext: modelContainerInstance.mainContext)

#if DEBUG
        configureUITestAutomationIfNeeded(taskManager: taskManagerInstance, appDelegate: appDelegate)
#endif
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
