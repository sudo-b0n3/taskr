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
    private var rowHeightCache: [UUID: CGFloat] = [:]
    var visibleLiveTasksCache: [Task]? = nil
    var childTaskCache: [TaskListKind: [UUID?: [Task]]] = [:]
    var taskIndexCache: [TaskListKind: [UUID: Task]] = [:]
    private var orphanedTaskLog: Set<UUID> = []

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

    func setRowHeight(_ height: CGFloat, for taskID: UUID) {
        rowHeightCache[taskID] = height
    }

    func clearRowHeight(for taskID: UUID) {
        rowHeightCache.removeValue(forKey: taskID)
    }

    func rowHeight(for taskID: UUID) -> CGFloat? {
        rowHeightCache[taskID]
    }

    func invalidateVisibleTasksCache() {
        visibleLiveTasksCache = nil
    }

    func invalidateChildTaskCache(for kind: TaskListKind? = nil) {
        if let specificKind = kind {
            childTaskCache.removeValue(forKey: specificKind)
            taskIndexCache.removeValue(forKey: specificKind)
        } else {
            childTaskCache.removeAll()
            taskIndexCache.removeAll()
        }
    }

    func ensureChildCache(for kind: TaskListKind) {
        if childTaskCache[kind] != nil { return }
        rebuildChildCache(for: kind)
    }

    func rebuildChildCache(for kind: TaskListKind) {
        let kindPredicate: Predicate<Task> = {
            switch kind {
            case .live:
                return #Predicate { !$0.isTemplateComponent }
            case .template:
                return #Predicate { $0.isTemplateComponent }
            }
        }()
        let descriptor = FetchDescriptor<Task>(
            predicate: kindPredicate,
            sortBy: [SortDescriptor(\.displayOrder, order: .forward)]
        )

        do {
            let tasks = try modelContext.fetch(descriptor)
            var map: [UUID?: [Task]] = [:]
            var index: [UUID: Task] = [:]
            for task in tasks {
                index[task.id] = task
                map[task.parentTask?.id, default: []].append(task)
            }
            for (key, children) in map {
                map[key] = children.sorted { $0.displayOrder < $1.displayOrder }
            }
            childTaskCache[kind] = map
            taskIndexCache[kind] = index
        } catch {
        #if DEBUG
            print("TaskManager warning: failed to rebuild child cache for \(kind): \(error)")
        #endif
            childTaskCache[kind] = [:]
            taskIndexCache[kind] = [:]
        }
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
        invalidateVisibleTasksCache()
        invalidateChildTaskCache(for: nil)
        return performAnimation(isEnabled: listAnimationsEnabled, body)
    }

    @discardableResult
    func performCollapseTransition<Result>(_ body: () -> Result) -> Result {
        invalidateVisibleTasksCache()
        return performAnimation(isEnabled: collapseAnimationsEnabled, body)
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

    func childTasks(forParentID parentID: UUID, kind: TaskListKind) -> [Task] {
        ensureChildCache(for: kind)
        if let cached = childTaskCache[kind]?[parentID] {
            return cached
        }

        // Fallback: log and attempt fetch once if cache is missing an entry
        guard let parentTask = task(withID: parentID) else {
            noteOrphanedTask(id: parentID, context: "childTasks(\(kind))")
            return []
        }

        do {
            let siblings = try fetchSiblings(for: parentTask, kind: kind)
            return siblings
        } catch {
            #if DEBUG
            print("TaskManager warning: fetchSiblings fallback failed for parent \(parentID) (\(kind)): \(error)")
            #endif
            return []
        }
    }

    func hasCompletedAncestor(for taskID: UUID, kind: TaskListKind) -> Bool {
        guard kind == .live else { return false }

        guard let startingTask = task(withID: taskID) else {
            noteOrphanedTask(id: taskID, context: "hasCompletedAncestor:start")
            return false
        }

        var visited = Set<UUID>()
        var parentID = startingTask.parentTask?.id

        while let currentParentID = parentID {
            if !visited.insert(currentParentID).inserted {
                break
            }

            guard let parentTask = task(withID: currentParentID) else {
                noteOrphanedTask(id: currentParentID, context: "hasCompletedAncestor:lookup")
                break
            }

            if parentTask.isCompleted {
                return true
            }

            parentID = parentTask.parentTask?.id
        }

        return false
    }

    func hasCompletedAncestorCached(for taskID: UUID, kind: TaskListKind) -> Bool {
        guard kind == .live else { return false }
        ensureChildCache(for: kind)
        guard let index = taskIndexCache[kind], let task = index[taskID] else {
            return hasCompletedAncestor(for: taskID, kind: kind)
        }

        var visited = Set<UUID>()
        var current = task.parentTask

        while let parent = current {
            if !visited.insert(parent.id).inserted {
                break
            }
            if parent.isCompleted {
                return true
            }
            current = parent.parentTask
        }

        return false
    }

    func noteOrphanedTask(id: UUID, context: String) {
        guard !orphanedTaskLog.contains(id) else { return }
        orphanedTaskLog.insert(id)
#if DEBUG
        print("TaskManager notice: encountered orphaned task \(id) during \(context)")
#endif
    }
}
