import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Template ordering

    func moveTemplateTaskUp(_ task: Task) {
        guard task.isTemplateComponent else { return }
        moveItem(task, kind: .template, direction: .up)
    }

    func moveTemplateTaskDown(_ task: Task) {
        guard task.isTemplateComponent else { return }
        moveItem(task, kind: .template, direction: .down)
    }

    func canMoveTemplateTaskUp(_ task: Task) -> Bool {
        guard task.isTemplateComponent else { return false }
        do {
            let siblings = try fetchSiblings(for: task.parentTask, kind: .template)
            guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return false }
            return index > 0
        } catch {
            return false
        }
    }

    func canMoveTemplateTaskDown(_ task: Task) -> Bool {
        guard task.isTemplateComponent else { return false }
        do {
            let siblings = try fetchSiblings(for: task.parentTask, kind: .template)
            guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return false }
            return index < siblings.count - 1
        } catch {
            return false
        }
    }

    func reparentTemplateTask(draggedTaskID: UUID, newParentID: UUID?) {
        do {
            let draggedFetch = FetchDescriptor<Task>(predicate: #Predicate { $0.id == draggedTaskID && $0.isTemplateComponent })
            guard let dragged = try modelContext.fetch(draggedFetch).first else { return }
            let originalParent = dragged.parentTask

            let newParent: Task?
            if let pid = newParentID {
                let parentFetch = FetchDescriptor<Task>(predicate: #Predicate { $0.id == pid && $0.isTemplateComponent })
                newParent = try modelContext.fetch(parentFetch).first
            } else {
                newParent = nil
            }

            dragged.parentTask = newParent
            dragged.displayOrder = getNextDisplayOrderForTemplates(for: newParent, in: modelContext)
            try modelContext.save()

            if originalParent?.id != newParent?.id {
                resequenceTemplateDisplayOrder(for: originalParent)
            }
            invalidateChildTaskCache(for: .template)
        } catch {
            print("Error reparenting template task with ID \(draggedTaskID): \(error)")
        }
    }

    func addTemplate() {
        guard !newTemplateName.isEmpty else { return }

        let templateRootContainerTask = Task(
            name: "TEMPLATE_INTERNAL_ROOT_CONTAINER",
            displayOrder: 0,
            isTemplateComponent: true
        )
        modelContext.insert(templateRootContainerTask)
        templateRootContainerTask.subtasks = []
        let newTemplate = TaskTemplate(
            name: newTemplateName,
            taskStructure: templateRootContainerTask
        )
        modelContext.insert(newTemplate)
        try? modelContext.save()
        newTemplateName = ""
        invalidateChildTaskCache(for: .template)
    }

    func applyTemplate(_ template: TaskTemplate) {
        guard let templateContainerTask = template.taskStructure,
              let tasksToCopyFromTemplate = templateContainerTask.subtasks?.sorted(by: { $0.displayOrder < $1.displayOrder })
        else { return }

        let placeAtTop = UserDefaults.standard.bool(forKey: addRootTasksToTopPreferenceKey)
        let orderedTasks = placeAtTop ? tasksToCopyFromTemplate.reversed() : tasksToCopyFromTemplate
        for taskToInstantiate in orderedTasks {
            applyTemplateTaskRecursively(templateTask: taskToInstantiate, parentTask: nil)
        }
        try? modelContext.save()
        invalidateVisibleTasksCache()
        invalidateChildTaskCache(for: .live)
    }

    private func applyTemplateTaskRecursively(templateTask: Task, parentTask: Task?) {
        let existingTask = findUserTask(named: templateTask.name, under: parentTask)

        let targetTask: Task
        if let existing = existingTask {
            targetTask = existing
        } else {
            let placeAtTop: Bool
            if parentTask == nil {
                placeAtTop = UserDefaults.standard.bool(forKey: addRootTasksToTopPreferenceKey)
            } else {
                placeAtTop = UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey)
            }
            let newDisplayOrder = getDisplayOrderForInsertion(
                for: parentTask,
                placeAtTop: placeAtTop,
                in: modelContext
            )
            targetTask = Task(
                name: templateTask.name,
                isCompleted: false,
                creationDate: Date(),
                displayOrder: newDisplayOrder,
                isTemplateComponent: false,
                parentTask: parentTask
            )
            modelContext.insert(targetTask)
        }

        if let templateSubtasks = templateTask.subtasks?.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            let placeAtTop = UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey)
            let orderedSubtasks = placeAtTop ? templateSubtasks.reversed() : templateSubtasks
            for subtask in orderedSubtasks {
                applyTemplateTaskRecursively(templateTask: subtask, parentTask: targetTask)
            }
        }
    }

    func addTemplateSubtask(to parent: Task, name: String = "New Task") {
        guard parent.isTemplateComponent else { return }
        let newOrder = getNextDisplayOrderForTemplates(for: parent, in: modelContext)
        let newTask = Task(
            name: name,
            isCompleted: false,
            creationDate: Date(),
            displayOrder: newOrder,
            isTemplateComponent: true,
            parentTask: parent
        )
        modelContext.insert(newTask)
        if parent.subtasks == nil {
            parent.subtasks = [newTask]
        } else if parent.subtasks?.contains(where: { $0.id == newTask.id }) == false {
            parent.subtasks?.append(newTask)
        }
        try? modelContext.save()
        invalidateChildTaskCache(for: .template)
    }

    func addTemplateRootTask(to template: TaskTemplate, name: String = "New Task") {
        guard let container = template.taskStructure else { return }
        addTemplateSubtask(to: container, name: name)
    }

    func deleteTemplateTask(_ task: Task) {
        guard task.isTemplateComponent else { return }
        // Use generic helper
        deleteTasks([task])
    }

    func fetchTemplateSiblings(for parent: Task?) throws -> [Task] {
        try fetchSiblings(for: parent, kind: .template)
    }

    func getNextDisplayOrderForTemplates(
        for parent: Task?,
        in context: ModelContext
    ) -> Int {
        nextDisplayOrder(for: parent, kind: .template, in: context)
    }

    func resequenceTemplateDisplayOrder(for parent: Task?) {
        resequenceDisplayOrder(for: parent, kind: .template)
    }

    private func deepCopyTask(
        original: Task,
        newParent: Task?,
        isTemplateComponentFlag: Bool,
        forApplying: Bool,
        context: ModelContext
    ) -> Task {
        let order: Int
        if forApplying {
            order = getNextDisplayOrder(for: newParent, in: context)
        } else {
            order = original.displayOrder
        }

        let copy = Task(
            name: original.name,
            isCompleted: forApplying ? original.isCompleted : false,
            creationDate: forApplying ? Date() : original.creationDate,
            displayOrder: order,
            isTemplateComponent: isTemplateComponentFlag,
            parentTask: newParent
        )
        context.insert(copy)
        if let originalSubtasks = original.subtasks?.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            copy.subtasks = []
            for sub in originalSubtasks {
                let copiedSub = deepCopyTask(
                    original: sub,
                    newParent: copy,
                    isTemplateComponentFlag: isTemplateComponentFlag,
                    forApplying: forApplying,
                    context: context
                )
                copy.subtasks?.append(copiedSub)
            }
        }
        return copy
    }
    func moveTemplateTask(draggedTaskID: UUID, targetTaskID: UUID, parentOfList: Task?, moveBeforeTarget: Bool) {
        do {
            let draggedFetch = FetchDescriptor<Task>(predicate: #Predicate { $0.id == draggedTaskID && $0.isTemplateComponent })
            guard let dragged = try modelContext.fetch(draggedFetch).first else { return }
            
            let targetFetch = FetchDescriptor<Task>(predicate: #Predicate { $0.id == targetTaskID && $0.isTemplateComponent })
            guard let target = try modelContext.fetch(targetFetch).first else { return }
            
            // Reparent if needed
            if dragged.parentTask?.id != parentOfList?.id {
                dragged.parentTask = parentOfList
            }
            
            var siblings = try fetchSiblings(for: parentOfList, kind: .template)
            siblings.removeAll { $0.id == dragged.id }
            
            guard let targetIndex = siblings.firstIndex(where: { $0.id == target.id }) else { return }
            
            let insertionIndex = moveBeforeTarget ? targetIndex : targetIndex + 1
            
            if insertionIndex >= siblings.count {
                siblings.append(dragged)
            } else {
                siblings.insert(dragged, at: insertionIndex)
            }
            
            // Update display orders
            for (index, task) in siblings.enumerated() {
                task.displayOrder = index
            }
            
            try modelContext.save()
            resequenceDisplayOrder(for: parentOfList, kind: .template)
            invalidateChildTaskCache(for: .template)
        } catch {
            print("Error moving template task: \(error)")
        }
    }
}
