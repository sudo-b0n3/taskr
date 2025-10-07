// taskr/taskr/TaskRowView.swift
import SwiftUI
import SwiftData
import AppKit

struct TaskRowView: View {
    enum RowMode { case live, template }

    @Bindable var task: Task
    var mode: RowMode = .live
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.modelContext) private var modelContext

    @AppStorage(completionAnimationsEnabledPreferenceKey) private var completionAnimationsEnabled: Bool = true
    @AppStorage(checkboxTopAlignedPreferenceKey) private var checkboxTopAligned: Bool = true

    private var isExpanded: Bool {
        taskManager.isTaskExpanded(task.id)
    }

    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isHoveringRow: Bool = false

    private var displaySubtasks: [Task] {
        (task.subtasks ?? []).sorted { $0.displayOrder < $1.displayOrder }
    }

    private var hasExpandableChildren: Bool {
        !(task.subtasks?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent

            if isExpanded && !displaySubtasks.isEmpty {
                ForEach(displaySubtasks, id: \.persistentModelID) { subtask in
                    TaskRowView(task: subtask, mode: mode)
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
                    AnimatedCheckCircle(isOn: task.isCompleted, enabled: completionAnimationsEnabled)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { taskManager.toggleTaskCompletion(taskID: task.id) }
                } else {
                    Text("•").foregroundColor(.secondary)
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
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    AnimatedStrikeText(
                        text: task.name,
                        isStruck: task.isCompleted || hasCompletedAncestor,
                        enabled: completionAnimationsEnabled
                    )
                    .font(.body)
                    .padding(.horizontal, 2)
                    .onTapGesture(count: 2) { startEditing() }
                }
            }
            .layoutPriority(1)

            Spacer()

            if hasExpandableChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture { taskManager.toggleTaskExpansion(task.id) }
            }

            if mode == .template {
                templateActions
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHoveringRow ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHoveringRow = hovering
        }
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
            Button("Edit") {
                taskManager.requestInlineEdit(for: task.id)
            }
            Menu("Move") {
                Button("↑ Up") {
                    taskManager.moveTaskUp(task)
                }
                .disabled(!taskManager.canMoveTaskUp(task))

                Button("↓ Down") {
                    taskManager.moveTaskDown(task)
                }
                .disabled(!taskManager.canMoveTaskDown(task))
            }
            Button("Duplicate") {
                _ = taskManager.duplicateTask(task)
            }
            Button("Add Subtask") {
                if let newTask = taskManager.addSubtask(to: task) {
                    taskManager.requestInlineEdit(for: newTask.id)
                }
            }
            Divider()
            Button("Copy Path") {
                taskManager.copyTaskPath(task)
            }
            Divider()
            Button(role: .destructive) {
                taskManager.deleteTask(task)
            } label: {
                Text("Delete")
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

}

// MARK: - Animated UI Bits
private struct AnimatedCheckCircle: View {
    var isOn: Bool
    var enabled: Bool

    private let targetScale: CGFloat = 0.55
    private let animation: Animation = .easeInOut(duration: 0.16)

    var body: some View {
        ZStack {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color.accentColor)
                .scaleEffect(isOn ? targetScale : 0.0001)
                .animation(enabled ? animation : .none, value: isOn)
        }
    }
}

private struct AnimatedStrikeText: View {
    let text: String
    let isStruck: Bool
    let enabled: Bool
    private let animation: Animation = .easeInOut(duration: 0.18)

    var body: some View {
        let progress: CGFloat = isStruck ? 1.0 : 0.0
        ZStack(alignment: .leading) {
            Text(text)

            Text(text)
                .foregroundStyle(Color.clear)
                .strikethrough(true, color: .secondary)
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
