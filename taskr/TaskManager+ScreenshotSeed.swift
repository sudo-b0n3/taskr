import Foundation
import SwiftData

extension TaskManager {
    func prepareForScreenshotCapture() {
        resetPersistentStateForScreenshots()
        seedTasks()
        seedTemplates()
        currentPathInput = "/Launch Campaign/"
        updateAutocompleteSuggestions(for: currentPathInput)
        selectedSuggestionIndex = autocompleteSuggestions.isEmpty ? nil : 0
        completionMutationVersion = 0
        pendingInlineEditTaskID = nil
        try? modelContext.save()
    }

    private func resetPersistentStateForScreenshots() {
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

        UserDefaults.standard.set(false, forKey: addRootTasksToTopPreferenceKey)
        UserDefaults.standard.set(false, forKey: addSubtasksToTopPreferenceKey)
        UserDefaults.standard.removeObject(forKey: collapsedTaskIDsPreferenceKey)
        collapsedTaskIDs = []
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
}
