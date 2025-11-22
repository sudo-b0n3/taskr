import SwiftUI
import SwiftData
import AppKit

struct TaskRowContentView: View {
    @Bindable var task: Task
    var mode: TaskRowView.RowMode
    var releaseInputFocus: (() -> Void)?
    
    @EnvironmentObject var taskManager: TaskManager
    
    @AppStorage(completionAnimationsEnabledPreferenceKey) private var completionAnimationsEnabled: Bool = true
    @AppStorage(checkboxTopAlignedPreferenceKey) private var checkboxTopAligned: Bool = true
    
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isHoveringRow: Bool = false
    @State private var rowHeight: CGFloat = 0
    
    private let taskID: UUID
    
    init(task: Task, mode: TaskRowView.RowMode, releaseInputFocus: (() -> Void)?) {
        self._task = Bindable(task)
        self.mode = mode
        self.releaseInputFocus = releaseInputFocus
        self.taskID = task.id
    }
    
    private var isExpanded: Bool {
        taskManager.isTaskExpanded(taskID)
    }
    
    private var hasExpandableChildren: Bool {
        // We need to know if there are children to show the chevron.
        // Accessing childTasks here is okay as this view is for the specific row.
        // However, we want to avoid re-calculating the *list* of children if possible,
        // but checking for emptiness is cheap if cached.
        let listKind: TaskManager.TaskListKind = mode == .live ? .live : .template
        return !taskManager.childTasks(forParentID: taskID, kind: listKind).isEmpty
    }
    
    private var palette: ThemePalette { taskManager.themePalette }
    private var isSelected: Bool {
        taskManager.isTaskSelected(taskID)
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
        if taskManager.isApplicationActive && taskManager.isTaskWindowKey {
            return Color(nsColor: NSColor.selectedContentBackgroundColor)
        }
        return Color(nsColor: NSColor.unemphasizedSelectedContentBackgroundColor)
    }
    
    private var rowForegroundColor: Color {
        guard isSelected else { return palette.primaryTextColor }
        if taskManager.isApplicationActive && taskManager.isTaskWindowKey {
            return Color(nsColor: NSColor.alternateSelectedControlTextColor)
        }
        return palette.primaryTextColor
    }
    
    private var rowSecondaryColor: Color {
        if isSelected && taskManager.isApplicationActive && taskManager.isTaskWindowKey {
            return rowForegroundColor.opacity(0.75)
        }
        return palette.secondaryTextColor
    }
    
