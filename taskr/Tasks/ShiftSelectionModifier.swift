import SwiftUI

struct ShiftSelectionModifier: ViewModifier {
    let taskID: UUID
    @ObservedObject var taskManager: TaskManager
    
    @State private var didStartShiftDrag: Bool = false
    @State private var shiftDragStartIndex: Int?
    @State private var shiftDragLastIndex: Int?
    
    // We need to access the effective row height for calculation.
    // Since this logic was tightly coupled with the view's height cache,
    // we might need to read from the manager.
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(shiftSelectionGesture)
            .onDisappear {
                resetShiftDragTracking()
            }
            .onHover { hovering in
                if hovering && taskManager.isShiftSelectionInProgress {
                    // We can't easily debounce here without a state object or similar mechanism
                    // But the original code had a debounce check.
                    // For now, we'll rely on the gesture updates or add a simple check if needed.
                    // The original code updated on hover during a drag from *another* row?
                    // Actually, the original code had .onHover updating selection if shift selection was in progress.
                    // This implies that simply hovering while shift-selecting (dragging?) updates it.
                    // Let's replicate the gesture first.
                    taskManager.updateShiftSelection(to: taskID)
                }
            }
    }
    
    private var shiftSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let shiftDown = currentModifierFlags().contains(.shift)
                if !shiftDown {
                    if didStartShiftDrag {
                        didStartShiftDrag = false
                        taskManager.endShiftSelection()
                        resetShiftDragTracking()
                    }
                    return
                }

                if !didStartShiftDrag {
                    didStartShiftDrag = true
                    taskManager.beginShiftSelection(at: taskID)
                }
                handleShiftDragChange(value)
            }
            .onEnded { _ in
                if didStartShiftDrag {
                    didStartShiftDrag = false
                    taskManager.endShiftSelection()
                }
                resetShiftDragTracking()
            }
    }
    
    private func handleShiftDragChange(_ value: DragGesture.Value) {
        // We need visible IDs to calculate the range
        // This is expensive to fetch on every drag update if not cached,
        // but TaskManager should handle the heavy lifting.
        // The original code calculated index based on Y offset and row heights.
        // That logic is quite complex to abstract completely without passing in the cache.
        // However, `taskManager.updateShiftSelection` now takes a targetID.
        // The original code used the Y offset to FIND the target ID.
        // If we just use the hover/drag location to find the target, we might be okay.
        // BUT, the original code did math on the Y offset to find the target index *without* necessarily hovering it?
        // Actually, looking at the original code:
        // It iterates through visibleIDs and sums up cachedHeights to find the targetIndex corresponding to the drag offset.
        
        // To keep this modifier simple, we might want to rely on `onHover` for the "drag over" effect if possible,
        // but `DragGesture` blocks hover updates in some cases.
        // Let's try to implement the offset logic if we can access the cache.
        
        // Accessing `taskManager.visibleLiveTasksCache` (which is now private/internal) might be needed.
        // Or we can expose a helper on TaskManager to "find task ID at vertical offset from anchor".
        // That seems cleaner.
        
        // For now, let's stick to the logic we can implement:
        // The original logic was:
        /*
         let visibleIDs = taskManager.snapshotVisibleTaskIDs()
         ...
         while targetIndex < visibleIDs.count - 1 { ... }
         */
        
        // Since we moved `snapshotVisibleTaskIDs` and row height logic to managers,
        // we should probably ask TaskManager to "update selection based on drag offset".
        // But `DragGesture` gives us a local translation.
        
        // Alternative: The original code was inside the View, so it had access to everything.
        // If we want to extract this, we might need to move the *calculation* to TaskManager too.
        // `taskManager.handleShiftDrag(from: taskID, offset: value.translation.height)`
        
        // Let's assume for this refactor that we can move that logic to TaskManager or SelectionManager.
        // But `SelectionManager` doesn't know about row heights. `RowHeightManager` does.
        // `TaskManager` knows both.
        
        // So, let's add `handleShiftDrag(from: UUID, offset: CGFloat)` to TaskManager.
        taskManager.handleShiftDrag(from: taskID, offset: value.translation.height)
    }
    
    private func currentModifierFlags() -> NSEvent.ModifierFlags {
        if let event = NSApp.currentEvent {
            return event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        }
        return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }
    
    private func resetShiftDragTracking() {
        didStartShiftDrag = false
        shiftDragStartIndex = nil
        shiftDragLastIndex = nil
        taskManager.resetShiftDragTracking()
    }
}
