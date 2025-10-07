import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Expansion State Management

    func isTaskExpanded(_ taskID: UUID) -> Bool {
        !collapsedTaskIDs.contains(taskID)
    }

    func toggleTaskExpansion(_ taskID: UUID) {
        if collapsedTaskIDs.contains(taskID) {
            collapsedTaskIDs.remove(taskID)
        } else {
            collapsedTaskIDs.insert(taskID)
        }
        persistCollapsedState()
    }

    func setTaskExpanded(_ taskID: UUID, expanded: Bool) {
        if expanded {
            collapsedTaskIDs.remove(taskID)
        } else {
            collapsedTaskIDs.insert(taskID)
        }
        persistCollapsedState()
    }

    func requestInlineEdit(for taskID: UUID) {
        if pendingInlineEditTaskID == taskID {
            pendingInlineEditTaskID = nil
        }
        pendingInlineEditTaskID = taskID
    }

    func pruneCollapsedState() {
        do {
            let tasks = try modelContext.fetch(FetchDescriptor<Task>())
            let existingIDs = Set(tasks.map { $0.id })
            let pruned = collapsedTaskIDs.intersection(existingIDs)
            if pruned != collapsedTaskIDs {
                collapsedTaskIDs = pruned
                persistCollapsedState()
            }
        } catch {
            print("Error pruning collapsed state: \(error)")
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

    private func persistCollapsedState() {
        let defaults = UserDefaults.standard
        let ids = collapsedTaskIDs.map { $0.uuidString }
        defaults.set(ids, forKey: collapsedTaskIDsPreferenceKey)
    }
}