    var body: some View {
        HStack(alignment: checkboxTopAligned ? .top : .center) {
            Group {
                if mode == .live {
                    AnimatedCheckCircle(
                        isOn: task.isCompleted,
                        enabled: taskManager.animationsMasterEnabled && completionAnimationsEnabled,
                        baseColor: rowSecondaryColor,
                        accentColor: palette.accentColor
                    )
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            releaseInputFocus?()
                            taskManager.registerUserInteractionTap()
                            taskManager.toggleTaskCompletion(task: task)
                        }
                } else {
                    Text("•").foregroundColor(palette.secondaryTextColor)
                }
            }
            .font(.body)

            Group {
                if isEditing {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .onSubmit { commitEdit() }
                        .onChange(of: isTextFieldFocused) { _, isFocusedNow in
                            if !isFocusedNow && isEditing { commitEdit() }
                        }
                        .font(.body)
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
                    .font(.body)
                    .padding(.horizontal, 2)
                    .onTapGesture(count: 2) {
                        taskManager.registerUserInteractionTap()
                        startEditing()
                    }
                }
            }
            .layoutPriority(1)

            Spacer()

            if hasExpandableChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.secondaryTextColor)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        taskManager.registerUserInteractionTap()
                        taskManager.toggleTaskExpansion(taskID)
                    }
            }

            if mode == .template {
                templateActions
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlightColor)
        )
        .background(
            Group {
                if shouldReportRowHeight {
                    rowHeightReporter
                }
            }
        )
        .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
            if let height = heights[taskID], height > 0 {
                let needsUpdate = rowHeight == 0 || abs(rowHeight - height) > 0.5
                if needsUpdate {
                    rowHeight = height
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
        .onHover { hovering in
            isHoveringRow = hovering
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
        .onAppear {
            handleInlineEditRequestIfNeeded()
        }
    }
    
    // ... (Private helpers moved from TaskRowView)
    
    @ViewBuilder
    private var templateActions: some View {
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
                taskManager.deleteTemplateTask(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundColor(.red)
            .help("Delete \(task.name) from this template")
        }
        .fixedSize()
        .frame(height: 22, alignment: .center)
    }

    @ViewBuilder
    private func menuContent() -> some View {
        if mode == .live {
            SelectionContextPrimingView(taskManager: taskManager, taskID: taskID)
            let selectedCount = taskManager.selectedTaskIDs.count
            let isRowSelected = taskManager.isTaskSelected(taskID)
            let multiSelectionActive = selectedCount > 1 && isRowSelected
            let canMoveUp = multiSelectionActive ? taskManager.canMoveSelectedTasksUp() : taskManager.canMoveTaskUp(task)
            let canMoveDown = multiSelectionActive ? taskManager.canMoveSelectedTasksDown() : taskManager.canMoveTaskDown(task)
            let canDuplicate = multiSelectionActive ? taskManager.canDuplicateSelectedTasks() : true
            let canMarkCompleted = multiSelectionActive ? taskManager.canMarkSelectedTasksCompleted() : false
            let canMarkUncompleted = multiSelectionActive ? taskManager.canMarkSelectedTasksUncompleted() : false

            Button("Edit") {
                taskManager.requestInlineEdit(for: taskID)
            }
            .disabled(multiSelectionActive)
            Menu("Move") {
                Button("↑ Up") {
                    if multiSelectionActive {
                        taskManager.moveSelectedTasksUp()
                    } else {
                        taskManager.moveTaskUp(task)
                    }
                }
                .disabled(!canMoveUp)

                Button("↓ Down") {
                    if multiSelectionActive {
                        taskManager.moveSelectedTasksDown()
                    } else {
                        taskManager.moveTaskDown(task)
                    }
                }
                .disabled(!canMoveDown)
            }
            Button("Duplicate") {
                if multiSelectionActive {
                    taskManager.duplicateSelectedTasks()
                } else {
                    _ = taskManager.duplicateTask(task)
                }
            }
            .disabled(!canDuplicate)
            if multiSelectionActive {
                Button("Mark as Completed") {
                    taskManager.markSelectedTasksCompleted()
                }
                .disabled(!canMarkCompleted)
                Button("Mark Uncompleted") {
                    taskManager.markSelectedTasksUncompleted()
                }
                .disabled(!canMarkUncompleted)
            }
            Button("Add Subtask") {
                if let newTask = taskManager.addSubtask(to: task) {
                    taskManager.requestInlineEdit(for: newTask.id)
                }
            }
            .disabled(multiSelectionActive)
            Divider()
            if !taskManager.selectedTaskIDs.isEmpty {
                Button("Copy Selected Tasks") {
                    taskManager.copySelectedTasksToPasteboard()
                }
            }
            Button("Copy Path") {
                taskManager.copyTaskPath(task)
            }
            .disabled(multiSelectionActive)
            Divider()
            Button(role: .destructive) {
                if multiSelectionActive {
                    taskManager.deleteSelectedTasks()
                } else {
                    taskManager.deleteTask(task)
                }
            } label: {
                Text(multiSelectionActive ? "Delete Selected" : "Delete")
            }
        } else if mode == .template {
            Button("Edit") {
                taskManager.requestInlineEdit(for: taskID)
            }
            Menu("Move") {
                Button("↑ Up") {
                    taskManager.moveTemplateTaskUp(task)
                }
                .disabled(!taskManager.canMoveTemplateTaskUp(task))

                Button("↓ Down") {
                    taskManager.moveTemplateTaskDown(task)
                }
                .disabled(!taskManager.canMoveTemplateTaskDown(task))
            }
        }
    }

    private struct SelectionContextPrimingView: View {
        let taskManager: TaskManager
        let taskID: UUID

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    DispatchQueue.main.async {
                        if !taskManager.isTaskSelected(taskID) {
                            taskManager.replaceSelection(with: taskID)
                        }
                    }
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

    private func startEditing() {
        editText = task.name
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

        isEditing = false
    }

    private func handleInlineEditRequestIfNeeded() {
        if taskManager.pendingInlineEditTaskID == taskID {
            startEditing()
            taskManager.pendingInlineEditTaskID = nil
        }
    }

    private func handlePrimarySelectionClick() {
        releaseInputFocus?()

        let modifiers = currentModifierFlags()

        if modifiers.contains(.shift) {
            taskManager.extendSelection(to: taskID)
        } else if modifiers.contains(.command) {
            taskManager.toggleSelection(for: taskID)
        } else {
            taskManager.replaceSelection(with: taskID)
        }
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

    private var effectiveRowHeight: CGFloat {
        rowHeight > 0 ? rowHeight : 28
    }

    private var shouldReportRowHeight: Bool {
        taskManager.isShiftSelectionInProgress || taskManager.rowHeight(for: taskID) == nil
    }

    private var rowHeightReporter: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: RowHeightPreferenceKey.self, value: [taskID: proxy.size.height])
        }
    }
}
