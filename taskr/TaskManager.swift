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

    @Published var newTemplateName: String = ""
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
    @Published private(set) var animationsMasterEnabled: Bool
    @Published private(set) var listAnimationsEnabled: Bool
    @Published private(set) var collapseAnimationsEnabled: Bool

    lazy var pathCoordinator = PathInputCoordinator(taskManager: self)
    let inputState: TaskInputState

    var themePalette: ThemePalette { selectedTheme.palette }
    var selectedTaskIDSet: Set<UUID> = []
    var selectionAnchorID: UUID?
    var selectionCursorID: UUID?
    private var selectionInteractionCaptured: Bool = false
    var shiftSelectionActive: Bool = false

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.inputState = TaskInputState()
        let storedTheme = defaults.string(forKey: selectedThemePreferenceKey) ?? ""
        self.selectedTheme = AppTheme(rawValue: storedTheme) ?? .system
        self.frostedBackgroundEnabled = defaults.bool(forKey: frostedBackgroundPreferenceKey)
        self.animationsMasterEnabled = defaults.object(forKey: animationsMasterEnabledPreferenceKey) as? Bool ?? true
        self.listAnimationsEnabled = defaults.object(forKey: listAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.collapseAnimationsEnabled = defaults.object(forKey: collapseAnimationsEnabledPreferenceKey) as? Bool ?? true
        loadCollapsedState()
        pruneCollapsedState()
        normalizeDisplayOrdersIfNeeded()
    }

    func task(withID id: UUID) -> Task? {
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
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

    func setAnimationsMasterEnabled(_ enabled: Bool) {
        guard animationsMasterEnabled != enabled else { return }
        animationsMasterEnabled = enabled
        defaults.set(enabled, forKey: animationsMasterEnabledPreferenceKey)
    }

    func setListAnimationsEnabled(_ enabled: Bool) {
        guard listAnimationsEnabled != enabled else { return }
        listAnimationsEnabled = enabled
        defaults.set(enabled, forKey: listAnimationsEnabledPreferenceKey)
    }

    func setCollapseAnimationsEnabled(_ enabled: Bool) {
        guard collapseAnimationsEnabled != enabled else { return }
        collapseAnimationsEnabled = enabled
        defaults.set(enabled, forKey: collapseAnimationsEnabledPreferenceKey)
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

    var currentPathInput: String {
        get { inputState.text }
        set {
            guard inputState.text != newValue else { return }
            inputState.text = newValue
        }
    }

    var autocompleteSuggestions: [String] {
        get { inputState.suggestions }
        set {
            guard inputState.suggestions != newValue else { return }
            inputState.suggestions = newValue
        }
    }

    var selectedSuggestionIndex: Int? {
        get { inputState.selectedSuggestionIndex }
        set {
            guard inputState.selectedSuggestionIndex != newValue else { return }
            inputState.selectedSuggestionIndex = newValue
        }
    }

    @discardableResult
    func performListMutation<Result>(_ body: () -> Result) -> Result {
        performAnimation(isEnabled: listAnimationsEnabled, body)
    }

    @discardableResult
    func performCollapseTransition<Result>(_ body: () -> Result) -> Result {
        performAnimation(isEnabled: collapseAnimationsEnabled, body)
    }

    @discardableResult
    private func performAnimation<Result>(isEnabled: Bool, _ body: () -> Result) -> Result {
        guard animationsMasterEnabled && isEnabled else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            return withTransaction(transaction) { body() }
        }
        return withAnimation(.default) { body() }
    }

    func childTasks(for parent: Task, kind: TaskListKind) -> [Task] {
        let children = parent.subtasks ?? []
        let filtered: [Task]
        switch kind {
        case .live:
            filtered = children.filter { !$0.isTemplateComponent }
        case .template:
            filtered = children.filter { $0.isTemplateComponent }
        }
        return filtered.sorted { $0.displayOrder < $1.displayOrder }
    }
}
