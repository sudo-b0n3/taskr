import Foundation
import SwiftData

extension TaskManager {
    func prepareForScreenshotCapture() {
        if isRunningScreenshotAutomation {
            isDemoSwapInProgress = true
            defer { isDemoSwapInProgress = false }
            resetPersistentStateForScreenshots()
            seedTasks()
            seedTemplates()
            finalizeScreenshotSeedState()
            return
        }

        enterScreenshotDemoMode()
    }

    func toggleScreenshotDemoMode() {
        guard !isRunningScreenshotAutomation else {
            prepareForScreenshotCapture()
            return
        }

        guard !isDemoSwapInProgress else { return }
        isDemoSwapInProgress = true
        defer { isDemoSwapInProgress = false }
        clearInputStateForDemoSwap()
        clearSelection()
        endShiftSelection()
        if isScreenshotDemoModeActive {
            restoreScreenshotBackup()
        } else {
            enterScreenshotDemoMode()
        }
    }

    private func enterScreenshotDemoMode() {
        guard !isScreenshotDemoModeActive else { return }
        do {
            try writeScreenshotBackup()
            UserDefaults.standard.set(true, forKey: screenshotDemoModeActivePreferenceKey)
        } catch {
            print("Screenshot seeding: failed to write backup: \(error)")
            return
        }

        let wasInProgress = isDemoSwapInProgress
        if !wasInProgress { isDemoSwapInProgress = true }
        defer { if !wasInProgress { isDemoSwapInProgress = false } }

        resetPersistentStateForScreenshots()
        seedTasks()
        seedTemplates()
        finalizeScreenshotSeedState()
    }

    private func restoreScreenshotBackup() {
        let wasInProgress = isDemoSwapInProgress
        if !wasInProgress { isDemoSwapInProgress = true }
        defer { if !wasInProgress { isDemoSwapInProgress = false } }

        do {
            let backup = try readScreenshotBackup()
            clearUserTasksAndTemplates()
            try importUserTasksBackup(from: backup.tasks)
            try importUserTemplates(from: backup.templates)
            applyScreenshotPreferences(backup.preferences)
            try modelContext.save()
            invalidateVisibleTasksCache()
            invalidateChildTaskCache(for: nil)
            clearScreenshotBackup()
            UserDefaults.standard.set(false, forKey: screenshotDemoModeActivePreferenceKey)
        } catch {
            print("Screenshot seeding: failed to restore backup: \(error)")
        }
    }

    private func resetPersistentStateForScreenshots() {
        clearUserTasksAndTemplates()
        applyScreenshotPreferences(.demoDefaults)
    }

    private func clearUserTasksAndTemplates() {
        do {
            let allTemplates = try modelContext.fetch(FetchDescriptor<TaskTemplate>())
            for template in allTemplates {
                modelContext.delete(template)
            }

            let allTasks = try modelContext.fetch(FetchDescriptor<Task>())
            for task in allTasks where !task.isTemplateComponent {
                modelContext.delete(task)
            }

            try modelContext.save()
        } catch {
            print("Screenshot seeding: failed to reset state: \(error)")
        }
    }

    private func seedTasks() {
        let samplePaths = [
            "/Launch Campaign/Kickoff call",
            "/Launch Campaign/Creative brief",
            "/Launch Campaign/Asset reviews/Copy approval",
            "/Launch Campaign/Asset reviews/Design polish",
            "/Launch Campaign/Launch plan/QA checklist",
            "/Launch Campaign/Launch plan/Final go/no-go",
            "/Personal/Health/Morning run",
            "/Personal/Health/Stretching",
            "/Personal/Errands/Groceries/Farmer's market list",
            "/Personal/Errands/Groceries/Supermarket staples",
        ]

        for path in samplePaths {
            addTaskFromPath(pathOverride: path)
        }

        if let launchPlan = findTask(withName: "Launch plan") {
            setTaskExpanded(launchPlan.id, expanded: true)
        }

        if let assetReviews = findTask(withName: "Asset reviews") {
            setTaskExpanded(assetReviews.id, expanded: true)
        }

        if let creativeBrief = findTask(withName: "Creative brief") {
            toggleTaskCompletion(taskID: creativeBrief.id)
        }

        if let morningRun = findTask(withName: "Morning run") {
            toggleTaskCompletion(taskID: morningRun.id)
        }
    }

