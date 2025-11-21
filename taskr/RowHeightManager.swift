import SwiftUI
import Combine

@MainActor
class RowHeightManager: ObservableObject {
    private var rowHeightCache: [UUID: CGFloat] = [:]
    
    func setRowHeight(_ height: CGFloat, for taskID: UUID) {
        rowHeightCache[taskID] = height
    }
    
    func clearRowHeight(for taskID: UUID) {
        rowHeightCache.removeValue(forKey: taskID)
    }
    
    func rowHeight(for taskID: UUID) -> CGFloat? {
        rowHeightCache[taskID]
    }
}
