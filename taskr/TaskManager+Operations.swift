import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Generic Operations

    func deleteTasks(_ tasks: [Task]) {
        guard !tasks.isEmpty else { return }
        
        // Collect all tasks to delete (including descendants)
        var allTasksToDelete: [Task] = []
        var allIDsToDelete = Set<UUID>()
        
        func collectTasksRecursively(_ task: Task) {
            allTasksToDelete.append(task)
            allIDsToDelete.insert(task.id)
            
            // Recursively collect descendants
            if let children = task.subtasks {
                for child in children {
                    collectTasksRecursively(child)
                }
            }
        }
        
        // Collect all tasks and their descendants
        for task in tasks {
            collectTasksRecursively(task)
        }
        
        // Group by parent to handle resequencing efficiently (only for top-level tasks)
        let tasksByParent = Dictionary(grouping: tasks) { $0.parentTask }
        
        // Delete all tasks explicitly (children first to avoid issues)
        // Sort by depth (deepest first) to delete children before parents
        let sortedTasks = allTasksToDelete.sorted { task1, task2 in
            func depth(of task: Task) -> Int {
                var count = 0
                var current = task.parentTask
                while current != nil {
                    count += 1
                    current = current?.parentTask
                }
                return count
            }
            return depth(of: task1) > depth(of: task2)
        }
        
        for task in sortedTasks {
            modelContext.delete(task)
        }
        
        do {
            try modelContext.save()
            
            // Ensure all deletes are fully processed
            modelContext.processPendingChanges()
            
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
    
    // moveTasks was unused and removed.

    
    // moveItem and MoveDirection are defined in TaskManager+OrderingHelpers.swift
    
    // resequenceDisplayOrder and nextDisplayOrder are defined in TaskManager+OrderingHelpers.swift
}