    private func seedTemplates() {
        newTemplateName = "Product Launch"
        addTemplate()

        guard let template = try? modelContext.fetch(FetchDescriptor<TaskTemplate>()).first,
              let container = template.taskStructure else { return }

        addTemplateSubtask(to: container, name: "Plan brief")
        addTemplateSubtask(to: container, name: "Draft assets")
        addTemplateSubtask(to: container, name: "Schedule QA")

        if let planBrief = container.subtasks?.first(where: { $0.name == "Plan brief" }) {
            addTemplateSubtask(to: planBrief, name: "Identify goals")
            addTemplateSubtask(to: planBrief, name: "Outline channels")
        }

        if let draftAssets = container.subtasks?.first(where: { $0.name == "Draft assets" }) {
            addTemplateSubtask(to: draftAssets, name: "Social post set")
            addTemplateSubtask(to: draftAssets, name: "Email copy")
        }
    }

    private func findTask(withName name: String) -> Task? {
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                !task.isTemplateComponent && task.name == name
            }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func finalizeScreenshotSeedState() {
        currentPathInput = "/Launch Campaign/"
        updateAutocompleteSuggestions(for: currentPathInput)
        selectedSuggestionIndex = autocompleteSuggestions.isEmpty ? nil : 0
        completionMutationVersion = 0
        pendingInlineEditTaskID = nil
        try? modelContext.save()
        invalidateVisibleTasksCache()
        invalidateChildTaskCache(for: nil)
    }

    private func clearInputStateForDemoSwap() {
        currentPathInput = ""
        updateAutocompleteSuggestions(for: "")
        selectedSuggestionIndex = nil
        pendingInlineEditTaskID = nil
        setTaskInputFocused(false)
    }

    private func applyScreenshotPreferences(_ preferences: ScreenshotPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.addRootTasksToTop, forKey: addRootTasksToTopPreferenceKey)
        defaults.set(preferences.addSubtasksToTop, forKey: addSubtasksToTopPreferenceKey)
        collapsedTaskIDs = Set(preferences.collapsedTaskIDs)
        persistCollapsedState()
    }

    private var isScreenshotDemoModeActive: Bool {
        UserDefaults.standard.bool(forKey: screenshotDemoModeActivePreferenceKey)
    }

    private var isRunningScreenshotAutomation: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["SCREENSHOT_CAPTURE"] == "1" {
            return true
        }
        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(screenshotAutomationConfigFilename)
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ScreenshotAutomationConfig.self, from: data)
        else { return false }
        return config.capture
    }

    private func screenshotBackupDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("Taskr", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private func screenshotBackupURLs() throws -> ScreenshotBackupURLs {
        let directory = try screenshotBackupDirectory()
        return ScreenshotBackupURLs(
            tasks: directory.appendingPathComponent("demo-backup-tasks.json"),
            templates: directory.appendingPathComponent("demo-backup-templates.json"),
            preferences: directory.appendingPathComponent("demo-backup-preferences.json")
        )
    }

    private func writeScreenshotBackup() throws {
        let urls = try screenshotBackupURLs()
        let tasksData = try exportUserTasksData()
        let templatesData = try exportUserTemplatesData()
        let preferences = ScreenshotPreferences(
            addRootTasksToTop: UserDefaults.standard.bool(forKey: addRootTasksToTopPreferenceKey),
            addSubtasksToTop: UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey),
            collapsedTaskIDs: Array(collapsedTaskIDs)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let preferencesData = try encoder.encode(preferences)
        try tasksData.write(to: urls.tasks, options: .atomic)
        try templatesData.write(to: urls.templates, options: .atomic)
        try preferencesData.write(to: urls.preferences, options: .atomic)
    }

    private func readScreenshotBackup() throws -> ScreenshotBackupData {
        let urls = try screenshotBackupURLs()
        let tasksData = try Data(contentsOf: urls.tasks)
        let templatesData = try Data(contentsOf: urls.templates)
        let preferencesData = try Data(contentsOf: urls.preferences)
        let decoder = JSONDecoder()
        let preferences = try decoder.decode(ScreenshotPreferences.self, from: preferencesData)
        return ScreenshotBackupData(
            tasks: tasksData,
            templates: templatesData,
            preferences: preferences
        )
    }

    private func clearScreenshotBackup() {
        guard let urls = try? screenshotBackupURLs() else { return }
        let fileManager = FileManager.default
        [urls.tasks, urls.templates, urls.preferences].forEach { url in
            try? fileManager.removeItem(at: url)
        }
    }
}

private struct ScreenshotPreferences: Codable {
    let addRootTasksToTop: Bool
    let addSubtasksToTop: Bool
    let collapsedTaskIDs: [UUID]

    static var demoDefaults: ScreenshotPreferences {
        ScreenshotPreferences(
            addRootTasksToTop: false,
            addSubtasksToTop: false,
            collapsedTaskIDs: []
        )
    }
}

private struct ScreenshotBackupURLs {
    let tasks: URL
    let templates: URL
    let preferences: URL
}

private struct ScreenshotBackupData {
    let tasks: Data
    let templates: Data
    let preferences: ScreenshotPreferences
}

private struct ScreenshotAutomationConfig: Decodable {
    let capture: Bool
}
