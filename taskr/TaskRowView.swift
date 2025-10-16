// taskr/taskr/TaskRowView.swift
import SwiftUI
import SwiftData
import AppKit

struct TaskRowView: View {
    enum RowMode { case live, template }

    @Bindable var task: Task
    var mode: RowMode = .live
    var releaseInputFocus: (() -> Void)? = nil
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.modelContext) private var modelContext

    @AppStorage(completionAnimationsEnabledPreferenceKey) private var completionAnimationsEnabled: Bool = true
    @AppStorage(checkboxTopAlignedPreferenceKey) private var checkboxTopAligned: Bool = true
    @Query private var liveChildTasks: [Task]
    @Query private var templateChildTasks: [Task]

    init(task: Task, mode: RowMode = .live, releaseInputFocus: (() -> Void)? = nil) {
        self._task = Bindable(task)
        self.mode = mode
        self.releaseInputFocus = releaseInputFocus

        let parentID = task.id
        _liveChildTasks = Query(
            filter: #Predicate<Task> {
                !$0.isTemplateComponent && $0.parentTask?.id == parentID
            },
            sort: [SortDescriptor(\Task.displayOrder, order: .forward)]
        )
        _templateChildTasks = Query(
            filter: #Predicate<Task> {
                $0.isTemplateComponent && $0.parentTask?.id == parentID
            },
            sort: [SortDescriptor(\Task.displayOrder, order: .forward)]
        )
    }

    private var isExpanded: Bool {
        taskManager.isTaskExpanded(task.id)
    }

    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isHoveringRow: Bool = false
    @State private var didStartShiftDrag: Bool = false

    private var displaySubtasks: [Task] {
        guard task.modelContext != nil else { return [] }
        switch mode {
        case .live:
            return liveChildTasks
        case .template:
            return templateChildTasks
        }
    }

    private var hasExpandableChildren: Bool {
        !displaySubtasks.isEmpty
    }

    private var palette: ThemePalette { taskManager.themePalette }
    private var isSelected: Bool {
        taskManager.isTaskSelected(task.id)
    }
    private var highlightColor: Color {
        if isSelected {
            let activeOpacity = (taskManager.isApplicationActive && taskManager.isTaskWindowKey) ? 1.0 : 0.35
            return palette.hoverBackgroundColor.opacity(activeOpacity)
        }
        if isHoveringRow {
            return palette.hoverBackgroundColor
        }
        return Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent

            if isExpanded && !displaySubtasks.isEmpty {
                ForEach(displaySubtasks, id: \.persistentModelID) { subtask in
                    TaskRowView(task: subtask, mode: mode, releaseInputFocus: releaseInputFocus)
                        .padding(.leading, 20)
                }
            }
        }
        .contextMenu(menuItems: menuContent)
        .onChange(of: taskManager.pendingInlineEditTaskID) { _, _ in
            handleInlineEditRequestIfNeeded()
        }
        .onAppear {
            handleInlineEditRequestIfNeeded()
        }
    }

    private var rowContent: some View {
        HStack(alignment: checkboxTopAligned ? .top : .center) {
            Group {
                if mode == .live {
                    AnimatedCheckCircle(
                        isOn: task.isCompleted,
                        enabled: completionAnimationsEnabled,
                        baseColor: palette.secondaryTextColor,
                        accentColor: palette.accentColor
                    )
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            releaseInputFocus?()
                            taskManager.registerUserInteractionTap()
                            taskManager.toggleTaskCompletion(taskID: task.id)
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
                        enabled: completionAnimationsEnabled,
                        strikeColor: palette.secondaryTextColor
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
                        taskManager.toggleTaskExpansion(task.id)
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
        .foregroundColor(palette.primaryTextColor)
        .contentShape(Rectangle())
        .onTapGesture {
            taskManager.registerUserInteractionTap()
            handlePrimarySelectionClick()
        }
        .onHover { hovering in
            isHoveringRow = hovering
            if hovering && taskManager.isShiftSelectionInProgress {
                taskManager.updateShiftSelection(to: task.id)
            }
        }
        .onDisappear {
            isHoveringRow = false
        }
        .simultaneousGesture(shiftSelectionGesture)
    }

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
            SelectionContextPrimingView(taskManager: taskManager, taskID: task.id)
            let selectedCount = taskManager.selectedTaskIDs.count
            let isRowSelected = taskManager.isTaskSelected(task.id)
            let multiSelectionActive = selectedCount > 1 && isRowSelected
            let canMoveUp = multiSelectionActive ? taskManager.canMoveSelectedTasksUp() : taskManager.canMoveTaskUp(task)
            let canMoveDown = multiSelectionActive ? taskManager.canMoveSelectedTasksDown() : taskManager.canMoveTaskDown(task)
            let canDuplicate = multiSelectionActive ? taskManager.canDuplicateSelectedTasks() : true

            Button("Edit") {
                taskManager.requestInlineEdit(for: task.id)
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
                taskManager.requestInlineEdit(for: task.id)
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
                        if !taskManager.isTaskSelected(taskID),
                           taskManager.selectedTaskIDs.count <= 1 {
                            taskManager.replaceSelection(with: taskID)
                        }
                    }
                }
        }
    }

    private var hasCompletedAncestor: Bool {
        var cur = task.parentTask
        while let t = cur {
            if t.isCompleted { return true }
            cur = t.parentTask
        }
        return false
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
                try modelContext.save()
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
        if taskManager.pendingInlineEditTaskID == task.id {
            startEditing()
            taskManager.pendingInlineEditTaskID = nil
        }
    }

    private func handlePrimarySelectionClick() {
        releaseInputFocus?()

        let modifiers = currentModifierFlags()

        if modifiers.contains(.shift) {
            taskManager.extendSelection(to: task.id)
        } else if modifiers.contains(.command) {
            taskManager.toggleSelection(for: task.id)
        } else {
            taskManager.replaceSelection(with: task.id)
        }
    }

    private func currentModifierFlags() -> NSEvent.ModifierFlags {
        if let event = NSApp.currentEvent {
            return event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        }
        return NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private var shiftSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                let shiftDown = currentModifierFlags().contains(.shift)
                if !shiftDown {
                    if didStartShiftDrag {
                        didStartShiftDrag = false
                        taskManager.endShiftSelection()
                    }
                    return
                }

                if !didStartShiftDrag {
                    didStartShiftDrag = true
                    taskManager.beginShiftSelection(at: task.id)
                }
            }
            .onEnded { _ in
                if didStartShiftDrag {
                    didStartShiftDrag = false
                    taskManager.endShiftSelection()
                }
            }
    }

}

// MARK: - Animated UI Bits
private struct AnimatedCheckCircle: View {
    var isOn: Bool
    var enabled: Bool
    var baseColor: Color
    var accentColor: Color

    private let targetScale: CGFloat = 0.55
    private let animation: Animation = .easeInOut(duration: 0.16)

    var body: some View {
        ZStack {
            Image(systemName: "circle")
                .foregroundColor(baseColor)
            Circle()
                .fill(accentColor)
                .scaleEffect(isOn ? targetScale : 0.0001)
                .animation(enabled ? animation : .none, value: isOn)
        }
    }
}

private struct AnimatedStrikeText: View {
    let text: String
    let isStruck: Bool
    let enabled: Bool
    let strikeColor: Color
    private let animation: Animation = .easeInOut(duration: 0.18)

    var body: some View {
        let progress: CGFloat = isStruck ? 1.0 : 0.0
        ZStack(alignment: .leading) {
            Text(text)

            Text(text)
                .foregroundStyle(Color.clear)
                .strikethrough(true, color: strikeColor)
                .mask(
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * progress, height: proxy.size.height, alignment: .leading)
                    }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(enabled ? animation : .none, value: isStruck)
    }
}
