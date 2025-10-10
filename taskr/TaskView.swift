// taskr/taskr/TaskView.swift
import SwiftUI
import SwiftData

struct TaskView: View {
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.modelContext) private var modelContext
    // Fetch tasks sorted by displayOrder for stable UI diffs
    @Query(
        filter: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
        sort: [SortDescriptor(\Task.displayOrder, order: .forward)],
        animation: .default
    ) private var tasks: [Task]

    @FocusState private var isInputFocused: Bool

    // Always display by persisted displayOrder; settings affect only insertion
    private var displayTasks: [Task] { tasks }
    private var palette: ThemePalette { taskManager.themePalette }
    private var backgroundColor: Color {
        taskManager.frostedBackgroundEnabled ? .clear : palette.backgroundColor
    }

    var body: some View {
        // Main VStack for the entire view
        VStack(alignment: .leading, spacing: 0) {

            // --- Top Controls Area ---
            // This VStack contains all the controls and sits at the top
            VStack(alignment: .leading, spacing: 4) {
                // Input Field Row
                HStack {
                    CustomTextField(
                        text: $taskManager.currentPathInput,
                        placeholder: "Type task or path /task/subtask",
                        onCommit: { taskManager.addTaskFromPath(); isInputFocused = true },
                        onTextChange: { newText in taskManager.updateAutocompleteSuggestions(for: newText) },
                        onTab: { if !taskManager.autocompleteSuggestions.isEmpty { taskManager.applySelectedSuggestion(); isInputFocused = true }},
                        onShiftTab: { if !taskManager.autocompleteSuggestions.isEmpty { taskManager.selectPreviousSuggestion() }},
                        onArrowDown: { taskManager.selectNextSuggestion() },
                        onArrowUp: { taskManager.selectPreviousSuggestion() },
                        fieldBackgroundColor: palette.inputBackground,
                        fieldTextColor: palette.primaryText
                    )
                    .focused($isInputFocused).frame(height: 22)
                    Button(action: { taskManager.addTaskFromPath(); isInputFocused = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(palette.accentColor)
                    }.buttonStyle(PlainButtonStyle()).padding(.leading, 4)
                }
                // Clear Button Row
                HStack {
                    Spacer()
                    Button("Clear Completed") { taskManager.clearCompletedTasks() }
                        .padding(.top, 4)
                        .foregroundColor(palette.primaryTextColor)
                }
                // Autocomplete Suggestions List
                if !taskManager.autocompleteSuggestions.isEmpty {
                    List(selection: $taskManager.selectedSuggestionIndex) {
                        ForEach(0..<taskManager.autocompleteSuggestions.count, id: \.self) { index in
                            Text(taskManager.autocompleteSuggestions[index])
                                .padding(.vertical, 2)
                                .foregroundColor(palette.primaryTextColor)
                                .listRowBackground(taskManager.selectedSuggestionIndex == index ? palette.accentColor.opacity(0.3) : palette.controlBackgroundColor)
                                .onTapGesture {
                                    taskManager.selectedSuggestionIndex = index
                                    taskManager.applySelectedSuggestion()
                                    isInputFocused = true
                                }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(palette.controlBackgroundColor)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.dividerColor.opacity(0.7), lineWidth: 1))
                    .padding(.top, 2)
                }
            }
            .padding([.horizontal, .top]) // Padding for the controls area
            .padding(.bottom, 8) // Space before the divider
            // --- End Top Controls Area ---

            Divider()
                .background(palette.dividerColor) // Divider between controls and task list

            // --- Task List Area ---
            // ScrollView now naturally sits below the controls and divider
            ScrollView {
                // Use a LazyVStack for potentially better performance with many tasks
                LazyVStack(alignment: .leading, spacing: 0) {
                    if displayTasks.isEmpty {
                        Text("No tasks yet. Add one above!")
                            .foregroundColor(palette.secondaryTextColor).padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(displayTasks, id: \.persistentModelID) { task in
                            TaskRowView(task: task)
                                .padding(.top, 4)
                                .padding(.bottom, 4)
                            // Add divider only if it's not the last task in the list
                            if task.id != displayTasks.last?.id {
                                Divider().background(palette.dividerColor)
                            }
                        }
                    }
                }
                // Add top padding inside the ScrollView if needed,
                // but the VStack structure should handle spacing now.
                // .padding(.top, 4)
            }
            .onAppear { isInputFocused = true }
            // --- End Task List Area ---

        } // End main VStack
        .foregroundColor(palette.primaryTextColor)
        .background(backgroundColor)
    } // End body
} // End TaskView

// Preview Provider
struct TaskView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)
        
        // Create some preview tasks with different display orders
        let task1 = Task(name: "Preview Root Task 1 (Older)", displayOrder: 0, isTemplateComponent: false)
        container.mainContext.insert(task1)
        let sub1 = Task(name: "Preview Subtask 1.1", displayOrder: 0, isTemplateComponent: false, parentTask: task1)
        container.mainContext.insert(sub1)
        task1.subtasks?.append(sub1) // Append for preview consistency

        let task2 = Task(name: "Preview Root Task 2 (Newer)", displayOrder: 1, isTemplateComponent: false)
        container.mainContext.insert(task2)

        // Seed insertion preferences for preview
        UserDefaults.standard.set(true, forKey: addRootTasksToTopPreferenceKey)
        UserDefaults.standard.set(false, forKey: addSubtasksToTopPreferenceKey)

        return TaskView()
            .modelContainer(container)
            .environmentObject(taskManager)
            .frame(width: 380, height: 400) // Standard preview frame
            .background(taskManager.themePalette.backgroundColor) // Match background
    }
}
