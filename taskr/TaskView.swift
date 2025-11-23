// taskr/taskr/TaskView.swift
import SwiftUI
import SwiftData
import AppKit

struct TaskView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var inputState: TaskInputState
    @Environment(\.modelContext) private var modelContext
    // Fetch tasks sorted by displayOrder for stable UI diffs
    @Query(
        filter: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
        sort: [SortDescriptor(\Task.displayOrder, order: .forward)]
    ) private var tasks: [Task]
    
    @AppStorage("hasCompletedSetup") var hasCompletedSetup: Bool = false

    @FocusState private var isInputFocused: Bool
    @State private var keyboardMonitor: Any?
    @State private var appObserverTokens: [NSObjectProtocol] = []
    @State private var windowObserverTokens: [NSObjectProtocol] = []
    @State private var hostingWindow: NSWindow?
    @State private var isWindowFocused: Bool = false

    // Always display by persisted displayOrder; settings affect only insertion
    private var displayTasks: [Task] { tasks }
    private var palette: ThemePalette { taskManager.themePalette }
    private var backgroundColor: Color {
        taskManager.frostedBackgroundEnabled ? .clear : palette.backgroundColor
    }
    private var releaseTaskInputFocus: () -> Void {
        return {
            isInputFocused = false
            taskManager.setTaskInputFocused(false)
        }
    }

    var body: some View {
        // Main VStack for the entire view
        VStack(alignment: .leading, spacing: 0) {

            // --- Top Controls Area ---
            // This VStack contains all the controls and sits at the top
            VStack(alignment: .leading, spacing: 0) {
                // Input Field Row
                HStack {
                    CustomTextField(
                        text: $inputState.text,
                        placeholder: "Type task or path /task/subtask",
                        onCommit: { taskManager.addTaskFromPath(); isInputFocused = true },
                        onTextChange: { newText in taskManager.updateAutocompleteSuggestions(for: newText) },
                        onTab: { if inputState.hasSuggestions { taskManager.applySelectedSuggestion(); isInputFocused = true }},
                        onShiftTab: { if inputState.hasSuggestions { taskManager.selectPreviousSuggestion() }},
                        onArrowDown: { taskManager.selectNextSuggestion() },
                        onArrowUp: { taskManager.selectPreviousSuggestion() },
                        fieldTextColor: palette.primaryText,
                        placeholderTextColor: palette.secondaryText
                    )
                    .focused($isInputFocused)
                    .disabled(!hasCompletedSetup)
                    Button(action: { taskManager.addTaskFromPath(); isInputFocused = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(palette.accentColor)
                    }.buttonStyle(PlainButtonStyle()).padding(.leading, 4)
                }
                .padding(.bottom, 8)
                // Clear Button Row
                HStack {
                    Spacer()
                    Button("Clear Completed") { taskManager.clearCompletedTasks() }
                        .padding(.top, 4)
                        .foregroundColor(palette.primaryTextColor)
                }
                // Autocomplete Suggestions List
                if !inputState.suggestions.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(inputState.suggestions.enumerated()), id: \.0) { index, suggestion in
                                Text(suggestion)
                                    .foregroundColor(palette.primaryTextColor)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        (inputState.selectedSuggestionIndex == index ? palette.accentColor.opacity(0.3) : palette.controlBackgroundColor)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        inputState.selectedSuggestionIndex = index
                                        taskManager.applySelectedSuggestion()
                                        isInputFocused = true
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                    .background(palette.controlBackgroundColor)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.dividerColor.opacity(0.7), lineWidth: 1))
                    .padding(.top, 2)
                }
            }
            .padding([.horizontal, .top]) // Padding for the controls area
            .padding(.bottom, 8) // Space before the divider
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        taskManager.registerUserInteractionTap()
                    }
            )
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
                            TaskRowView(task: task, releaseInputFocus: releaseTaskInputFocus)
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
            .onAppear {
                if hasCompletedSetup {
                    isInputFocused = true
                    taskManager.setTaskInputFocused(true)
                }
                installKeyboardMonitorIfNeeded()
                installLifecycleObservers()
            }
            .onChange(of: hasCompletedSetup) { _, newValue in
                if newValue {
                    // Setup just completed, set focus
                    isInputFocused = true
                    taskManager.setTaskInputFocused(true)
                } else {
                    // Setup is being shown, remove focus
                    isInputFocused = false
                    taskManager.setTaskInputFocused(false)
                }
            }
            // --- End Task List Area ---

        } // End main VStack
        .foregroundColor(palette.primaryTextColor)
        .background(backgroundColor)
        .environment(\.isWindowFocused, isWindowFocused)
        .onChange(of: isInputFocused) { _, newValue in
            taskManager.setTaskInputFocused(newValue)
        }
        .onDisappear {
            removeKeyboardMonitor()
            taskManager.setTaskInputFocused(false)
            removeLifecycleObservers()
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    DispatchQueue.main.async {
                        if !taskManager.consumeInteractionCapture(),
                           !taskManager.selectedTaskIDs.isEmpty {
                            taskManager.clearSelection()
                        }
                    }
                }
        )
        .background {
            WindowAccessor { window in
                DispatchQueue.main.async {
                    handleWindowChange(window)
                }
            }
        }
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
            .environmentObject(taskManager.inputState)
            .frame(width: 380, height: 400) // Standard preview frame
            .background(taskManager.themePalette.backgroundColor) // Match background
    }
}

