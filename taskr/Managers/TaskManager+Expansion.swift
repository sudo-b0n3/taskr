import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Expansion State Management

    func applyCollapsedState(
        _ updated: Set<UUID>,
        persist: Bool = true,
        pruneSelection: Bool = false,
        notify: Bool = true
    ) {
        guard updated != collapsedTaskIDs else { return }
        collapsedTaskIDs = updated
        if persist {
            persistCollapsedState()
        }
        invalidateVisibleTasksCache()
        if pruneSelection {
            pruneSelectionToVisibleTasks()
        }
        if notify {
            objectWillChange.send()
        }
    }

    func isTaskExpanded(_ taskID: UUID) -> Bool {
        !collapsedTaskIDs.contains(taskID)
    }

    func toggleTaskExpansion(_ taskID: UUID) {
        TaskrDiagnostics.logExpansion("toggleTaskExpansion begin id=\(taskID.uuidString)")
        TaskrDiagnostics.signpostBegin(TaskrDiagnostics.Signpost.toggleExpansion, message: taskID.uuidString)
        performCollapseTransition {
            var updated = collapsedTaskIDs
            let willCollapse = !updated.contains(taskID)
            if willCollapse {
                updated.insert(taskID)
            } else {
                updated.remove(taskID)
            }
            applyCollapsedState(updated, pruneSelection: willCollapse)
        }
        TaskrDiagnostics.signpostEnd(TaskrDiagnostics.Signpost.toggleExpansion, message: taskID.uuidString)
        TaskrDiagnostics.logExpansion("toggleTaskExpansion end id=\(taskID.uuidString) expanded=\(!collapsedTaskIDs.contains(taskID))")
    }

    func setTaskExpanded(_ taskID: UUID, expanded: Bool) {
        TaskrDiagnostics.logExpansion("setTaskExpanded begin id=\(taskID.uuidString) expanded=\(expanded)")
        TaskrDiagnostics.signpostBegin(TaskrDiagnostics.Signpost.setTaskExpanded, message: "\(taskID.uuidString) expanded=\(expanded)")
        performCollapseTransition {
            var updated = collapsedTaskIDs
            let wasCollapsed = updated.contains(taskID)
            if expanded {
                updated.remove(taskID)
            } else {
                updated.insert(taskID)
            }
            applyCollapsedState(updated, pruneSelection: !expanded && !wasCollapsed)
        }
        TaskrDiagnostics.signpostEnd(TaskrDiagnostics.Signpost.setTaskExpanded, message: "\(taskID.uuidString) expanded=\(expanded)")
        TaskrDiagnostics.logExpansion("setTaskExpanded end id=\(taskID.uuidString) expanded=\(!collapsedTaskIDs.contains(taskID))")
    }

    func setExpandedState(for taskIDs: [UUID], expanded: Bool, kind: TaskListKind = .live) {
        let uniqueIDs = Set(taskIDs)
        guard !uniqueIDs.isEmpty else { return }

        let parentIDs = uniqueIDs.filter { hasCachedChildren(forParentID: $0, kind: kind) }
        guard !parentIDs.isEmpty else { return }

        TaskrDiagnostics.logExpansion("setExpandedState begin ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)")
        TaskrDiagnostics.signpostBegin(TaskrDiagnostics.Signpost.setExpandedState, message: "ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)")
        performCollapseTransition {
            var updated = collapsedTaskIDs
            var changed = false

            for id in parentIDs {
                if expanded {
                    if updated.remove(id) != nil {
                        changed = true
                    }
                } else {
                    if updated.insert(id).inserted {
                        changed = true
                    }
                }
            }

            guard changed else { return }
            applyCollapsedState(updated, pruneSelection: !expanded)
        }
        TaskrDiagnostics.signpostEnd(TaskrDiagnostics.Signpost.setExpandedState, message: "ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)")
        TaskrDiagnostics.logExpansion("setExpandedState end ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)")
    }

    func setExpandedStateRecursively(for taskIDs: [UUID], expanded: Bool, kind: TaskListKind = .live) {
        let uniqueIDs = Set(taskIDs)
        guard !uniqueIDs.isEmpty else { return }

        let parentIDs = collectExpandableDescendantIDs(from: uniqueIDs, kind: kind)
        guard !parentIDs.isEmpty else { return }

        TaskrDiagnostics.logExpansion("setExpandedStateRecursively begin ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)")
        TaskrDiagnostics.signpostBegin(
            TaskrDiagnostics.Signpost.setExpandedState,
            message: "recursive ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)"
        )
        performCollapseTransition {
            var updated = collapsedTaskIDs
            var changed = false

            for id in parentIDs {
                if expanded {
                    if updated.remove(id) != nil {
                        changed = true
                    }
                } else {
                    if updated.insert(id).inserted {
                        changed = true
                    }
                }
            }

            guard changed else { return }
            applyCollapsedState(updated, pruneSelection: !expanded)
        }
        TaskrDiagnostics.signpostEnd(
            TaskrDiagnostics.Signpost.setExpandedState,
            message: "recursive ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)"
        )
        TaskrDiagnostics.logExpansion("setExpandedStateRecursively end ids=\(parentIDs.count) expanded=\(expanded) kind=\(kind)")
    }

    func requestInlineEdit(for taskID: UUID) {
        if pendingInlineEditTaskID == taskID {
            pendingInlineEditTaskID = nil
        }
        pendingInlineEditTaskID = taskID
    }

    func pruneCollapsedState(removingIDs idsToRemove: Set<UUID>? = nil) {
        if let idsToRemove = idsToRemove {
            // Fast path: we know which IDs to remove
            let pruned = collapsedTaskIDs.subtracting(idsToRemove)
            applyCollapsedState(pruned)
        } else {
            // Slow path: fetch all tasks and intersect
            do {
                let tasks = try modelContext.fetch(FetchDescriptor<Task>())
                // On some startups SwiftData can briefly return no rows before the store is ready.
                // Skipping prune here prevents wiping persisted collapsed state and expanding everything.
                if tasks.isEmpty {
                    return
                }
                let existingIDs = Set(tasks.map { $0.id })
                let pruned = collapsedTaskIDs.intersection(existingIDs)
                applyCollapsedState(pruned)
                markInitialCollapsedPruneCompleted()
            } catch {
                print("Error pruning collapsed state: \(error)")
            }
        }
    }

    // MARK: - Collapsed state persistence

    func loadCollapsedState() {
        let defaults = UserDefaults.standard
        if let stored = defaults.array(forKey: collapsedTaskIDsPreferenceKey) as? [String] {
            let ids = stored.compactMap { UUID(uuidString: $0) }
            collapsedTaskIDs = Set(ids)
        }
    }

    func persistCollapsedState() {
        let defaults = UserDefaults.standard
        let ids = collapsedTaskIDs.map { $0.uuidString }
        defaults.set(ids, forKey: collapsedTaskIDsPreferenceKey)
    }

    private func collectExpandableDescendantIDs(from rootTaskIDs: Set<UUID>, kind: TaskListKind) -> Set<UUID> {
        ensureChildCache(for: kind)
        let childMap = childTaskCache[kind] ?? [:]

        var visited: Set<UUID> = []
        var expandableIDs: Set<UUID> = []
        var stack = Array(rootTaskIDs)

        while let currentID = stack.popLast() {
            guard visited.insert(currentID).inserted else { continue }
            let children = (childMap[currentID] ?? []).filter { $0.modelContext != nil && !$0.isDeleted }
            guard !children.isEmpty else { continue }

            expandableIDs.insert(currentID)
            for child in children {
                stack.append(child.id)
            }
        }

        return expandableIDs
    }
}
