import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Expansion State Management

    func isTaskExpanded(_ taskID: UUID) -> Bool {
        !collapsedTaskIDs.contains(taskID)
    }

    func toggleTaskExpansion(_ taskID: UUID) {
        performCollapseTransition {
            let willCollapse = !collapsedTaskIDs.contains(taskID)
            if willCollapse {
                collapsedTaskIDs.insert(taskID)
            } else {
                collapsedTaskIDs.remove(taskID)
            }
            persistCollapsedState()
            if willCollapse {
                pruneSelectionToVisibleTasks()
            }
        }
    }

    func setTaskExpanded(_ taskID: UUID, expanded: Bool) {
        performCollapseTransition {
            let wasCollapsed = collapsedTaskIDs.contains(taskID)
            if expanded {
                collapsedTaskIDs.remove(taskID)
            } else {
                collapsedTaskIDs.insert(taskID)
            }
            persistCollapsedState()
            if !expanded && !wasCollapsed {
                pruneSelectionToVisibleTasks()
            }
        }
    }

    func setExpandedState(for taskIDs: [UUID], expanded: Bool, kind: TaskListKind = .live) {
        let uniqueIDs = Set(taskIDs)
        guard !uniqueIDs.isEmpty else { return }

        let parentIDs = uniqueIDs.filter { hasCachedChildren(forParentID: $0, kind: kind) }
        guard !parentIDs.isEmpty else { return }

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
            collapsedTaskIDs = updated
            persistCollapsedState()
            if !expanded {
                pruneSelectionToVisibleTasks()
            }
        }
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
            if pruned != collapsedTaskIDs {
                collapsedTaskIDs = pruned
                persistCollapsedState()
                invalidateVisibleTasksCache()
            }
        } else {
            // Slow path: fetch all tasks and intersect
            do {
                let tasks = try modelContext.fetch(FetchDescriptor<Task>())
                let existingIDs = Set(tasks.map { $0.id })
                let pruned = collapsedTaskIDs.intersection(existingIDs)
                if pruned != collapsedTaskIDs {
                    collapsedTaskIDs = pruned
                    persistCollapsedState()
                    invalidateVisibleTasksCache()
                }
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
}
