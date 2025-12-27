import AppKit
import Foundation
import SwiftData
import SwiftUI

extension TaskManager {
    enum SelectionDirection {
        case up
        case down
    }

    // Note: Core selection logic has been moved to SelectionManager.swift
    // This file now contains higher-level selection operations that require Task objects or specific logic not yet migrated.

    func stepSelection(_ direction: SelectionDirection, extend: Bool) {
        let visibleTasks = snapshotVisibleTasks()
        guard !visibleTasks.isEmpty else {
            clearSelection()
            return
        }
        let visibleIDs = visibleTasks.map(\.id)
        
        // Sync selection first
        // We need to expose syncSelectionWithVisibleIDs or implement it here using SelectionManager
        // For now, let's just use what we have.
        // selectionManager.pruneSelection(to: visibleIDs) // If we had it
        
        let delta = direction == .down ? 1 : -1
        let anchorID = selectionAnchorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let currentCursorID = selectionCursorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? selectedTaskIDs.last
            ?? selectedTaskIDs.first

        if selectedTaskIDs.isEmpty || currentCursorID == nil {
            let index = direction == .down ? 0 : visibleIDs.count - 1
            let id = visibleIDs[index]
            selectTasks(orderedIDs: [id], anchor: id, cursor: id)
            return
        }

        guard let cursorIndex = visibleIDs.firstIndex(of: currentCursorID!) else {
            let index = direction == .down ? 0 : visibleIDs.count - 1
            let id = visibleIDs[index]
            let anchorIndex = anchorID.flatMap { visibleIDs.firstIndex(of: $0) } ?? index
            if extend {
                let lower = min(anchorIndex, index)
                let upper = max(anchorIndex, index)
                let rangeIDs = Array(visibleIDs[lower...upper])
                selectTasks(orderedIDs: rangeIDs, anchor: visibleIDs[anchorIndex], cursor: id)
            } else {
                selectTasks(orderedIDs: [id], anchor: id, cursor: id)
            }
            return
        }

        let nextIndex = max(0, min(visibleIDs.count - 1, cursorIndex + delta))
        let nextID = visibleIDs[nextIndex]

        if extend {
            let anchorIndex = anchorID.flatMap { visibleIDs.firstIndex(of: $0) } ?? cursorIndex
            let lower = min(anchorIndex, nextIndex)
            let upper = max(anchorIndex, nextIndex)
            let rangeIDs = Array(visibleIDs[lower...upper])
            selectTasks(
                orderedIDs: rangeIDs,
                anchor: visibleIDs[anchorIndex],
                cursor: nextID
            )
        } else {
            selectTasks(orderedIDs: [nextID], anchor: nextID, cursor: nextID)
        }
    }

    func copySelectedTasksToPasteboard() {
        guard !selectedTaskIDs.isEmpty else { return }
        var entries: [(task: Task, depth: Int)] = []

        let visibleTasks = snapshotVisibleTasks()
        let cache = Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, $0) })

        for id in selectedTaskIDs {
            guard let task = cache[id] ?? task(withID: id) else { continue }
            let depth = taskDepth(task)
            entries.append((task, depth))
        }

        guard !entries.isEmpty else { return }

        let minDepth = entries.map(\.depth).min() ?? 0
        var lines: [String] = []
        lines.reserveCapacity(entries.count)

        for entry in entries {
            let adjustedDepth = max(0, entry.depth - minDepth)
            let prefix = entry.task.isCompleted ? "(x)" : "()"
            let indentation = adjustedDepth > 0 ? String(repeating: "\t", count: adjustedDepth) : ""
            lines.append("\(indentation)\(prefix) - \(entry.task.name)")
        }

        guard !lines.isEmpty else { return }
        let output = lines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }

    func pruneSelectionToVisibleTasks() {
        let visibleIDs = snapshotVisibleTaskIDs()
        // selectionManager.syncSelectionWithVisibleIDs(visibleIDs) // If exposed
        // For now, manual implementation or rely on SelectionManager to handle it if we add a method
        // Let's implement it manually using public methods
        let visibleSet = Set(visibleIDs)
        let filtered = selectedTaskIDs.filter { visibleSet.contains($0) }
        if filtered.count != selectedTaskIDs.count {
             let newAnchor = selectionAnchorID.flatMap { visibleSet.contains($0) ? $0 : nil }
             let newCursor = selectionCursorID.flatMap { visibleSet.contains($0) ? $0 : nil }
             selectTasks(orderedIDs: filtered, anchor: newAnchor, cursor: newCursor)
        }
    }
    
    func selectAllVisibleTasks() {
        let visibleIDs = snapshotVisibleTaskIDs()
        guard !visibleIDs.isEmpty else {
            clearSelection()
            return
        }
        selectTasks(
            orderedIDs: visibleIDs,
            anchor: visibleIDs.first,
            cursor: visibleIDs.last
        )
    }

    // MARK: - Helper routines

    func snapshotVisibleTasks() -> [Task] {
        if isDemoSwapInProgress {
            return []
        }
        if let cached = visibleLiveTasksCache {
            // Filter out deleted tasks to prevent SwiftData crashes
            let validTasks = cached.filter { $0.modelContext != nil }
            if validTasks.count != cached.count {
                // Cache contained deleted tasks, invalidate and rebuild
                visibleLiveTasksCache = nil
            } else {
                return cached
            }
        }

        ensureChildCache(for: .live)
        let childMap = childTaskCache[.live] ?? [:]
        let roots = childMap[nil as UUID?] ?? []

        var flattened: [Task] = []
        for root in roots.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            appendVisible(task: root, accumulator: &flattened, childMap: childMap)
        }
        visibleLiveTasksCache = flattened
        return flattened
    }

    func snapshotVisibleTasksWithDepth() -> [(task: Task, depth: Int)] {
        if isDemoSwapInProgress {
            return []
        }
        if let cached = visibleLiveTasksWithDepthCache {
            // Filter out deleted tasks to prevent SwiftData crashes
            let validEntries = cached.filter { $0.task.modelContext != nil }
            if validEntries.count != cached.count {
                // Cache contained deleted tasks, invalidate and rebuild
                visibleLiveTasksWithDepthCache = nil
            } else {
                return cached
            }
        }

        ensureChildCache(for: .live)
        let childMap = childTaskCache[.live] ?? [:]
        let roots = childMap[nil as UUID?] ?? []

        var flattened: [(task: Task, depth: Int)] = []
        for root in roots.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            appendVisible(task: root, depth: 0, accumulator: &flattened, childMap: childMap)
        }
        visibleLiveTasksWithDepthCache = flattened
        return flattened
    }

    private func appendVisible(task: Task, accumulator: inout [Task], childMap: [UUID?: [Task]]) {
        accumulator.append(task)
        guard isTaskExpanded(task.id) else { return }
        let children = childMap[task.id] ?? []
        for child in children {
            appendVisible(task: child, accumulator: &accumulator, childMap: childMap)
        }
    }

    private func appendVisible(
        task: Task,
        depth: Int,
        accumulator: inout [(task: Task, depth: Int)],
        childMap: [UUID?: [Task]]
    ) {
        accumulator.append((task: task, depth: depth))
        guard isTaskExpanded(task.id) else { return }
        let children = childMap[task.id] ?? []
        for child in children {
            appendVisible(task: child, depth: depth + 1, accumulator: &accumulator, childMap: childMap)
        }
    }

    private func taskDepth(_ task: Task) -> Int {
        var depth = 0
        var current = task.parentTask
        while let parent = current {
            depth += 1
            current = parent.parentTask
        }
        return depth
    }
}
