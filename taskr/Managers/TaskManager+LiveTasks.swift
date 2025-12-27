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
        return performListMutation {
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
    }

    func deleteSelectedTasks() {
        let tasks = selectedLiveTasks()
        guard !tasks.isEmpty else { return }
        let selectedSet = Set(tasks.map(\.id))
        let rootIDs = tasks
            .filter { !hasSelectedAncestor($0, selectedSet: selectedSet) }
            .map(\.id)

        guard !rootIDs.isEmpty else { return }

        // Before deleting, find the index to select after deletion
        let visibleIDs = snapshotVisibleTaskIDs()
        let selectedIndices = visibleIDs.indices.filter { selectedSet.contains(visibleIDs[$0]) }
        let lowestSelectedIndex = selectedIndices.min()

        var tasksToDelete: [Task] = []
        for id in rootIDs {
            guard let task = task(withID: id) else { continue }
            tasksToDelete.append(task)
        }
        
        // Use generic helper
        deleteTasks(tasksToDelete)

        // After deletion, select the task at the same position (or the last task if we deleted at the end)
        let newVisibleIDs = snapshotVisibleTaskIDs()
        guard !newVisibleIDs.isEmpty else {
            clearSelection()
            return
        }

        if let lowestIndex = lowestSelectedIndex {
            // Select the task that now occupies the lowest selected position
            // If that's beyond the list, select the last task
            let targetIndex = min(lowestIndex, newVisibleIDs.count - 1)
            let targetID = newVisibleIDs[targetIndex]
            replaceSelection(with: targetID)
        } else {
            clearSelection()
        }
    }

    func duplicateSelectedTasks() {
        let tasks = selectedLiveTasks()
        guard !tasks.isEmpty else { return }
        let selectedSet = Set(tasks.map(\.id))
        let rootTasks = tasks.filter { !hasSelectedAncestor($0, selectedSet: selectedSet) }
        guard !rootTasks.isEmpty else { return }

        let grouped = Dictionary(grouping: rootTasks) { $0.parentTask?.id }
        var parentsToResequence: [Task?] = []
        var duplicatedIDs: [UUID] = []

        performListMutation {
            do {
                for (_, group) in grouped {
                    guard let sample = group.first else { continue }
                    let parent = sample.parentTask
                    let siblings = try fetchSiblings(for: parent, kind: .live)
                    let groupSet = Set(group.map { $0.id })
                    guard !groupSet.isEmpty else { continue }

                    var existingNames = Set(siblings.map { $0.name })
                    var orderIndex = 0

                    for sibling in siblings {
                        if sibling.displayOrder != orderIndex {
                            sibling.displayOrder = orderIndex
                        }
                        orderIndex += 1

                        if groupSet.contains(sibling.id) {
                            let duplicateName = makeDuplicateName(for: sibling, existingNames: &existingNames)
                            let duplicate = cloneTaskSubtree(
                                sibling,
                                parent: parent,
                                displayOrder: orderIndex,
                                overrideName: duplicateName
                            )
                            duplicatedIDs.append(duplicate.id)
                            orderIndex += 1
                        }
                    }

                    parentsToResequence.append(parent)
                }

                guard !duplicatedIDs.isEmpty else { return }

                try modelContext.save()

                for parent in parentsToResequence {
                    resequenceDisplayOrder(for: parent)
                }
            } catch {
                modelContext.rollback()
                print("Error duplicating selected tasks: \(error)")
                return
            }

            let visibleIDs = snapshotVisibleTaskIDs()
            var remaining = Set(duplicatedIDs)
            var orderedDuplicates: [UUID] = []
            orderedDuplicates.reserveCapacity(duplicatedIDs.count)

            for id in visibleIDs where remaining.contains(id) {
                orderedDuplicates.append(id)
                remaining.remove(id)
            }
            if !remaining.isEmpty {
                for id in duplicatedIDs where remaining.contains(id) {
                    orderedDuplicates.append(id)
                    remaining.remove(id)
                }
            }

            if !orderedDuplicates.isEmpty {
                selectTasks(
                    orderedIDs: orderedDuplicates,
                    anchor: orderedDuplicates.first,
                    cursor: orderedDuplicates.last
                )
            }
        }
    }

    func canMarkSelectedTasksCompleted() -> Bool {
        selectedLiveTasks().contains { !$0.isCompleted }
    }

    func markSelectedTasksCompleted() {
        let targets = selectedLiveTasks().filter { !$0.isCompleted }
        guard !targets.isEmpty else { return }

        // Check if move-to-bottom is enabled and find the lowest selected index
        let willMoveToBottom = UserDefaults.standard.bool(forKey: moveCompletedTasksToBottomPreferenceKey)
        var lowestSelectedIndex: Int? = nil
        if willMoveToBottom {
            let visibleIDs = snapshotVisibleTaskIDs()
            let targetIDs = Set(targets.map(\.id))
            let selectedIndices = visibleIDs.indices.filter { targetIDs.contains(visibleIDs[$0]) }
            lowestSelectedIndex = selectedIndices.min()
        }

        performListMutation {
            for task in targets {
                task.isCompleted = true
            }
            moveCompletedTasksToBottomIfNeeded(targets)
        }

        completionMutationVersion &+= 1
        objectWillChange.send()

        do {
            try modelContext.save()
            collapseCompletedParentsIfNeeded(targets)
        } catch {
            modelContext.rollback()
            print("Error marking selected tasks as completed: \(error)")
        }
        
        // After completion, select the task at the original position
        if let lowestIndex = lowestSelectedIndex {
            let newVisibleIDs = snapshotVisibleTaskIDs()
            guard !newVisibleIDs.isEmpty else {
                clearSelection()
                return
            }
            let safeIndex = min(lowestIndex, newVisibleIDs.count - 1)
            let targetID = newVisibleIDs[safeIndex]
            replaceSelection(with: targetID)
        }
    }

    func canMarkSelectedTasksUncompleted() -> Bool {
        selectedLiveTasks().contains { $0.isCompleted }
    }

    func markSelectedTasksUncompleted() {
        let targets = selectedLiveTasks().filter { $0.isCompleted }
        guard !targets.isEmpty else { return }

        performListMutation {
            for task in targets {
                task.isCompleted = false
            }
        }

        completionMutationVersion &+= 1

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            print("Error marking selected tasks as uncompleted: \(error)")
        }
    }

    func toggleSelectedTasksCompletion() {
        let targets = selectedLiveTasks()
        guard !targets.isEmpty else { return }

        let hasIncomplete = targets.contains { !$0.isCompleted }
        if hasIncomplete {
            markSelectedTasksCompleted()
        } else {
            markSelectedTasksUncompleted()
        }
    }

    func canDuplicateSelectedTasks() -> Bool {
        !selectedLiveTasks().isEmpty
    }

    func canMoveSelectedTasksUp() -> Bool {
        guard selectedTaskIDs.count > 1,
              let context = selectedSiblingContext(),
              let firstIndex = context.indices.first else {
            return false
        }
        return firstIndex > 0
    }

    func canMoveSelectedTasksDown() -> Bool {
        guard selectedTaskIDs.count > 1,
              let context = selectedSiblingContext(),
              let lastIndex = context.indices.last else {
            return false
        }
        return lastIndex < context.siblings.count - 1
    }

    func moveSelectedTasksUp() {
        guard selectedTaskIDs.count > 1 else {
            if let first = selectedTaskIDs.first,
               let task = task(withID: first) {
                moveTaskUp(task)
                // Request scroll to follow the moved task
                requestScrollTo(first)
            }
            return
        }

        guard let context = selectedSiblingContext(),
              let firstIndex = context.indices.first,
              firstIndex > 0 else {
            return
        }

        let block = context.siblings.filter { context.selectedSet.contains($0.id) }
        guard !block.isEmpty else { return }

        var reordered = context.siblings.filter { !context.selectedSet.contains($0.id) }
        let insertionIndex = max(0, firstIndex - 1)
        reordered.insert(contentsOf: block, at: insertionIndex)

        applySiblingOrder(reordered, parent: context.parent, selectedSet: context.selectedSet)
        
        // Trigger scroll to follow the moved selection
        if let firstSelectedID = block.first?.id {
            requestScrollTo(firstSelectedID)
        }
    }

    func moveSelectedTasksDown() {
        guard selectedTaskIDs.count > 1 else {
            if let first = selectedTaskIDs.first,
               let task = task(withID: first) {
                moveTaskDown(task)
                // Request scroll to follow the moved task
                requestScrollTo(first)
            }
            return
        }

        guard let context = selectedSiblingContext(),
              let lastIndex = context.indices.last else {
            return
        }

        let afterIndex = lastIndex + 1
        guard afterIndex < context.siblings.count else { return }

        let block = context.siblings.filter { context.selectedSet.contains($0.id) }
        guard !block.isEmpty else { return }

        var reordered = context.siblings.filter { !context.selectedSet.contains($0.id) }
        let blockCount = block.count
        let insertionIndex = afterIndex - blockCount
        let targetIndex = min(reordered.count, insertionIndex + 1)
        reordered.insert(contentsOf: block, at: targetIndex)

        applySiblingOrder(reordered, parent: context.parent, selectedSet: context.selectedSet)
        
        // Trigger scroll to follow the moved selection
        if let lastSelectedID = block.last?.id {
            requestScrollTo(lastSelectedID)
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
        performListMutation {
            modelContext.insert(newTask)
        }
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
        // Use generic helper
        deleteTasks([task])
    }

    func toggleTaskCompletion(taskID: UUID) {
        guard let task = task(withID: taskID) else { return }
        toggleTaskCompletion(task: task)
    }

    func toggleTaskCompletion(task: Task) {
        guard !task.isTemplateComponent else { return }
        
        // Check if the task is selected and if "move to bottom" is enabled
        let taskWasSelected = selectedTaskIDs.contains(task.id)
        let willMoveToBottom = UserDefaults.standard.bool(forKey: moveCompletedTasksToBottomPreferenceKey)
        
        // Before completion, find the task's position so we can select an adjacent task
        var indexToSelectAfter: Int? = nil
        if taskWasSelected && willMoveToBottom && !task.isCompleted {
            // Only if completing (not uncompleting) and the setting is on
            let visibleIDs = snapshotVisibleTaskIDs()
            if let currentIndex = visibleIDs.firstIndex(of: task.id) {
                indexToSelectAfter = currentIndex
            }
        }
        
        var isCompletedNow = false
        performListMutation {
            task.isCompleted.toggle()
            isCompletedNow = task.isCompleted
            if isCompletedNow {
                moveCompletedTasksToBottomIfNeeded([task])
            }
        }
        completionMutationVersion &+= 1
        invalidateCompletionCache(for: .live)
        objectWillChange.send()
        do {
            try modelContext.save()
            if isCompletedNow {
                collapseCompletedParentsIfNeeded([task])
            }
        } catch {
            modelContext.rollback()
            print("Error toggling task: \(error)")
        }
        
        // After completion, if the task moved to bottom, select the task at the original position
        if let targetIndex = indexToSelectAfter, isCompletedNow {
            let newVisibleIDs = snapshotVisibleTaskIDs()
            guard !newVisibleIDs.isEmpty else { return }
            // Select the task that now occupies the original position (or the last task if beyond end)
            let safeIndex = min(targetIndex, newVisibleIDs.count - 1)
            let targetID = newVisibleIDs[safeIndex]
            // Only change selection if the target is different from the completed task
            if targetID != task.id {
                replaceSelection(with: targetID)
            }
        }
    }

    func clearCompletedTasks() {
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

            let skipClearingHiddenDescendants = UserDefaults.standard.object(forKey: skipClearingHiddenDescendantsPreferenceKey) as? Bool ?? true
            let visibleTargets: [Task]
            if skipClearingHiddenDescendants {
                let collapsedIDs = collapsedTaskIDs
                var ancestorVisibilityCache: [UUID: Bool] = [:]

                func branchVisible(_ task: Task) -> Bool {
                    if let cached = ancestorVisibilityCache[task.id] {
                        return cached
                    }
                    let visible: Bool
                    if collapsedIDs.contains(task.id) && !task.isCompleted {
                        visible = false
                    } else if let parent = task.parentTask {
                        visible = branchVisible(parent)
                    } else {
                        visible = true
                    }
                    ancestorVisibilityCache[task.id] = visible
                    return visible
                }

                func isVisible(_ task: Task) -> Bool {
                    guard let parent = task.parentTask else { return true }
                    return branchVisible(parent)
                }

                visibleTargets = targets.filter { isVisible($0) }
            } else {
                visibleTargets = targets
            }
            if visibleTargets.isEmpty { return }

            // Filter out tasks that are in a locked thread (task or any ancestor is locked)
            func isInLockedThread(_ task: Task) -> Bool {
                if task.isLocked { return true }
                var current = task.parentTask
                while let parent = current {
                    if parent.isLocked { return true }
                    current = parent.parentTask
                }
                return false
            }

            let unlockedTargets = visibleTargets.filter { !isInLockedThread($0) }
            if unlockedTargets.isEmpty { return }

            let targetIDs = Set(unlockedTargets.map { $0.id })
            let topLevelTasks = unlockedTargets.filter { task in
                var current = task.parentTask
                while let parent = current {
                    if targetIDs.contains(parent.id) { return false }
                    current = parent.parentTask
                }
                return true
            }
            if topLevelTasks.isEmpty { return }

            var uniqueTaskMap: [UUID: Task] = [:]
            for task in topLevelTasks {
                uniqueTaskMap[task.id] = task
            }
            let uniqueTasks = Array(uniqueTaskMap.values)
            
            // Use generic helper
            deleteTasks(uniqueTasks)
        } catch {
            print("Error clearing completed tasks: \(error)")
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
                        sortBy: [SortDescriptor(\.displayOrder, order: .forward)]
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
            invalidateVisibleTasksCache()
            invalidateChildTaskCache(for: .live)
        } catch {
            print("Normalization migration failed: \(error)")
            defaults.set(true, forKey: normalizedDisplayOrderMigrationDoneKey)
            invalidateVisibleTasksCache()
            invalidateChildTaskCache(for: .live)
        }
    }

    // MARK: - Helpers

    func fetchLiveSiblings(for parent: Task?) throws -> [Task] {
        try fetchSiblings(for: parent, kind: .live)
    }

    private func collectSubtreeIDs(for task: Task) -> Set<UUID> {
        var identifiers: Set<UUID> = [task.id]
        var stack: [Task] = [task]

        while let current = stack.popLast() {
            let children: [Task]
            do {
                children = try fetchSiblings(for: current, kind: .live)
            } catch {
                continue
            }
            for child in children where identifiers.insert(child.id).inserted {
                stack.append(child)
            }
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
        var stack: [Task] = [task]

        while let current = stack.popLast() {
            let children: [Task]
            do {
                children = try fetchSiblings(for: current, kind: .live)
            } catch {
                return false
            }

            for child in children {
                if !child.isCompleted { return false }
                stack.append(child)
            }
        }

        return true
    }

    private func collapseCompletedParentsIfNeeded(_ tasks: [Task]) {
        guard UserDefaults.standard.bool(forKey: collapseCompletedParentsPreferenceKey) else { return }
        let parentIDs = tasks.filter { $0.isCompleted }.map(\.id)
        guard !parentIDs.isEmpty else { return }
        performCollapseTransition {
            var updated = collapsedTaskIDs
            var changed = false
            for id in parentIDs {
                if updated.insert(id).inserted {
                    changed = true
                }
            }
            guard changed else { return }
            collapsedTaskIDs = updated
            persistCollapsedState()
            invalidateVisibleTasksCache()
            objectWillChange.send()
            pruneSelectionToVisibleTasks()
        }
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

        let childCandidates: [Task]
        do {
            childCandidates = try fetchSiblings(for: source, kind: .live, order: .forward)
        } catch {
            return cloned
        }

        for (index, child) in childCandidates.enumerated() {
            _ = cloneTaskSubtree(child, parent: cloned, displayOrder: index)
        }
        return cloned
    }

    private func moveCompletedTasksToBottomIfNeeded(_ tasks: [Task]) {
        guard UserDefaults.standard.bool(forKey: moveCompletedTasksToBottomPreferenceKey) else { return }
        let completed = tasks.filter { !$0.isTemplateComponent && $0.isCompleted }
        guard !completed.isEmpty else { return }

        let grouped = Dictionary(grouping: completed) { $0.parentTask }
        var didReorder = false
        for (parent, group) in grouped {
            do {
                var siblings = try fetchSiblings(for: parent, kind: .live)
                let targetIDs = Set(group.map(\.id))
                var completedSiblings: [Task] = []

                siblings.removeAll { task in
                    if targetIDs.contains(task.id) {
                        completedSiblings.append(task)
                        return true
                    }
                    return false
                }

                guard !completedSiblings.isEmpty else { continue }
                completedSiblings.sort { $0.displayOrder < $1.displayOrder }
                siblings.append(contentsOf: completedSiblings)

                for (index, task) in siblings.enumerated() {
                    task.displayOrder = index
                }
                didReorder = true
            } catch {
                continue
            }
        }
        if didReorder {
            invalidateVisibleTasksCache()
            invalidateChildTaskCache(for: .live)
            objectWillChange.send()
        }
    }

    private func makeDuplicateName(for task: Task, among siblings: [Task]) -> String {
        var existingNames = Set(siblings.map { $0.name })
        return makeDuplicateName(for: task, existingNames: &existingNames)
    }

    private func makeDuplicateName(for task: Task, existingNames: inout Set<String>) -> String {
        let baseName = task.name
        var candidate = "\(baseName) (copy)"
        if !existingNames.contains(candidate) {
            existingNames.insert(candidate)
            return candidate
        }

        var index = 2
        while existingNames.contains("\(baseName) (copy \(index))") {
            index += 1
        }
        candidate = "\(baseName) (copy \(index))"
        existingNames.insert(candidate)
        return candidate
    }
    
    // Helper for multi-selection move
    private func selectedSiblingContext() -> SelectedSiblingContext? {
        guard let firstID = selectedTaskIDs.first,
              let firstTask = task(withID: firstID) else { return nil }
        
        let parent = firstTask.parentTask
        guard let siblings = try? fetchSiblings(for: parent, kind: .live) else { return nil }
        
        let selectedSet = Set(selectedTaskIDs)
        
        // Verify all selected tasks share the same parent
        for id in selectedTaskIDs {
            guard let t = task(withID: id), t.parentTask?.id == parent?.id else { return nil }
        }
        
        let indices = siblings.indices.filter { selectedSet.contains(siblings[$0].id) }
        return SelectedSiblingContext(parent: parent, siblings: siblings, selectedSet: selectedSet, indices: indices)
    }
    
    private func applySiblingOrder(_ orderedTasks: [Task], parent: Task?, selectedSet: Set<UUID>) {
        performListMutation {
            for (index, task) in orderedTasks.enumerated() {
                if task.displayOrder != index {
                    task.displayOrder = index
                }
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Error saving reorder: \(error)")
            }
        }
    }
    func moveTask(draggedTaskID: UUID, targetTaskID: UUID, parentOfList: Task?, moveBeforeTarget: Bool) {
        performListMutation {
            guard let dragged = task(withID: draggedTaskID), !dragged.isTemplateComponent else { return }
            guard let target = task(withID: targetTaskID), !target.isTemplateComponent else { return }
            
            // Reparent if needed
            if dragged.parentTask?.id != parentOfList?.id {
                dragged.parentTask = parentOfList
            }
            
            do {
                var siblings = try fetchSiblings(for: parentOfList, kind: .live)
                // Remove dragged from siblings if present (it might be there if parent didn't change)
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
                resequenceDisplayOrder(for: parentOfList)
            } catch {
                print("Error moving task: \(error)")
            }
        }
    }

    // MARK: - Task Locking

    /// Returns true if the task or any of its ancestors is locked
    func isTaskInLockedThread(_ task: Task) -> Bool {
        if task.isLocked { return true }
        var current = task.parentTask
        while let parent = current {
            if parent.isLocked { return true }
            current = parent.parentTask
        }
        return false
    }

    /// Toggle lock state for a single task
    func toggleLockForTask(_ task: Task) {
        guard !task.isTemplateComponent else { return }
        task.isLocked.toggle()
        do {
            try modelContext.save()
            objectWillChange.send()
        } catch {
            print("Error toggling lock for task: \(error)")
        }
    }

    /// Toggle lock state for all selected tasks
    func toggleLockForSelectedTasks() {
        let tasks = selectedLiveTasks()
        guard !tasks.isEmpty else { return }

        // If any task is unlocked, lock all. Otherwise unlock all.
        let hasUnlocked = tasks.contains { !$0.isLocked }
        let newLockState = hasUnlocked

        for task in tasks {
            task.isLocked = newLockState
        }

        do {
            try modelContext.save()
            objectWillChange.send()
        } catch {
            print("Error toggling lock for selected tasks: \(error)")
        }
    }
}

// MARK: - Multi-selection helpers
private extension TaskManager {
    struct SelectedSiblingContext {
        let parent: Task?
        let siblings: [Task]
        let selectedSet: Set<UUID>
        let indices: [Int]
    }

    func selectedLiveTasks() -> [Task] {
        selectedTaskIDs.compactMap { id in
            guard let task = task(withID: id), !task.isTemplateComponent else { return nil }
            return task
        }
    }

    func hasSelectedAncestor(_ task: Task, selectedSet: Set<UUID>) -> Bool {
        var current = task.parentTask
        while let parent = current {
            if selectedSet.contains(parent.id) {
                return true
            }
            current = parent.parentTask
        }
        return false
    }
}
