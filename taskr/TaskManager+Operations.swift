import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Generic Operations

    func deleteTasks(_ tasks: [Task]) {
        guard !tasks.isEmpty else { return }
        
        // Collect all IDs that will be deleted (including descendants via cascade)
        // BEFORE we delete, so we can properly clean up collapsed state
        var allIDsToDelete = Set<UUID>()
        for task in tasks {
            allIDsToDelete.insert(task.id)
            // Recursively collect all descendant IDs
            collectDescendantIDs(of: task, into: &allIDsToDelete)
        }
        
        // Group by parent to handle resequencing efficiently
        let tasksByParent = Dictionary(grouping: tasks) { $0.parentTask }
        
        // Delete the tasks (cascade will handle children)
        for task in tasks {
            modelContext.delete(task)
        }
        
        do {
            try modelContext.save()
            
            // Resequence siblings for each affected parent
            for (parent, _) in tasksByParent {
                if let first = tasks.first {
                    let kind: TaskListKind = first.isTemplateComponent ? .template : .live
                    resequenceDisplayOrder(for: parent, kind: kind)
                }
            }
            
            // Prune collapsed state for all deleted IDs
            pruneCollapsedState(removingIDs: allIDsToDelete)
            
            // Invalidate caches
            invalidateChildTaskCache(for: nil)
            invalidateVisibleTasksCache()
            
        } catch {
            print("Error deleting tasks: \(error)")
        }
    }
    
    private func collectDescendantIDs(of task: Task, into set: inout Set<UUID>) {
        guard let children = task.subtasks else { return }
        for child in children {
            set.insert(child.id)
            collectDescendantIDs(of: child, into: &set)
        }
    }
    
    // moveTasks was unused and removed.

    
    // moveItem and MoveDirection are defined in TaskManager+OrderingHelpers.swift
    
    // resequenceDisplayOrder and nextDisplayOrder are defined in TaskManager+OrderingHelpers.swift
}
