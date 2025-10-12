import AppKit
import Foundation
import SwiftData

extension TaskManager {
    enum SelectionDirection {
        case up
        case down
    }

    func isTaskSelected(_ taskID: UUID) -> Bool {
        selectedTaskIDSet.contains(taskID)
    }

    func clearSelection() {
        applySelection(orderedIDs: [], anchor: nil, cursor: nil)
        resetTapInteractionCapture()
        shiftSelectionActive = false
    }

    func replaceSelection(with taskID: UUID) {
        applySelection(orderedIDs: [taskID], anchor: taskID, cursor: taskID)
    }

    func toggleSelection(for taskID: UUID) {
        let visibleIDs = snapshotVisibleTaskIDs()
        var orderedCandidates = selectedTaskIDs

        if let existingIndex = orderedCandidates.firstIndex(of: taskID) {
            orderedCandidates.remove(at: existingIndex)
            applySelection(
                candidateIDs: orderedCandidates,
                anchor: selectionAnchorID == taskID ? nil : selectionAnchorID,
                cursor: selectionCursorID == taskID ? nil : selectionCursorID,
                visibleIDs: visibleIDs
            )
        } else {
            orderedCandidates.append(taskID)
            let anchorCandidate = selectionAnchorID
                ?? selectedTaskIDs.first
                ?? taskID
            applySelection(
                candidateIDs: orderedCandidates,
                anchor: anchorCandidate,
                cursor: taskID,
                visibleIDs: visibleIDs
            )
        }
    }

    func extendSelection(to taskID: UUID) {
        let visibleIDs = snapshotVisibleTaskIDs()
        guard let targetIndex = visibleIDs.firstIndex(of: taskID) else {
            replaceSelection(with: taskID)
            return
        }

        let anchorID = selectionAnchorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? selectionCursorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? selectedTaskIDs.first
            ?? taskID

        guard let anchorIndex = visibleIDs.firstIndex(of: anchorID) else {
            replaceSelection(with: taskID)
            return
        }

        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let rangeIDs = Array(visibleIDs[lower...upper])
        applySelection(orderedIDs: rangeIDs, anchor: anchorID, cursor: taskID)
    }

    func selectAllVisibleTasks() {
        let visibleIDs = snapshotVisibleTaskIDs()
        guard !visibleIDs.isEmpty else {
            clearSelection()
            return
        }
        applySelection(
            orderedIDs: visibleIDs,
            anchor: visibleIDs.first,
            cursor: visibleIDs.last
        )
    }

    func stepSelection(_ direction: SelectionDirection, extend: Bool) {
        let visibleTasks = snapshotVisibleTasks()
        guard !visibleTasks.isEmpty else {
            clearSelection()
            return
        }
        let visibleIDs = visibleTasks.map(\.id)
        syncSelectionWithVisibleIDs(visibleIDs)

        let delta = direction == .down ? 1 : -1
        let anchorID = selectionAnchorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let currentCursorID = selectionCursorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? selectedTaskIDs.last
            ?? selectedTaskIDs.first

        if selectedTaskIDs.isEmpty || currentCursorID == nil {
            let index = direction == .down ? 0 : visibleIDs.count - 1
            let id = visibleIDs[index]
            applySelection(orderedIDs: [id], anchor: id, cursor: id)
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
                applySelection(orderedIDs: rangeIDs, anchor: visibleIDs[anchorIndex], cursor: id)
            } else {
                applySelection(orderedIDs: [id], anchor: id, cursor: id)
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
            applySelection(
                orderedIDs: rangeIDs,
                anchor: visibleIDs[anchorIndex],
                cursor: nextID
            )
        } else {
            applySelection(orderedIDs: [nextID], anchor: nextID, cursor: nextID)
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
        syncSelectionWithVisibleIDs(visibleIDs)
    }

    func selectTasks(
        orderedIDs: [UUID],
        anchor: UUID? = nil,
        cursor: UUID? = nil
    ) {
        applySelection(orderedIDs: orderedIDs, anchor: anchor, cursor: cursor)
    }

    func beginShiftSelection(at taskID: UUID) {
        if selectedTaskIDs.isEmpty {
            replaceSelection(with: taskID)
        } else if !selectedTaskIDSet.contains(taskID) && selectedTaskIDs.count == 1 {
            replaceSelection(with: taskID)
        } else if selectionAnchorID == nil {
            selectionAnchorID = selectedTaskIDs.first ?? taskID
        }

        shiftSelectionActive = true
        extendSelection(to: taskID)
    }

    func updateShiftSelection(to taskID: UUID) {
        guard shiftSelectionActive else { return }
        extendSelection(to: taskID)
    }

    func endShiftSelection() {
        shiftSelectionActive = false
    }

    var isShiftSelectionInProgress: Bool {
        shiftSelectionActive
    }

    // MARK: - Helper routines

    private func snapshotVisibleTasks() -> [Task] {
        let roots: [Task]
        do {
            roots = try fetchSiblings(for: nil, kind: .live, order: .forward)
        } catch {
            return []
        }

        var flattened: [Task] = []
        for root in roots.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            appendVisible(task: root, accumulator: &flattened)
        }
        return flattened
    }

