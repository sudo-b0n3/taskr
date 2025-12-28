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

    enum FrostLevel: Int, CaseIterable, Identifiable {
        case low = 0
        case medium = 1
        case high = 2
        
        var id: Int { rawValue }
        
        var displayName: String {
            switch self {
            case .low: return "Most Transparent"
            case .medium: return "Moderate"
            case .high: return "Least Transparent"
            }
        }
        
        var opacity: Double {
            switch self {
            case .low: return 0.5
            case .medium: return 0.65
            case .high: return 0.8
            }
        }
    }

    let modelContext: ModelContext
    private let defaults: UserDefaults

    // Sub-managers
    let themeManager: ThemeManager
    let selectionManager: SelectionManager
    let animationManager: AnimationManager
    let rowHeightManager: RowHeightManager

    @Published var newTemplateName: String = ""
    @Published var completionMutationVersion: Int = 0
    @Published var pendingInlineEditTaskID: UUID? = nil
    @Published var collapsedTaskIDs: Set<UUID> = []
    @Published var isDemoSwapInProgress: Bool = false
    
    @Published private(set) var isTaskInputFocused: Bool = false
    @Published private(set) var frostedBackgroundEnabled: Bool
    @Published private(set) var frostedBackgroundLevel: FrostLevel
    @Published private(set) var fontScale: Double
    @Published private(set) var isApplicationActive: Bool = true

    lazy var pathCoordinator = PathInputCoordinator(taskManager: self)
    let inputState: TaskInputState

    // Proxy properties for backward compatibility and ease of access
    var selectedTheme: AppTheme { themeManager.selectedTheme }
    var themePalette: ThemePalette { themeManager.themePalette }
    
    var selectedTaskIDs: [UUID] {
        get { selectionManager.selectedTaskIDs }
        set { selectionManager.selectedTaskIDs = newValue }
    }
    var selectedTaskIDSet: Set<UUID> { selectionManager.selectedTaskIDSet }
    var selectionAnchorID: UUID? {
        get { selectionManager.selectionAnchorID }
        set { selectionManager.selectionAnchorID = newValue }
    }
    var selectionCursorID: UUID? {
        get { selectionManager.selectionCursorID }
        set { selectionManager.selectionCursorID = newValue }
    }
    var shiftSelectionActive: Bool { selectionManager.shiftSelectionActive }
    var isShiftSelectionInProgress: Bool { selectionManager.isShiftSelectionInProgress }
    
    var animationsMasterEnabled: Bool { animationManager.animationsMasterEnabled }
    var listAnimationsEnabled: Bool { animationManager.listAnimationsEnabled }
    var collapseAnimationsEnabled: Bool { animationManager.collapseAnimationsEnabled }

    var visibleLiveTasksCache: [Task]? = nil
    var visibleLiveTasksWithDepthCache: [(task: Task, depth: Int)]? = nil
    var childTaskCache: [TaskListKind: [UUID?: [Task]]] = [:]
    var taskIndexCache: [TaskListKind: [UUID: Task]] = [:]
    var completedAncestorCache: [TaskListKind: [UUID: Bool]] = [:]
    private var orphanedTaskLog: Set<UUID> = []

    private var cancellables = Set<AnyCancellable>()
    static let fontScaleRange: ClosedRange<Double> = 0.9...1.3
    static let fontScaleStep: Double = 0.05

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.inputState = TaskInputState()
        
        // Initialize sub-managers
        self.themeManager = ThemeManager(defaults: defaults)
        self.selectionManager = SelectionManager()
        self.animationManager = AnimationManager(defaults: defaults)
        self.rowHeightManager = RowHeightManager()
        
        self.frostedBackgroundEnabled = defaults.bool(forKey: frostedBackgroundPreferenceKey)
        self.frostedBackgroundLevel = FrostLevel(rawValue: defaults.integer(forKey: frostedBackgroundLevelPreferenceKey)) ?? .medium
        let storedScale = defaults.object(forKey: fontScalePreferenceKey) as? Double ?? 1.0
        self.fontScale = TaskManager.clampFontScale(storedScale)
        
        // Forward sub-manager updates to TaskManager's objectWillChange
        themeManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        animationManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        rowHeightManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        
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

    // MARK: - Theme Delegation
    func setTheme(_ theme: AppTheme) {
        themeManager.setTheme(theme)
    }

    // MARK: - Settings Delegation
    func setFrostedBackgroundEnabled(_ enabled: Bool) {
        guard frostedBackgroundEnabled != enabled else { return }
        frostedBackgroundEnabled = enabled
        defaults.set(enabled, forKey: frostedBackgroundPreferenceKey)
    }

    func setFrostedBackgroundLevel(_ level: FrostLevel) {
        guard frostedBackgroundLevel != level else { return }
        frostedBackgroundLevel = level
        defaults.set(level.rawValue, forKey: frostedBackgroundLevelPreferenceKey)
    }

    func setAnimationsMasterEnabled(_ enabled: Bool) {
        animationManager.setAnimationsMasterEnabled(enabled)
    }

    func setListAnimationsEnabled(_ enabled: Bool) {
        animationManager.setListAnimationsEnabled(enabled)
    }

    func setCollapseAnimationsEnabled(_ enabled: Bool) {
        animationManager.setCollapseAnimationsEnabled(enabled)
    }
    
    func setCompletionAnimationsEnabled(_ enabled: Bool) {
        animationManager.setCompletionAnimationsEnabled(enabled)
    }
    
    func setChevronAnimationEnabled(_ enabled: Bool) {
        animationManager.setChevronAnimationEnabled(enabled)
    }
    
    func setItemTransitionsEnabled(_ enabled: Bool) {
        animationManager.setItemTransitionsEnabled(enabled)
    }
    
    func setUiMicroAnimationsEnabled(_ enabled: Bool) {
        animationManager.setUiMicroAnimationsEnabled(enabled)
    }
    
    func setRowHeightAnimationEnabled(_ enabled: Bool) {
        animationManager.setRowHeightAnimationEnabled(enabled)
    }
    
    func setFontScale(_ scale: Double) {
        let clamped = Self.clampFontScale(scale)
        guard abs(fontScale - clamped) > 0.0001 else { return }
        fontScale = clamped
        defaults.set(clamped, forKey: fontScalePreferenceKey)
    }

    // MARK: - Input Focus & App State
    func setTaskInputFocused(_ isFocused: Bool) {
        guard isTaskInputFocused != isFocused else { return }
        isTaskInputFocused = isFocused
        if isFocused {
            selectionManager.clearSelection()
            selectionManager.endShiftSelection()
        }
    }

    func setApplicationActive(_ active: Bool) {
        guard isApplicationActive != active else { return }
        isApplicationActive = active
    }

    // MARK: - Selection Delegation
    func registerUserInteractionTap() {
        selectionManager.registerUserInteractionTap()
    }

    func consumeInteractionCapture() -> Bool {
        selectionManager.consumeInteractionCapture()
    }

    func resetTapInteractionCapture() {
        selectionManager.resetTapInteractionCapture()
    }
    
    func isTaskSelected(_ id: UUID) -> Bool {
        selectionManager.isTaskSelected(id)
    }
    
    func clearSelection() {
        selectionManager.clearSelection()
    }
    
    func replaceSelection(with id: UUID) {
        selectionManager.replaceSelection(with: id)
    }
    
    func toggleSelection(for id: UUID) {
        selectionManager.toggleSelection(for: id, visibleTaskIDs: snapshotVisibleTaskIDs())
    }
    
    func extendSelection(to id: UUID) {
        selectionManager.extendSelection(to: id, visibleTaskIDs: snapshotVisibleTaskIDs())
    }
    
    func selectTasks(orderedIDs: [UUID], anchor: UUID?, cursor: UUID?) {
        selectionManager.selectTasks(orderedIDs: orderedIDs, anchor: anchor, cursor: cursor)
    }
    
    func beginShiftSelection(at id: UUID) {
        selectionManager.beginShiftSelection(at: id)
    }
    
    func updateShiftSelection(to targetID: UUID) {
        let visibleIDs = snapshotVisibleTaskIDs()
        selectionManager.updateShiftSelection(to: targetID, visibleTaskIDs: visibleIDs)
    }

    func endShiftSelection() {
        selectionManager.endShiftSelection()
    }
    
    func requestScrollTo(_ taskID: UUID) {
        selectionManager.requestScrollTo(taskID)
    }
    
    private static func clampFontScale(_ scale: Double) -> Double {
        let stepped = (scale / fontScaleStep).rounded() * fontScaleStep
        return min(max(stepped, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }

    // MARK: - Row Height Delegation
    func setRowHeight(_ height: CGFloat, for taskID: UUID) {
        rowHeightManager.setRowHeight(height, for: taskID)
    }

    func clearRowHeight(for taskID: UUID) {
        rowHeightManager.clearRowHeight(for: taskID)
    }

    func rowHeight(for taskID: UUID) -> CGFloat? {
        rowHeightManager.rowHeight(for: taskID)
    }

    // MARK: - Cache Management
    func invalidateVisibleTasksCache() {
        visibleLiveTasksCache = nil
        visibleLiveTasksWithDepthCache = nil
        invalidateCompletionCache(for: .live)
    }

    func invalidateChildTaskCache(for kind: TaskListKind? = nil) {
        if let specificKind = kind {
            childTaskCache.removeValue(forKey: specificKind)
            taskIndexCache.removeValue(forKey: specificKind)
        } else {
            childTaskCache.removeAll()
            taskIndexCache.removeAll()
        }
        invalidateCompletionCache(for: kind)
    }

    func invalidateCompletionCache(for kind: TaskListKind? = nil) {
        if let specificKind = kind {
            completedAncestorCache.removeValue(forKey: specificKind)
        } else {
            completedAncestorCache.removeAll()
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
            // Ensure every task ID has an entry so leaf lookups hit the cache and avoid re-fetching
            for task in tasks {
                if map[task.id] == nil {
                    map[task.id] = []
                }
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
        return animationManager.performListMutation(body)
    }

    @discardableResult
    func performCollapseTransition<Result>(_ body: () -> Result) -> Result {
        invalidateVisibleTasksCache()
        return animationManager.performCollapseTransition(body)
    }

    func childTasks(forParentID parentID: UUID, kind: TaskListKind) -> [Task] {
        ensureChildCache(for: kind)
        if let cached = childTaskCache[kind]?[parentID] {
            // Filter out deleted tasks to prevent SwiftData crashes
            let validTasks = cached.filter { $0.modelContext != nil }
            if validTasks.count != cached.count {
                // Cache contained deleted tasks, invalidate this entry
                childTaskCache[kind]?[parentID] = nil
                invalidateVisibleTasksCache()
            } else {
                return cached
            }
        }

        // Fallback: log and attempt fetch once if cache is missing an entry
        guard let parentTask = task(withID: parentID) else {
            noteOrphanedTask(id: parentID, context: "childTasks(\(kind))")
            return []
        }

        do {
            let siblings = try fetchSiblings(for: parentTask, kind: kind)
            // Memoize empty child lists to prevent repeated fetches for leaves
            if var map = childTaskCache[kind] {
                map[parentID] = siblings
                childTaskCache[kind] = map
            }
            return siblings
        } catch {
            #if DEBUG
            print("TaskManager warning: fetchSiblings fallback failed for parent \(parentID) (\(kind)): \(error)")
            #endif
            return []
        }
    }

    func hasCachedChildren(forParentID parentID: UUID, kind: TaskListKind) -> Bool {
        ensureChildCache(for: kind)
        guard let cached = childTaskCache[kind]?[parentID] else {
            return false
        }
        return !cached.isEmpty
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

        if let cached = completedAncestorCache[kind]?[taskID] {
            return cached
        }

        var visited = Set<UUID>()
        var current = task.parentTask
        var hasCompletedAncestor = false

        while let parent = current {
            if !visited.insert(parent.id).inserted {
                break
            }
            if parent.isCompleted {
                hasCompletedAncestor = true
                break
            }
            current = parent.parentTask
        }

        completedAncestorCache[kind, default: [:]][taskID] = hasCompletedAncestor
        return hasCompletedAncestor
    }

    func handleShiftDrag(from startTaskID: UUID, offset: CGFloat) {
        // We need to calculate the target task ID based on the offset and row heights.
        // This requires visible tasks and their heights.
        
        // We need to calculate the target task ID based on the offset and row heights.
        // This requires visible tasks and their heights.
        
        let visibleIDs = snapshotVisibleTaskIDs()
        
        guard let startIndex = visibleIDs.firstIndex(of: startTaskID) else { return }
        
        var targetIndex = startIndex
        
        if offset >= 0 {
            var remaining = offset
            while targetIndex < visibleIDs.count - 1 {
                let height = rowHeight(for: visibleIDs[targetIndex]) ?? 28 // Default height
                if remaining < height {
                    break
                }
                remaining -= height
                targetIndex += 1
            }
        } else {
            var remaining = offset
            while targetIndex > 0 {
                let previousIndex = targetIndex - 1
                let height = rowHeight(for: visibleIDs[previousIndex]) ?? 28
                remaining += height
                targetIndex = previousIndex
                if remaining >= 0 {
                    break
                }
            }
        }
        
        let targetID = visibleIDs[targetIndex]
        updateShiftSelection(to: targetID)
    }
    
    func resetShiftDragTracking() {
        // Any cleanup if needed in managers
    }

    // Helper to get flattened visible IDs (re-implementing or exposing if it was private)
    // Helper to get flattened visible IDs
    func snapshotVisibleTaskIDs() -> [UUID] {
        snapshotVisibleTasks().map(\.id)
    }
    
    // Re-adding fetchSiblings since it was used in the original code but might be private/missing in my replacement
    // fetchSiblings is defined in TaskManager+OrderingHelpers.swift


    func noteOrphanedTask(id: UUID, context: String) {
        guard !orphanedTaskLog.contains(id) else { return }
        orphanedTaskLog.insert(id)
#if DEBUG
        print("TaskManager notice: encountered orphaned task \(id) during \(context)")
#endif
    }
}
