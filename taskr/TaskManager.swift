import SwiftUI
import Combine
import SwiftData
import AppKit

@MainActor
class TaskManager: ObservableObject {
    enum TaskListKind {
        case live
        case template
    }

    let modelContext: ModelContext

    @Published var currentPathInput: String = ""
    @Published var newTemplateName: String = ""
    @Published var autocompleteSuggestions: [String] = []
    @Published var selectedSuggestionIndex: Int? = nil
    @Published var completionMutationVersion: Int = 0
    @Published var pendingInlineEditTaskID: UUID? = nil
    @Published var collapsedTaskIDs: Set<UUID> = []

    lazy var pathCoordinator = PathInputCoordinator(taskManager: self)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCollapsedState()
        pruneCollapsedState()
        normalizeDisplayOrdersIfNeeded()
    }
}
