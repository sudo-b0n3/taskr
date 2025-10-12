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
    private let defaults: UserDefaults

    @Published var currentPathInput: String = ""
    @Published var newTemplateName: String = ""
    @Published var autocompleteSuggestions: [String] = []
    @Published var selectedSuggestionIndex: Int? = nil
    @Published var completionMutationVersion: Int = 0
    @Published var pendingInlineEditTaskID: UUID? = nil
    @Published var collapsedTaskIDs: Set<UUID> = []
    @Published var selectedTaskIDs: [UUID] = [] {
        didSet { selectedTaskIDSet = Set(selectedTaskIDs) }
    }
    @Published private(set) var isTaskInputFocused: Bool = false
    @Published private(set) var selectedTheme: AppTheme
    @Published private(set) var frostedBackgroundEnabled: Bool
    @Published private(set) var isApplicationActive: Bool = true
    @Published private(set) var isTaskWindowKey: Bool = true

    lazy var pathCoordinator = PathInputCoordinator(taskManager: self)

    var themePalette: ThemePalette { selectedTheme.palette }
    var selectedTaskIDSet: Set<UUID> = []
    var selectionAnchorID: UUID?
    var selectionCursorID: UUID?
    private var selectionInteractionCaptured: Bool = false

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.defaults = defaults
        let storedTheme = defaults.string(forKey: selectedThemePreferenceKey) ?? ""
        self.selectedTheme = AppTheme(rawValue: storedTheme) ?? .system
        self.frostedBackgroundEnabled = defaults.bool(forKey: frostedBackgroundPreferenceKey)
        loadCollapsedState()
        pruneCollapsedState()
        normalizeDisplayOrdersIfNeeded()
    }

    func setTheme(_ theme: AppTheme) {
        guard theme != selectedTheme else { return }
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: selectedThemePreferenceKey)
    }

    func setFrostedBackgroundEnabled(_ enabled: Bool) {
        guard frostedBackgroundEnabled != enabled else { return }
        frostedBackgroundEnabled = enabled
        defaults.set(enabled, forKey: frostedBackgroundPreferenceKey)
    }

    func setTaskInputFocused(_ isFocused: Bool) {
        guard isTaskInputFocused != isFocused else { return }
        isTaskInputFocused = isFocused
    }

    func setApplicationActive(_ active: Bool) {
        guard isApplicationActive != active else { return }
        isApplicationActive = active
    }

    func setTaskWindowKey(_ isKey: Bool) {
        guard isTaskWindowKey != isKey else { return }
        isTaskWindowKey = isKey
    }

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
}
