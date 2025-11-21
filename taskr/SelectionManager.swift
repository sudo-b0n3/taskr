import SwiftUI
import Combine

@MainActor
class SelectionManager: ObservableObject {
    @Published var selectedTaskIDs: [UUID] = [] {
        didSet { selectedTaskIDSet = Set(selectedTaskIDs) }
    }
    @Published private(set) var selectedTaskIDSet: Set<UUID> = []
    
    var selectionAnchorID: UUID?
    var selectionCursorID: UUID?
    var shiftSelectionActive: Bool = false
    private var selectionInteractionCaptured: Bool = false
    
    // MARK: - Selection State Queries
    
    func isTaskSelected(_ id: UUID) -> Bool {
        selectedTaskIDSet.contains(id)
    }
    
    var isShiftSelectionInProgress: Bool {
        shiftSelectionActive
    }
    
    // MARK: - Selection Interaction Capture
    
    func registerUserInteractionTap() {
        selectionInteractionCaptured = true
    }
    
    func consumeInteractionCapture() -> Bool {
        let captured = selectionInteractionCaptured
        selectionInteractionCaptured = false
        return captured
    }
    
    func resetTapInteractionCapture() {
        selectionInteractionCaptured = false
    }
    
    // MARK: - Selection Mutators
    
    func clearSelection() {
        selectedTaskIDs = []
        selectionAnchorID = nil
        selectionCursorID = nil
    }
    
    func replaceSelection(with id: UUID) {
        selectedTaskIDs = [id]
        selectionAnchorID = id
        selectionCursorID = id
    }
    
    func toggleSelection(for id: UUID, visibleTaskIDs: [UUID]) {
        var orderedCandidates = selectedTaskIDs
        let wasSelected = selectedTaskIDSet.contains(id)
        
        if let existingIndex = orderedCandidates.firstIndex(of: id) {
            orderedCandidates.remove(at: existingIndex)
        } else {
            orderedCandidates.append(id)
        }
        
        let ordered = orderedSelection(from: orderedCandidates, visibleIDs: visibleTaskIDs)
        
        if !wasSelected {
            // New click becomes the anchor/cursor
            selectTasks(orderedIDs: ordered, anchor: id, cursor: id)
            return
        }
        
        // For removals, preserve prior anchor/cursor if still valid; otherwise fall back
        let preservedAnchor = selectionAnchorID.flatMap { ordered.contains($0) ? $0 : nil }
        let preservedCursor = selectionCursorID.flatMap { ordered.contains($0) ? $0 : nil }
        let fallback = ordered.last
        
        selectTasks(
            orderedIDs: ordered,
            anchor: preservedAnchor ?? fallback,
            cursor: preservedCursor ?? fallback
        )
    }
    
    func extendSelection(to id: UUID, visibleTaskIDs: [UUID]) {
        guard let targetIndex = visibleTaskIDs.firstIndex(of: id) else {
            replaceSelection(with: id)
            return
        }
        
        let anchorID = selectionAnchorID.flatMap { visibleTaskIDs.contains($0) ? $0 : nil }
            ?? selectionCursorID.flatMap { visibleTaskIDs.contains($0) ? $0 : nil }
            ?? selectedTaskIDs.first
            ?? id
            
        guard let anchorIndex = visibleTaskIDs.firstIndex(of: anchorID) else {
            replaceSelection(with: id)
            return
        }
        
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let rangeIDs = Array(visibleTaskIDs[lower...upper])
        
        selectTasks(orderedIDs: rangeIDs, anchor: anchorID, cursor: id)
    }
    
    func selectTasks(orderedIDs: [UUID], anchor: UUID?, cursor: UUID?) {
        selectedTaskIDs = orderedIDs
        selectionAnchorID = anchor
        selectionCursorID = cursor
    }
    
    // MARK: - Shift Selection Logic
    
    func beginShiftSelection(at id: UUID) {
        shiftSelectionActive = true
        if !selectedTaskIDSet.contains(id) {
            replaceSelection(with: id)
        } else {
            if selectionAnchorID == nil { selectionAnchorID = id }
            selectionCursorID = id
        }
    }
    
    func updateShiftSelection(to targetID: UUID, visibleTaskIDs: [UUID]) {
        guard shiftSelectionActive else { return }
        // Reuse extendSelection logic which handles range from anchor
        extendSelection(to: targetID, visibleTaskIDs: visibleTaskIDs)
    }
    
    func endShiftSelection() {
        shiftSelectionActive = false
    }
    
    // MARK: - Helpers
    
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
}
