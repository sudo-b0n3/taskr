import SwiftUI
import SwiftData
import AppKit

struct TaskRowContentView: View {
    @Bindable var task: Task
    var mode: TaskRowView.RowMode
    @ObservedObject var selectionState: TaskSelectionState
    var releaseInputFocus: (() -> Void)?
    
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.isWindowKey) var isWindowKey
    @Environment(\.isLiveScrolling) var isLiveScrolling
    @Environment(\.taskrFontScale) var fontScale
    
    @AppStorage(completionAnimationsEnabledPreferenceKey) private var completionAnimationsEnabled: Bool = true
    @AppStorage(checkboxTopAlignedPreferenceKey) private var checkboxTopAligned: Bool = true
    @AppStorage(contextMenuTagTargetPreferenceKey) private var contextMenuTagTargetRaw: String = ContextMenuTagTarget.defaultTarget.rawValue
    
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isHoveringRow: Bool = false
    @State private var originalNameBeforeEdit: String?
    @State private var chevronExpanded: Bool = false
    
    private let taskID: UUID
    private let checkboxSize: CGFloat = 18
    private let checkboxTapExpansion: CGFloat = 6
    
    init(
        task: Task,
        mode: TaskRowView.RowMode,
        selectionState: TaskSelectionState,
        releaseInputFocus: (() -> Void)?
    ) {
        self._task = Bindable(task)
        self.mode = mode
        self.selectionState = selectionState
        self.releaseInputFocus = releaseInputFocus
        self.taskID = task.id
    }
    
    private var isExpanded: Bool {
        taskManager.isTaskExpanded(taskID)
    }

    private var chevronAnimEnabled: Bool {
        taskManager.animationsMasterEnabled && taskManager.animationManager.chevronAnimationEnabled
    }
    
    private var rowHeightAnimEnabled: Bool {
        taskManager.animationsMasterEnabled && taskManager.animationManager.rowHeightAnimationEnabled
    }
    
    /// The base height for a single-line row, based on body font line height plus padding.
    /// All row heights snap to multiples of this value.
    private var baseRowHeight: CGFloat {
        // Line height for body text at current scale
        let lineHeight = TaskrTypography.lineHeight(for: .body, scale: fontScale)
        // Add vertical padding (2pts internal on each side) + some buffer for checkbox/elements
        let padding: CGFloat = 8
        let calculatedHeight = lineHeight + padding
        // Ensure we never go below the checkbox size to prevent clipping
        return max(calculatedHeight, checkboxSize + padding)
    }
    
    private var hasExpandableChildren: Bool {
        // We need to know if there are children to show the chevron.
        // Accessing childTasks here is okay as this view is for the specific row.
        // However, we want to avoid re-calculating the *list* of children if possible,
        // but checking for emptiness is cheap if cached.
        let listKind: TaskManager.TaskListKind = mode == .live ? .live : .template
        return taskManager.hasCachedChildren(forParentID: taskID, kind: listKind)
    }
    
    private var palette: ThemePalette { taskManager.themePalette }
    private var isSelected: Bool {
        selectionState.isSelected
    }
    
    private var hoverHighlightsEnabled: Bool {
        taskManager.animationManager.effectiveHoverHighlightsEnabled
    }
    
    private var highlightColor: Color {
        if isSelected {
            return selectionBackgroundColor
        }
        if isHoveringRow {
            return palette.hoverBackgroundColor.opacity(0.6)
        }
        return Color.clear
    }
    
    private var selectionBackgroundColor: Color {
        let baseColor = isWindowKey
            ? NSColor.selectedContentBackgroundColor
            : NSColor.unemphasizedSelectedContentBackgroundColor
        let blendFraction: CGFloat = palette.isDark ? 0.35 : 0.25
        let blended = baseColor.blended(withFraction: blendFraction, of: palette.controlBackground) ?? baseColor
        return Color(nsColor: blended)
    }
    
    private var rowForegroundColor: Color {
        guard isSelected else { return palette.primaryTextColor }
        if isWindowKey {
            return Color(nsColor: NSColor.alternateSelectedControlTextColor)
        }
        return palette.primaryTextColor
    }
    
    private var rowSecondaryColor: Color {
        if isSelected && isWindowKey {
            return rowForegroundColor.opacity(0.75)
        }
        return palette.secondaryTextColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: checkboxTopAligned ? .top : .center) {
                // Lock icon indicator (shown only on the task that is locked, not children)
                if mode == .live && task.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(rowSecondaryColor)
                        .font(.caption)
                        .frame(width: 12)
                } else if mode == .live && isInLockedThread {
                    // Spacer to maintain indentation for children of locked tasks
                    Spacer()
                        .frame(width: 12)
                }

                Group {
                    if mode == .live {
                        ClickThroughWrapper(onTap: {
                            releaseInputFocus?()
                            taskManager.registerUserInteractionTap()
                            taskManager.toggleTaskCompletion(task: task)
                        }) {
                            AnimatedCheckCircle(
                                isOn: task.isCompleted,
                                enabled: taskManager.animationsMasterEnabled && completionAnimationsEnabled,
                                baseColor: rowSecondaryColor,
                                accentColor: palette.accentColor
                            )
                                .frame(width: checkboxSize, height: checkboxSize)
                        }
                        .frame(width: checkboxSize, height: checkboxSize)
                    } else {
                        Text("•").foregroundColor(palette.secondaryTextColor)
                    }
                }
                .taskrFont(.body)

                Group {
                    if isEditing {
                        ExpandingTextEditor(
                            text: $editText,
                            isTextFieldFocused: $isTextFieldFocused,
                            onSubmit: { commitEdit() },
                            onCancel: { cancelEdit() }
                        )
                        .onChange(of: isTextFieldFocused) { _, isFocusedNow in
                            if !isFocusedNow && isEditing { commitEdit() }
                        }
                        .taskrFont(.body)
                        .padding(.horizontal, 2)
                        .background(palette.inputBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        AnimatedStrikeText(
                            text: task.name,
                            isStruck: task.isCompleted || hasCompletedAncestor,
                            enabled: taskManager.animationsMasterEnabled && completionAnimationsEnabled,
                            strikeColor: rowSecondaryColor
                        )
                        .taskrFont(.body)
                        .padding(.horizontal, 2)
                    }
                }
                .layoutPriority(1)

                Spacer()

                if hasExpandableChildren {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(chevronExpanded ? 90 : 0))
                        .taskrFont(.caption)
                        .foregroundColor(palette.secondaryTextColor)
                        .padding(5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            taskManager.registerUserInteractionTap()
                            taskManager.toggleTaskExpansion(taskID)
                        }
                        .onAppear {
                            chevronExpanded = isExpanded
                        }
                        .onChange(of: isExpanded) { _, newValue in
                            if chevronAnimEnabled {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    chevronExpanded = newValue
                                }
                            } else {
                                chevronExpanded = newValue
                            }
                        }
                        .onChange(of: chevronAnimEnabled) { _, _ in
                            chevronExpanded = isExpanded
                        }
                }

                if mode == .template {
                    templateActions
                }
            }

            if mode == .live && !displayTags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displayTags, id: \.id) { tag in
                        Text(tag.phrase)
                            .taskrFont(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(TaskTagPalette.color(for: tag.colorKey))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(.leading, tagChipLeadingPadding)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
        .frame(minHeight: baseRowHeight)
        .animation(rowHeightAnimEnabled ? .easeInOut(duration: 0.15) : nil, value: baseRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlightColor)
                .animation(hoverHighlightsEnabled ? .easeInOut(duration: 0.10) : nil, value: isHoveringRow)
        )
        .background(
            Group {
                if shouldReportRowHeight {
                    rowHeightReporter
                }
            }
        )
        .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
            guard mode == .live else { return }
            if let height = heights[taskID], height > 0 {
                let cachedHeight = taskManager.rowHeight(for: taskID)
                let needsUpdate = cachedHeight == nil || abs((cachedHeight ?? 0) - height) > 0.5
                if needsUpdate {
                    taskManager.setRowHeight(height, for: taskID)
                }
            }
        }
        .foregroundColor(rowForegroundColor)
        .contentShape(Rectangle())
        .onTapGesture {
            taskManager.registerUserInteractionTap()
            handlePrimarySelectionClick()
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { handleDoubleTapEdit() }
        )
        .onHover { hovering in
            if let event = NSApp.currentEvent, event.type == .scrollWheel {
                if !hovering { isHoveringRow = false }
                return
            }
            if isLiveScrolling {
                if !hovering { isHoveringRow = false }
                return
            }
            isHoveringRow = hovering
        }
        .onChange(of: isLiveScrolling) { _, liveScrolling in
            if liveScrolling {
                isHoveringRow = false
            }
        }
        .onChange(of: isWindowKey) { _, focused in
            guard !focused, isEditing else { return }
            isTextFieldFocused = false
            commitEdit()
        }
        .onDisappear {
            isHoveringRow = false
            taskManager.clearRowHeight(for: taskID)
        }
        .modifier(ShiftSelectionModifier(taskID: taskID, taskManager: taskManager))
        .contextMenu(menuItems: menuContent)
        .onChange(of: taskManager.pendingInlineEditTaskID) { _, _ in
            handleInlineEditRequestIfNeeded()
        }
        .onChange(of: selectionState.selectionGeneration) { _, _ in
            handleSelectionChangeWhileEditing()
        }
        .onAppear {
            handleInlineEditRequestIfNeeded()
        }
    }
    
    // ... (Private helpers moved from TaskRowView)
    
    @ViewBuilder
    private var templateActions: some View {
        let selectedCount = taskManager.selectedTaskIDs.count
        let isSelected = taskManager.isTaskSelected(taskID)
        let multiSelectionActive = selectedCount > 1 && isSelected
        
        HStack(spacing: 8) {
            Button {
                taskManager.addTemplateSubtask(to: task)
            } label: {
                Label("Subtask", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Add a subtask under \(task.name)")

            Button {
                if multiSelectionActive {
                    for id in taskManager.selectedTaskIDs {
                        if let t = taskManager.task(withID: id), t.isTemplateComponent {
                            taskManager.deleteTemplateTask(t)
                        }
                    }
                    taskManager.clearSelection()
                } else {
                    taskManager.deleteTemplateTask(task)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundColor(.red)
            .help(multiSelectionActive ? "Delete selected tasks" : "Delete \(task.name)")
        }
        .fixedSize()
        .frame(height: 22, alignment: .center)
    }

    @ViewBuilder
    private func menuContent() -> some View {
        if mode == .live {
            let selectedCount = taskManager.selectedTaskIDs.count
            let isRowSelected = taskManager.isTaskSelected(taskID)
            let multiSelectionActive = selectedCount > 1 && isRowSelected
            let canMoveUp = multiSelectionActive ? taskManager.canMoveSelectedTasksUp() : taskManager.canMoveTaskUp(task)
            let canMoveDown = multiSelectionActive ? taskManager.canMoveSelectedTasksDown() : taskManager.canMoveTaskDown(task)
            let canDuplicate = multiSelectionActive ? taskManager.canDuplicateSelectedTasks() : true
            let canMarkCompleted = multiSelectionActive ? taskManager.canMarkSelectedTasksCompleted() : false
            let canMarkUncompleted = multiSelectionActive ? taskManager.canMarkSelectedTasksUncompleted() : false

            Button("Edit (⏎)") {
                taskManager.requestInlineEdit(for: taskID)
            }
            .disabled(multiSelectionActive)
            Menu("Move (M+↑↓)") {
                Button("↑ Up (M+↑)") {
                    if multiSelectionActive {
                        taskManager.moveSelectedTasksUp()
                    } else {
                        taskManager.moveTaskUp(task)
                    }
                }
                .disabled(!canMoveUp)

                Button("↓ Down (M+↓)") {
                    if multiSelectionActive {
                        taskManager.moveSelectedTasksDown()
                    } else {
                        taskManager.moveTaskDown(task)
                    }
                }
                .disabled(!canMoveDown)
            }
            Button("Duplicate (⌘D)") {
                if multiSelectionActive {
                    taskManager.duplicateSelectedTasks()
                } else {
                    _ = taskManager.duplicateTask(task)
                }
            }
            .disabled(!canDuplicate)
            if multiSelectionActive {
                Button("Mark as Completed (⌘↩)") {
                    taskManager.markSelectedTasksCompleted()
                }
                .disabled(!canMarkCompleted)
                Button("Mark Uncompleted (⌘↩)") {
                    taskManager.markSelectedTasksUncompleted()
                }
                .disabled(!canMarkUncompleted)
            }
            Button("Add Subtask (⇧↩)") {
                if let newTask = taskManager.addSubtask(to: task) {
                    taskManager.requestInlineEdit(for: newTask.id)
                }
            }
            .disabled(multiSelectionActive)
            Menu("Tags") {
                let allTags = taskManager.fetchAllTags()
                let contextMenuTagTarget = ContextMenuTagTarget(rawValue: contextMenuTagTargetRaw) ?? .defaultTarget
                let shouldUseSelectionForTags: Bool = {
                    switch contextMenuTagTarget {
                    case .clickedItem:
                        return taskManager.isTaskSelected(taskID)
                    case .currentSelection:
                        return !taskManager.selectedTaskIDs.isEmpty
                    }
                }()
                let selectedLiveTasks = shouldUseSelectionForTags
                    ? taskManager.selectedTaskIDs.compactMap { id -> Task? in
                        guard let candidate = taskManager.task(withID: id),
                              !candidate.isTemplateComponent else { return nil }
                        return candidate
                    }
                    : [task]
                if allTags.isEmpty {
                    Button("No tags created") { }
                        .disabled(true)
                } else {
                    ForEach(allTags, id: \.id) { tag in
                        Button {
                            taskManager.toggleTag(tag, for: selectedLiveTasks)
                        } label: {
                            let appliedToAll = !selectedLiveTasks.isEmpty && selectedLiveTasks.allSatisfy { candidate in
                                (candidate.tags ?? []).contains(where: { $0.id == tag.id })
                            }
                            if appliedToAll {
                                Label(tag.phrase, systemImage: "checkmark")
                            } else {
                                Text(tag.phrase)
                            }
                        }
                    }
                }
            }
            Divider()
            if multiSelectionActive {
                Button("Copy Selected Tasks (⌘C)") {
                    taskManager.copySelectedTasksToPasteboard()
                }
            }
            Button("Copy Path") {
                taskManager.copyTaskPath(task)
            }
            .disabled(multiSelectionActive)
            Divider()
            Button(task.isLocked ? "Unlock Thread (⌘L)" : "Lock Thread (⌘L)") {
                if multiSelectionActive {
                    taskManager.toggleLockForSelectedTasks()
                } else {
                    taskManager.toggleLockForTask(task)
                }
            }
            Divider()
            Button(role: .destructive) {
                if multiSelectionActive {
                    taskManager.deleteSelectedTasks()
                } else {
                    taskManager.deleteTask(task)
                }
            } label: {
                Text(multiSelectionActive ? "Delete Selected (⌘⌫)" : "Delete (⌘⌫)")
            }
        } else if mode == .template {
            let selectedCount = taskManager.selectedTaskIDs.count
            let isRowSelected = taskManager.isTaskSelected(taskID)
            let multiSelectionActive = selectedCount > 1 && isRowSelected
            
            Button("Edit (⏎)") {
                taskManager.requestInlineEdit(for: taskID)
            }
            .disabled(multiSelectionActive)
            
            Menu("Move (M+↑↓)") {
                Button("↑ Up (M+↑)") {
                    taskManager.moveTemplateTaskUp(task)
                }
                .disabled(!taskManager.canMoveTemplateTaskUp(task))

                Button("↓ Down (M+↓)") {
                    taskManager.moveTemplateTaskDown(task)
                }
                .disabled(!taskManager.canMoveTemplateTaskDown(task))
            }
            
            Button("Duplicate (⌘D)") {
                taskManager.duplicateTemplateTask(task)
            }
            
            Button("Add Subtask (⇧↩)") {
                taskManager.addTemplateSubtask(to: task)
            }
            .disabled(multiSelectionActive)
            
            Divider()
            
            Button(role: .destructive) {
                if multiSelectionActive {
                    for id in taskManager.selectedTaskIDs {
                        if let t = taskManager.task(withID: id), t.isTemplateComponent {
                            taskManager.deleteTemplateTask(t)
                        }
                    }
                    taskManager.clearSelection()
                } else {
                    taskManager.deleteTemplateTask(task)
                }
            } label: {
                Text(multiSelectionActive ? "Delete Selected (⌘⌫)" : "Delete (⌘⌫)")
            }
        }
    }

    private var hasCompletedAncestor: Bool {
        let listKind: TaskManager.TaskListKind = mode == .live ? .live : .template
        if task.modelContext == nil {
            taskManager.noteOrphanedTask(id: taskID, context: "TaskRowView.hasCompletedAncestor")
        }
        return taskManager.hasCompletedAncestorCached(for: taskID, kind: listKind)
    }

    private var displayTags: [TaskTag] {
        guard mode == .live else { return [] }
        return taskManager.tagsForDisplay(on: task)
    }

    private var tagChipLeadingPadding: CGFloat {
        var indent = checkboxSize + 8
        if task.isLocked || isInLockedThread {
            indent += 12 + 8
        }
        return indent
    }

    private var isInLockedThread: Bool {
        taskManager.isTaskInLockedThread(task)
    }

    private func startEditing() {
        editText = task.name
        originalNameBeforeEdit = task.name
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }

    private func commitEdit() {
        guard isEditing else { return }

        let trimmedText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            editText = task.name
            isEditing = false
            return
        }

        if task.name != trimmedText {
            let originalName = task.name
            task.name = trimmedText
            do {
                if let context = task.modelContext {
                    try context.save()
                    context.processPendingChanges()
                }
            } catch {
                task.name = originalName
                editText = originalName
                print("Failed to save task rename: \(error)")
                return
            }
        }

        originalNameBeforeEdit = nil  // Clear FIRST to prevent race with cancelEdit
        isEditing = false
    }
    
    private func cancelEdit() {
        guard isEditing else { return }
        
        // Take the original name and clear immediately to prevent race conditions
        guard let original = originalNameBeforeEdit else {
            editText = task.name
            isEditing = false
            return
        }
        originalNameBeforeEdit = nil
        
        // Only revert if the task name hasn't already been modified (e.g., by commitEdit)
        if task.name != original {
            // Name was already changed (likely committed), don't revert
            editText = task.name
        } else {
            // Name unchanged, safe to revert
            task.name = original
            editText = original
        }
        isEditing = false
    }

    private func handleInlineEditRequestIfNeeded() {
        if taskManager.pendingInlineEditTaskID == taskID {
            startEditing()
            taskManager.pendingInlineEditTaskID = nil
        }
    }
    
    private func handleSelectionChangeWhileEditing() {
        guard isEditing else { return }
        if !selectionState.isSelected || taskManager.selectedTaskIDs.count != 1 {
            isTextFieldFocused = false
            commitEdit()
        }
    }

    private func handlePrimarySelectionClick() {
        releaseInputFocus?()

        let modifiers = currentModifierFlags()

        if modifiers.contains(.shift) {
            if mode == .template {
                if taskManager.selectionAnchorID == nil {
                    taskManager.replaceSelection(with: taskID)
                } else {
                    // Build visible template task IDs from cache
                    let kind = TaskManager.TaskListKind.template
                    taskManager.ensureChildCache(for: kind)
                    let visibleIDs = buildVisibleTemplateIDs()
                    taskManager.extendSelection(to: taskID, visibleTaskIDs: visibleIDs)
                }
            } else {
                taskManager.extendSelection(to: taskID)
            }
        } else if modifiers.contains(.command) {
            if mode == .template {
                let visibleIDs = buildVisibleTemplateIDs()
                taskManager.toggleSelection(for: taskID, visibleTaskIDs: visibleIDs)
            } else {
                taskManager.toggleSelection(for: taskID)
            }
        } else {
            taskManager.replaceSelection(with: taskID)
        }
    }
    
    private func buildVisibleTemplateIDs() -> [UUID] {
        let kind = TaskManager.TaskListKind.template
        taskManager.ensureChildCache(for: kind)
        guard let childMap = taskManager.childTaskCache[kind] else { return [] }
        
        // Get all root template containers (those with nil parent that are containers)
        var visibleIDs: [UUID] = []
        
        func collectVisible(parentID: UUID?) {
            let children = childMap[parentID] ?? []
            for child in children.sorted(by: { $0.displayOrder < $1.displayOrder }) {
                // Skip internal container nodes (TEMPLATE_INTERNAL_ROOT_CONTAINER)
                if child.name == "TEMPLATE_INTERNAL_ROOT_CONTAINER" {
                    // Still recurse into its children if expanded
                    if taskManager.isTaskExpanded(child.id) {
                        collectVisible(parentID: child.id)
                    }
                } else {
                    visibleIDs.append(child.id)
                    if taskManager.isTaskExpanded(child.id) {
                        collectVisible(parentID: child.id)
                    }
                }
            }
        }
        
        collectVisible(parentID: nil)
        return visibleIDs
    }
    
    private func handleDoubleTapEdit() {
        taskManager.registerUserInteractionTap()
        if !taskManager.isTaskSelected(taskID) {
            taskManager.replaceSelection(with: taskID)
        }
        startEditing()
    }

    private func currentModifierFlags() -> NSEvent.ModifierFlags {
        if let event = NSApp.currentEvent {
            return event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        }
        return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }
    
    private struct RowHeightPreferenceKey: PreferenceKey {
        static var defaultValue: [UUID: CGFloat] = [:]
        static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private var shouldReportRowHeight: Bool {
        guard mode == .live else { return false }
        return taskManager.isShiftSelectionInProgress || taskManager.rowHeight(for: taskID) == nil
    }

    private var rowHeightReporter: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: RowHeightPreferenceKey.self, value: [taskID: proxy.size.height])
        }
    }
}
