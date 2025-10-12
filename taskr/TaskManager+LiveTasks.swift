import SwiftUI
import SwiftData

extension TaskManager {
    // MARK: - Context menu actions (live tasks)

    func moveTaskUp(_ task: Task) {
        guard !task.isTemplateComponent else { return }
        moveItem(task, kind: .live, direction: .up)
    }

    func moveTaskDown(_ task: Task) {
        guard !task.isTemplateComponent else { return }
        moveItem(task, kind: .live, direction: .down)
    }

    func canMoveTaskUp(_ task: Task) -> Bool {
        guard !task.isTemplateComponent else { return false }
        do {
            let siblings = try fetchSiblings(for: task.parentTask, kind: .live)
            guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return false }
            return index > 0
        } catch {
            return false
        }
    }

    func canMoveTaskDown(_ task: Task) -> Bool {
        guard !task.isTemplateComponent else { return false }
        do {
            let siblings = try fetchSiblings(for: task.parentTask, kind: .live)
            guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return false }
            return index < siblings.count - 1
        } catch {
            return false
        }
    }

    @discardableResult
    func duplicateTask(_ task: Task) -> Task? {
        guard !task.isTemplateComponent else { return nil }
        let parent = task.parentTask
        do {
            let siblings = try fetchLiveSiblings(for: parent)
            for sibling in siblings where sibling.id != task.id && sibling.displayOrder > task.displayOrder {
                sibling.displayOrder += 1
            }

            let duplicateName = makeDuplicateName(for: task, among: siblings)
            let duplicated = cloneTaskSubtree(
                task,
                parent: parent,
                displayOrder: task.displayOrder + 1,
                overrideName: duplicateName
            )
            try modelContext.save()
            resequenceDisplayOrder(for: parent)
            return duplicated
        } catch {
            print("Error duplicating task: \(error)")
            return nil
        }
    }

    func moveTask(
        draggedTaskID: UUID,
        targetTaskID: UUID,
        parentOfList: Task?,
        moveBeforeTarget: Bool
    ) {
        if draggedTaskID == targetTaskID { return }

        let predicate: Predicate<Task>
        if let parentId = parentOfList?.id {
            predicate = #Predicate<Task> {
                !$0.isTemplateComponent && $0.parentTask?.id == parentId
            }
        } else {
            predicate = #Predicate<Task> {
                !$0.isTemplateComponent && $0.parentTask == nil
            }
        }
        let descriptor = FetchDescriptor<Task>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.displayOrder)]
        )

        do {
            var currentSiblings = try modelContext.fetch(descriptor)

            guard let draggedTaskIndex = currentSiblings.firstIndex(where: { $0.id == draggedTaskID }) else {
                print("Error: Dragged task (ID: \(draggedTaskID)) not found among siblings.")
                return
            }
            let taskToMove = currentSiblings.remove(at: draggedTaskIndex)

            guard let targetTaskNewIndexInModifiedList = currentSiblings.firstIndex(where: { $0.id == targetTaskID }) else {
                print("Error: Target task (ID: \(targetTaskID)) not found after removing dragged task.")
                currentSiblings.insert(taskToMove, at: min(draggedTaskIndex, currentSiblings.count))
                for (newOrder, task) in currentSiblings.enumerated() where task.displayOrder != newOrder {
                    task.displayOrder = newOrder
                }
                try? modelContext.save()
                return
            }

            var insertionIndex = targetTaskNewIndexInModifiedList
            if !moveBeforeTarget {
                insertionIndex += 1
            }

            insertionIndex = max(0, min(insertionIndex, currentSiblings.count))

            currentSiblings.insert(taskToMove, at: insertionIndex)
            guard let updatedIndex = currentSiblings.firstIndex(where: { $0.id == draggedTaskID }) else {
                print("Error: Unable to locate dragged task after reinsertion.")
                return
            }

            if updatedIndex == draggedTaskIndex {
                return
            }

            let start = min(draggedTaskIndex, updatedIndex)
            let end = max(draggedTaskIndex, updatedIndex)

            var didUpdateOrder = false
            for idx in start...end {
                let task = currentSiblings[idx]
                if task.displayOrder != idx {
                    task.displayOrder = idx
                    didUpdateOrder = true
                }
            }

            guard didUpdateOrder else { return }

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                print("Error saving task reorder for parent \(parentOfList?.name ?? "nil"): \(error)")
            }
        } catch {
            print("Error moving task with ID \(draggedTaskID): \(error)")
        }
    }

    @discardableResult
    func addSubtask(to parent: Task) -> Task? {
        guard !parent.isTemplateComponent else { return nil }
        let placeAtTop = UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey)
        let displayOrder = getDisplayOrderForInsertion(
            for: parent,
            placeAtTop: placeAtTop,
            in: modelContext
        )

        let newTask = Task(
            name: "New Subtask",
            isCompleted: false,
            creationDate: Date(),
            displayOrder: displayOrder,
            isTemplateComponent: false,
            parentTask: parent
        )
        modelContext.insert(newTask)
        do {
            try modelContext.save()
            setTaskExpanded(parent.id, expanded: true)
            resequenceDisplayOrder(for: parent)
            return newTask
        } catch {
            print("Error adding subtask: \(error)")
            return nil
        }
    }

    func deleteTask(_ task: Task) {
        guard !task.isTemplateComponent else { return }
        let parent = task.parentTask
        let subtreeIDs = collectSubtreeIDs(for: task)

        if !subtreeIDs.isEmpty {
            let previousCollapsed = collapsedTaskIDs
            collapsedTaskIDs.subtract(subtreeIDs)
            if collapsedTaskIDs != previousCollapsed {
                persistCollapsedState()
            }

            if !selectedTaskIDs.isEmpty {
                selectedTaskIDs.removeAll { subtreeIDs.contains($0) }
            }

            if let anchor = selectionAnchorID, subtreeIDs.contains(anchor) {
                selectionAnchorID = nil
            }

            if let cursor = selectionCursorID, subtreeIDs.contains(cursor) {
                selectionCursorID = nil
            }

            if let pending = pendingInlineEditTaskID, subtreeIDs.contains(pending) {
                pendingInlineEditTaskID = nil
            }
        }

        deleteSubtree(task)

        do {
            try modelContext.save()
            resequenceDisplayOrder(for: parent)
            pruneCollapsedState()
        } catch {
            print("Error deleting task: \(error)")
        }
    }

    func toggleTaskCompletion(taskID: UUID) {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate {
            $0.id == taskID && !$0.isTemplateComponent
        })
        do {
            if let taskToToggle = try modelContext.fetch(descriptor).first {
                taskToToggle.isCompleted.toggle()
                completionMutationVersion &+= 1
                try modelContext.save()
            }
        } catch {
            print("Error toggling task: \(error)")
        }
    }

    func clearCompletedTasks() {
        withAnimation(nil) {
            let predicate = #Predicate<Task> { $0.isCompleted && !$0.isTemplateComponent }
            do {
                let completedCandidates = try modelContext.fetch(FetchDescriptor<Task>(predicate: predicate))
                if completedCandidates.isEmpty { return }

                let allowClearingStruckDescendants = UserDefaults.standard.bool(forKey: allowClearingStruckDescendantsPreferenceKey)
                let targets: [Task]
                if allowClearingStruckDescendants {
                    targets = completedCandidates
                } else {
                    targets = completedCandidates.filter { isSubtreeCompleted($0) }
                }
                if targets.isEmpty { return }

                let targetIDs = Set(targets.map { $0.id })
                let topLevelDeletions = targets.filter { task in
                    var current = task.parentTask
                    while let parent = current {
                        if targetIDs.contains(parent.id) { return false }
                        current = parent.parentTask
                    }
                    return true
                }
                if topLevelDeletions.isEmpty { return }

                let topLevelDeletionIDs = Set(topLevelDeletions.map { $0.id })
                var parentIDsToResequence = Set<UUID?>()
                for task in topLevelDeletions {
                    if let parentID = task.parentTask?.id {
                        if !topLevelDeletionIDs.contains(parentID) {
                            parentIDsToResequence.insert(parentID)
                        }
                    } else {
                        parentIDsToResequence.insert(nil)
                    }
                }

                for task in topLevelDeletions {
                    modelContext.delete(task)
                }

                try modelContext.save()
                for parentID in parentIDsToResequence {
                    let parentTask: Task?
                    if let id = parentID {
                        parentTask = try modelContext.fetch(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })).first
                    } else {
                        parentTask = nil
                    }
                    resequenceDisplayOrder(for: parentTask)
                }
                pruneCollapsedState()
            } catch {
                print("Error clearing completed tasks: \(error)")
            }
        }
    }

    func normalizeDisplayOrdersIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: normalizedDisplayOrderMigrationDoneKey) { return }
        let legacy = defaults.string(forKey: newTaskPositionPreferenceKey)
        guard legacy == NewTaskPosition.top.rawValue else {
            defaults.set(true, forKey: normalizedDisplayOrderMigrationDoneKey)
            return
        }
        do {
            let all = try modelContext.fetch(FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent }))
            var parentIDs = Set<UUID?>()
            for t in all { parentIDs.insert(t.parentTask?.id) }

            for pID in parentIDs {
                let predicate: Predicate<Task> = pID.map { id in
                    #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask?.id == id }
                } ?? #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil }
                let siblings = try modelContext.fetch(
                    FetchDescriptor<Task>(
                        predicate: predicate,
                        sortBy: [SortDescriptor(\.displayOrder, order: .reverse)]
                    )
                )
                var hasChanges = false
                for (i, t) in siblings.enumerated() {
                    if t.displayOrder != i {
                        t.displayOrder = i
                        hasChanges = true
                    }
                }
                if hasChanges { try modelContext.save() }
            }
            defaults.set(true, forKey: normalizedDisplayOrderMigrationDoneKey)
        } catch {
            print("Normalization migration failed: \(error)")
            defaults.set(true, forKey: normalizedDisplayOrderMigrationDoneKey)
        }
    }

    // MARK: - Helpers

    func fetchLiveSiblings(for parent: Task?) throws -> [Task] {
        try fetchSiblings(for: parent, kind: .live)
    }

    private func deleteSubtree(_ task: Task) {
        let children = task.subtasks ?? []
        for child in children where !child.isTemplateComponent {
            deleteSubtree(child)
        }
        modelContext.delete(task)
    }

    private func collectSubtreeIDs(for task: Task) -> Set<UUID> {
        var identifiers: Set<UUID> = [task.id]
        let children = task.subtasks ?? []
        for child in children where !child.isTemplateComponent {
            identifiers.formUnion(collectSubtreeIDs(for: child))
        }
        return identifiers
    }

    func getNextDisplayOrder(
        for parent: Task?,
        in context: ModelContext
    ) -> Int {
        nextDisplayOrder(for: parent, kind: .live, in: context)
    }

    func getDisplayOrderForInsertion(
        for parent: Task?,
        placeAtTop: Bool,
        in context: ModelContext
    ) -> Int {
        displayOrderForInsertion(
            for: parent,
            kind: .live,
            placeAtTop: placeAtTop,
            in: context
        )
    }

    func resequenceDisplayOrder(for parent: Task?) {
        resequenceDisplayOrder(for: parent, kind: .live)
    }

    func isSubtreeCompleted(_ task: Task) -> Bool {
        if !task.isCompleted { return false }
        guard let subs = task.subtasks, !subs.isEmpty else { return true }
        for child in subs { if !isSubtreeCompleted(child) { return false } }
        return true
    }

    private func cloneTaskSubtree(
        _ source: Task,
        parent: Task?,
        displayOrder: Int,
        overrideName: String? = nil
    ) -> Task {
        let cloned = Task(
            name: overrideName ?? source.name,
            isCompleted: source.isCompleted,
            creationDate: Date(),
            displayOrder: displayOrder,
            isTemplateComponent: false,
            parentTask: parent
        )
        modelContext.insert(cloned)

        let childCandidates = (source.subtasks ?? [])
            .filter { !$0.isTemplateComponent }
            .sorted { $0.displayOrder < $1.displayOrder }
        for (index, child) in childCandidates.enumerated() {
            _ = cloneTaskSubtree(child, parent: cloned, displayOrder: index)
        }
        return cloned
    }

    private func makeDuplicateName(for task: Task, among siblings: [Task]) -> String {
        let baseName = task.name
        var candidate = "\(baseName) (copy)"
        let siblingNames = Set(siblings.map { $0.name })
        if !siblingNames.contains(candidate) { return candidate }

        var index = 2
        while siblingNames.contains("\(baseName) (copy \(index))") {
            index += 1
        }
        candidate = "\(baseName) (copy \(index))"
        return candidate
    }
}