    func snapshotVisibleTaskIDs() -> [UUID] {
        snapshotVisibleTasks().map(\.id)
    }

    private func appendVisible(task: Task, accumulator: inout [Task]) {
        accumulator.append(task)
        guard isTaskExpanded(task.id) else { return }
        let children = (task.subtasks ?? [])
            .filter { !$0.isTemplateComponent }
            .sorted { $0.displayOrder < $1.displayOrder }

        for child in children {
            appendVisible(task: child, accumulator: &accumulator)
        }
    }

    private func applySelection(
        candidateIDs: [UUID],
        anchor: UUID?,
        cursor: UUID?,
        visibleIDs: [UUID]
    ) {
        let ordered = orderedSelection(from: candidateIDs, visibleIDs: visibleIDs)
        applySelection(orderedIDs: ordered, anchor: anchor, cursor: cursor)
    }

    private func applySelection(
        orderedIDs: [UUID],
        anchor: UUID?,
        cursor: UUID?
    ) {
        selectedTaskIDs = orderedIDs
        if orderedIDs.isEmpty {
            selectionAnchorID = nil
            selectionCursorID = nil
            return
        }

        let anchorID = anchor.flatMap { orderedIDs.contains($0) ? $0 : nil } ?? orderedIDs.first
        let cursorID = cursor.flatMap { orderedIDs.contains($0) ? $0 : nil } ?? orderedIDs.last
        selectionAnchorID = anchorID
        selectionCursorID = cursorID
    }

    private func orderedSelection(from candidates: [UUID], visibleIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var uniqueCandidates: [UUID] = []
        uniqueCandidates.reserveCapacity(candidates.count)

        for id in candidates where seen.insert(id).inserted {
            uniqueCandidates.append(id)
        }

        var ordered: [UUID] = []
        ordered.reserveCapacity(uniqueCandidates.count)
        var remaining = Set(uniqueCandidates)

        for id in visibleIDs where remaining.contains(id) {
            ordered.append(id)
            remaining.remove(id)
        }

        if !remaining.isEmpty {
            for id in uniqueCandidates where remaining.contains(id) {
                ordered.append(id)
                remaining.remove(id)
            }
        }

        return ordered
    }

    private func syncSelectionWithVisibleIDs(_ visibleIDs: [UUID]) {
        guard !selectedTaskIDs.isEmpty else { return }
        let visibleSet = Set(visibleIDs)
        if selectedTaskIDs.allSatisfy({ visibleSet.contains($0) }) &&
            selectionAnchorID.map({ visibleSet.contains($0) }) != false &&
            selectionCursorID.map({ visibleSet.contains($0) }) != false {
            return
        }

        let filtered = selectedTaskIDs.filter { visibleSet.contains($0) }
        let newAnchor = selectionAnchorID.flatMap { visibleSet.contains($0) ? $0 : nil }
        let newCursor = selectionCursorID.flatMap { visibleSet.contains($0) ? $0 : nil }
        applySelection(orderedIDs: filtered, anchor: newAnchor, cursor: newCursor)
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
