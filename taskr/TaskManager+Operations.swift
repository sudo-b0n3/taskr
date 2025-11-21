import Foundation
import SwiftData

extension TaskManager {
    // MARK: - Generic Operations

    func deleteTasks(_ tasks: [Task]) {
        guard !tasks.isEmpty else { return }
        
        // Group by parent to handle resequencing efficiently
        let tasksByParent = Dictionary(grouping: tasks) { $0.parentTask }
        
        for task in tasks {
            modelContext.delete(task)
        }
        
        do {
            try modelContext.save()
            
            // Resequence siblings for each affected parent
            for (parent, _) in tasksByParent {
                // We need to know the kind to resequence correctly if we want to be strict,
                // but resequenceDisplayOrder takes a kind.
                // We can infer kind from the tasks or pass it.
                // Since tasks can be mixed (theoretically, but unlikely in UI), let's assume they are same kind.
                if let first = tasks.first {
                    let kind: TaskListKind = first.isTemplateComponent ? .template : .live
                    resequenceDisplayOrder(for: parent, kind: kind)
                }
            }
            
            // Prune collapsed state if needed
            pruneCollapsedState()
            
            // Invalidate caches
            // We should invalidate both if we are unsure, or specific if we know.
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