private struct WindowAccessor: NSViewRepresentable {
    var onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChange(nsView.window)
        }
    }
}

// MARK: - Keyboard Handling
extension TaskView {
    private func installKeyboardMonitorIfNeeded() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard handleKeyDownEvent(event) else { return event }
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard shouldHandleKeyEvent(event) else { return false }

        let flags = event.modifierFlags
        let shiftPressed = flags.contains(.shift)
        let commandPressed = flags.contains(.command)

        if commandPressed {
            if let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "a":
                    taskManager.selectAllVisibleTasks()
                    return true
                default:
                    break
                }
            }
        }

        switch event.keyCode {
        case 125: // Down arrow
            guard !commandPressed else { return false }
            taskManager.stepSelection(.down, extend: shiftPressed)
            return true
        case 126: // Up arrow
            guard !commandPressed else { return false }
            taskManager.stepSelection(.up, extend: shiftPressed)
            return true
        case 53: // Escape
            guard !commandPressed && !shiftPressed else { return false }
            if !taskManager.selectedTaskIDs.isEmpty {
                taskManager.clearSelection()
                return true
            }
            return false
        default:
            break
        }

        return false
    }

    private func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        guard window.isKeyWindow else { return false }

        if taskManager.isTaskInputFocused {
            return false
        }

        return true
    }

    @MainActor
    private func installLifecycleObservers() {
        taskManager.setApplicationActive(NSApp.isActive)
        if appObserverTokens.isEmpty {
            let center = NotificationCenter.default
            let become = center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                _Concurrency.Task { @MainActor in
                    taskManager.setApplicationActive(true)
                }
            }
            let resign = center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                _Concurrency.Task { @MainActor in
                    taskManager.setApplicationActive(false)
                }
            }
            appObserverTokens = [become, resign]
        }

        if let window = hostingWindow {
            isWindowFocused = window.isKeyWindow
        }
    }

    @MainActor
    private func removeLifecycleObservers() {
        let center = NotificationCenter.default
        for token in appObserverTokens {
            center.removeObserver(token)
        }
        appObserverTokens.removeAll()

        for token in windowObserverTokens {
            center.removeObserver(token)
        }
        windowObserverTokens.removeAll()

        hostingWindow = nil
        isWindowFocused = false
    }

    @MainActor
    private func handleWindowChange(_ window: NSWindow?) {
        guard hostingWindow !== window else { return }

        let center = NotificationCenter.default
        for token in windowObserverTokens {
            center.removeObserver(token)
        }
        windowObserverTokens.removeAll()

        hostingWindow = window

        guard let window else {
            isWindowFocused = false
            return
        }

        isWindowFocused = window.isKeyWindow

        let become = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in
                isWindowFocused = true
            }
        }
        let resign = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in
                isWindowFocused = false
            }
        }
        windowObserverTokens = [become, resign]
    }
}
