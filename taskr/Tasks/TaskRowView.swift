import SwiftUI
import SwiftData
import AppKit

struct TaskRowView: View {
    enum RowMode { case live, template }

    @Bindable var task: Task
    var mode: RowMode = .live
    var releaseInputFocus: (() -> Void)? = nil
    @EnvironmentObject var taskManager: TaskManager

    private let taskID: UUID

    init(task: Task, mode: RowMode = .live, releaseInputFocus: (() -> Void)? = nil) {
        self._task = Bindable(task)
        self.mode = mode
        self.releaseInputFocus = releaseInputFocus
        self.taskID = task.id
    }

    private var isExpanded: Bool {
        taskManager.isTaskExpanded(taskID)
    }

    private var displaySubtasks: [Task] {
        let listKind: TaskManager.TaskListKind = mode == .live ? .live : .template
        if task.modelContext == nil {
            taskManager.noteOrphanedTask(id: taskID, context: "TaskRowView.displaySubtasks")
        }
        return taskManager.childTasks(forParentID: taskID, kind: listKind)
    }

    var body: some View {
        Group {
            if isDetached {
                orphanedRowFallback
            } else {
                renderedRow
            }
        }
    }

    private var isDetached: Bool {
        task.modelContext == nil
    }

    private var orphanedRowFallback: some View {
        EmptyView()
            .frame(width: 0, height: 0)
            .onAppear {
                taskManager.noteOrphanedTask(id: taskID, context: "TaskRowView.body")
            }
    }

    private var renderedRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use the isolated content view for the row itself
            TaskRowContentView(
                task: task,
                mode: mode,
                selectionState: taskManager.selectionManager.selectionState(for: taskID),
                releaseInputFocus: releaseInputFocus
            )

            // Recursively render children if expanded
            if isExpanded && !displaySubtasks.isEmpty {
                ForEach(displaySubtasks, id: \.persistentModelID) { subtask in
                    TaskRowView(task: subtask, mode: mode, releaseInputFocus: releaseInputFocus)
                        .padding(.leading, 20)
                }
            }
        }
    }
}
