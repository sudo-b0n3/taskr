// taskr/taskr/TaskView.swift
import SwiftUI
import SwiftData
import AppKit

struct TaskView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.modelContext) private var modelContext
    // Fetch tasks sorted by displayOrder for stable UI diffs
    @Query(
        filter: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
        sort: [SortDescriptor(\Task.displayOrder, order: .forward)]
    ) private var tasks: [Task]
    
    @AppStorage("hasCompletedSetup") var hasCompletedSetup: Bool = false

    @FocusState private var isInputFocused: Bool
    @State private var keyboardMonitor: Any?
    @State private var isMKeyPressed: Bool = false
    @State private var appObserverTokens: [NSObjectProtocol] = []
    @State private var windowObserverTokens: [NSObjectProtocol] = []
    @State private var hostingWindow: NSWindow?
    @State private var isWindowFocused: Bool = false
    @State private var isLiveScrolling: Bool = false
    
    // Paste dialog state
    @State private var showPasteRootConfirmation: Bool = false
    @State private var showPasteError: Bool = false
    @State private var pasteErrorMessage: String = ""
    @State private var dontAskPasteAgain: Bool = false
    @State private var pendingPasteTaskCount: Int = 0

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
        VStack(alignment: .leading, spacing: 0) {
            TaskInputHeader(
                isInputFocused: $isInputFocused,
                hasCompletedSetup: hasCompletedSetup
            )
            Divider().background(palette.dividerColor)
            taskList
        }
        .foregroundColor(palette.primaryTextColor)
        .background(backgroundColor)
        .environment(\.isWindowFocused, isWindowFocused)
        .environment(\.isLiveScrolling, isLiveScrolling)
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
        .onChange(of: taskManager.pendingPasteResult) { _, result in
            handlePasteResult(result)
        }
        .overlay(alignment: .top) {
            if showPasteRootConfirmation {
                pasteRootConfirmationView
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(taskManager.animationManager.animationsMasterEnabled ? .easeInOut(duration: 0.2) : .none, value: showPasteRootConfirmation)
        .alert("Cannot Paste", isPresented: $showPasteError) {
            Button("OK", role: .cancel) {
                taskManager.pendingPasteResult = nil
            }
        } message: {
            Text(pasteErrorMessage)
        }
    } // End body
} // End TaskView

private extension TaskView {
    @ViewBuilder
    var taskList: some View {
        // Keep the query alive so SwiftUI observes model changes that invalidate TaskManager caches
        let _ = tasks
        let visible = taskManager.snapshotVisibleTasksWithDepth()
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visible.isEmpty {
                        Text("No tasks yet. Add one above!")
                            .foregroundColor(palette.secondaryTextColor)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(Array(visible.enumerated()), id: \.1.task.persistentModelID) { index, entry in
                            FlatTaskRowView(
                                task: entry.task,
                                depth: entry.depth,
                                selectionState: taskManager.selectionManager.selectionState(for: entry.task.id),
                                releaseInputFocus: releaseTaskInputFocus
                            )
                                .padding(.top, 4)
                                .padding(.bottom, 4)
                                .id(entry.task.id)
                                .transition(taskManager.animationsMasterEnabled
                                    && taskManager.animationManager.itemTransitionsEnabled
                                    && taskManager.collapseAnimationsEnabled
                                    ? .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity
                                    )
                                    : .identity
                                )
                            let nextDepth = index + 1 < visible.count ? visible[index + 1].depth : nil
                            // Only separate roots from the next root; avoid separating roots from their own children
                            if nextDepth == 0 {
                                Divider().background(palette.dividerColor)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(!isLiveScrolling)
            }
            .background(LiveScrollObserver(isLiveScrolling: $isLiveScrolling))
            .overlay {
                SelectionScrollCoordinator(proxy: proxy)
                    .environmentObject(taskManager.selectionManager)
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
                    isInputFocused = true
                    taskManager.setTaskInputFocused(true)
                } else {
                    isInputFocused = false
                    taskManager.setTaskInputFocused(false)
                }
            }
        }
    }
    
    /// Compact confirmation bar for pasting at root level
    @ViewBuilder
    var pasteRootConfirmationView: some View {
        let palette = taskManager.themePalette
        
        HStack(spacing: 12) {
            Text("Paste at root?")
                .taskrFont(.callout)
                .foregroundColor(palette.primaryTextColor)
            
            Spacer()
            
            Toggle("Don't ask", isOn: $dontAskPasteAgain)
                .toggleStyle(.checkbox)
                .taskrFont(.caption)
                .foregroundColor(palette.secondaryTextColor)
            
            Button("Cancel") {
                dismissPasteConfirmation()
            }
            .buttonStyle(.plain)
            .taskrFont(.callout)
            .foregroundColor(palette.secondaryTextColor)
            .keyboardShortcut(.escape, modifiers: [])
            
            Button("Paste") {
                confirmPaste()
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accentColor)
            .taskrFont(.callout)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.inputBackgroundColor)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    private func dismissPasteConfirmation() {
        showPasteRootConfirmation = false
        taskManager.pendingPasteResult = nil
    }
    
    private func confirmPaste() {
        if dontAskPasteAgain {
            UserDefaults.standard.set(true, forKey: skipPasteRootConfirmationPreferenceKey)
        }
        showPasteRootConfirmation = false
        _ = taskManager.pasteTasksAtRootLevel()
        taskManager.pendingPasteResult = nil
    }
    
    func handlePasteResult(_ result: TaskManager.PasteResult?) {
        guard let result = result else { return }
        
        switch result {
        case .success:
            // Nothing to show
            break
        case .noSelection:
            // Count tasks in clipboard for the confirmation message
            if let content = NSPasteboard.general.string(forType: .string),
               let entries = taskManager.parseClipboardContent(content) {
                pendingPasteTaskCount = entries.count
            } else {
                pendingPasteTaskCount = 0
            }
            showPasteRootConfirmation = true
        case .multipleSelection:
            pasteErrorMessage = "Select a single task to paste under, or clear selection to paste at root level."
            showPasteError = true
        case .emptyClipboard:
            pasteErrorMessage = "Clipboard is empty."
            showPasteError = true
        case .parseError:
            pasteErrorMessage = "Could not parse clipboard content."
            showPasteError = true
        }
    }
}

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
            .environmentObject(taskManager.selectionManager)
            .environmentObject(AppDelegate())
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

private struct TaskInputHeader: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var inputState: TaskInputState

    var isInputFocused: FocusState<Bool>.Binding
    var hasCompletedSetup: Bool

    private var palette: ThemePalette { taskManager.themePalette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                ExpandingTaskInput(
                    text: $inputState.text,
                    placeholder: "Type task or path /task/subtask",
                    onCommit: { taskManager.addTaskFromPath(); isInputFocused.wrappedValue = true },
                    onTextChange: { newText in taskManager.updateAutocompleteSuggestions(for: newText) },
                    onTab: { if inputState.hasSuggestions { taskManager.applySelectedSuggestion(); isInputFocused.wrappedValue = true }},
                    onShiftTab: {
                        // Shift+Tab: Toggle focus from input to task list
                        let visibleTasks = taskManager.snapshotVisibleTasks()
                        if let firstTask = visibleTasks.first {
                            taskManager.replaceSelection(with: firstTask.id)
                        }
                        isInputFocused.wrappedValue = false
                        taskManager.setTaskInputFocused(false)
                    },
                    onArrowDown: {
                        guard inputState.hasSuggestions else { return false }
                        taskManager.selectNextSuggestion()
                        return true
                    },
                    onArrowUp: {
                        guard inputState.hasSuggestions else { return false }
                        taskManager.selectPreviousSuggestion()
                        return true
                    },
                    fieldTextColor: palette.primaryText,
                    placeholderTextColor: palette.secondaryText
                )
                .focused(isInputFocused)
                .disabled(!hasCompletedSetup)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(palette.controlBackgroundColor)
                .cornerRadius(10)
                
                // Button wrapped with matching vertical padding to align with input's first line
                Button(action: { taskManager.addTaskFromPath(); isInputFocused.wrappedValue = true }) {
                    Image(systemName: "plus.circle.fill")
                        .taskrFont(.title2)
                        .foregroundColor(palette.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .padding(.vertical, 8) // Match the input field's vertical padding
                .padding(.trailing, -4) // Pull closer to the edge
            }
            .padding(.bottom, 8)

            HStack {
                Spacer()
                Button("Clear Completed") { taskManager.clearCompletedTasks() }
                    .focusable(false)
                    .padding(.top, 4)
                    .foregroundColor(palette.primaryTextColor)
            }

            if !inputState.suggestions.isEmpty {
                ScrollViewReader { proxy in
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
                                        isInputFocused.wrappedValue = true
                                    }
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                    .background(palette.controlBackgroundColor)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.dividerColor.opacity(0.7), lineWidth: 1))
                    .padding(.top, 2)
                    .onChange(of: inputState.selectedSuggestionIndex) { _, newIndex in
                        guard let index = newIndex else { return }
                        proxy.scrollTo(index)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                .animation(
                    taskManager.animationManager.effectiveSuggestionBoxAnimationEnabled
                        ? .easeOut(duration: 0.15)
                        : .none,
                    value: inputState.suggestions.isEmpty
                )
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    taskManager.registerUserInteractionTap()
                }
        )
    }
}

private struct SelectionScrollCoordinator: View {
    let proxy: ScrollViewProxy

    @EnvironmentObject var selectionManager: SelectionManager

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: selectionManager.selectionCursorID) { _, newCursorID in
                guard let cursorID = newCursorID else { return }
                proxy.scrollTo(cursorID)
            }
            .onChange(of: selectionManager.scrollToTaskRequest?.counter) { _, _ in
                guard let request = selectionManager.scrollToTaskRequest else { return }
                proxy.scrollTo(request.id)
            }
    }
}

private struct FlatTaskRowView: View {
    @Bindable var task: Task
    var depth: Int
    @ObservedObject var selectionState: TaskSelectionState
    var releaseInputFocus: (() -> Void)?

    @EnvironmentObject var taskManager: TaskManager

    var body: some View {
        TaskRowContentView(
            task: task,
            mode: .live,
            selectionState: selectionState,
            releaseInputFocus: releaseInputFocus
        )
            .padding(.leading, CGFloat(depth) * 20)
    }
}


private struct LiveScrollObserver: NSViewRepresentable {
    @Binding var isLiveScrolling: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.bind(to: view, isLiveScrolling: $isLiveScrolling)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.bind(to: nsView, isLiveScrolling: $isLiveScrolling)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private var startObserver: NSObjectProtocol?
        private var endObserver: NSObjectProtocol?
        private var liveScrollBinding: Binding<Bool>?

        func bind(to view: NSView, isLiveScrolling: Binding<Bool>) {
            guard let scrollView = view.enclosingScrollView else { return }
            if self.scrollView === scrollView {
                liveScrollBinding = isLiveScrolling
                return
            }
            teardown()
            self.scrollView = scrollView
            self.liveScrollBinding = isLiveScrolling

            let center = NotificationCenter.default
            startObserver = center.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.liveScrollBinding?.wrappedValue = true
            }
            endObserver = center.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.liveScrollBinding?.wrappedValue = false
            }
        }

        func teardown() {
            let center = NotificationCenter.default
            if let startObserver {
                center.removeObserver(startObserver)
            }
            if let endObserver {
                center.removeObserver(endObserver)
            }
            startObserver = nil
            endObserver = nil
            scrollView = nil
            liveScrollBinding = nil
        }
    }
}

// MARK: - Keyboard Handling
extension TaskView {
    private func installKeyboardMonitorIfNeeded() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.type == .keyUp {
                handleKeyUpEvent(event)
                return event
            }
            guard handleKeyDownEvent(event) else { return event }
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        isMKeyPressed = false
    }

    private func handleKeyUpEvent(_ event: NSEvent) {
        // Track M key release (keyCode 46 is 'm')
        if event.keyCode == 46 {
            isMKeyPressed = false
        }
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard shouldHandleKeyEvent(event) else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let effectiveFlags = flags.subtracting([.numericPad, .function])
        let shiftOnly = effectiveFlags == [.shift]
        let commandOnly = effectiveFlags == [.command]
        let noModifiers = effectiveFlags.isEmpty

        if commandOnly {
            switch event.keyCode {
            case 36, 76: // Return and Enter
                taskManager.toggleSelectedTasksCompletion()
                return true
            case 51, 117: // Delete and Forward Delete
                taskManager.deleteSelectedTasks()
                return true
            default:
                break
            }
            if let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "a":
                    taskManager.selectAllVisibleTasks()
                    return true
                case "d":
                    taskManager.duplicateSelectedTasks()
                    return true
                case "l":
                    taskManager.toggleLockForSelectedTasks()
                    return true
                case "v":
                    taskManager.triggerPaste()
                    return true
                case "p":
                    appDelegate.isWindowPinned.toggle()
                    return true
                default:
                    break
                }
            }
        }

        switch event.keyCode {
        case 46: // M key
            guard noModifiers else { return false }
            isMKeyPressed = true
            // Consume the event when tasks are selected to prevent system beep
            return !taskManager.selectedTaskIDs.isEmpty
        case 125: // Down arrow
            if noModifiers && isMKeyPressed {
                // M + Down Arrow = Move selected tasks down
                taskManager.moveSelectedTasksDown()
                return true
            }
            guard noModifiers || shiftOnly else { return false }
            taskManager.stepSelection(.down, extend: shiftOnly)
            return true
        case 126: // Up arrow
            if noModifiers && isMKeyPressed {
                // M + Up Arrow = Move selected tasks up
                taskManager.moveSelectedTasksUp()
                return true
            }
            guard noModifiers || shiftOnly else { return false }
            taskManager.stepSelection(.up, extend: shiftOnly)
            return true
        case 123: // Left arrow
            guard noModifiers else { return false }
            return updateSelectedParentExpansion(expanded: false)
        case 124: // Right arrow
            guard noModifiers else { return false }
            return updateSelectedParentExpansion(expanded: true)
        case 36, 76: // Return and Enter
            guard noModifiers || shiftOnly else { return false }
            let selectedIDs = taskManager.selectedTaskIDs
            guard selectedIDs.count == 1, let targetID = selectedIDs.first else { return false }
            if shiftOnly {
                guard let targetTask = taskManager.task(withID: targetID),
                      let newTask = taskManager.addSubtask(to: targetTask) else { return false }
                taskManager.replaceSelection(with: newTask.id)
                taskManager.requestInlineEdit(for: newTask.id)
                return true
            }
            taskManager.requestInlineEdit(for: targetID)
            return true
        case 53: // Escape
            guard noModifiers else { return false }
            if !taskManager.selectedTaskIDs.isEmpty {
                taskManager.clearSelection()
                return true
            }
            return false
        case 48: // Tab
            guard shiftOnly else { return false }
            // Shift+Tab: Toggle focus from task list to input field
            isInputFocused = true
            taskManager.setTaskInputFocused(true)
            return true
        default:
            break
        }

        return false
    }

    private func updateSelectedParentExpansion(expanded: Bool) -> Bool {
        let selectedParents = taskManager.selectedTaskIDs.filter {
            taskManager.hasCachedChildren(forParentID: $0, kind: .live)
        }
        guard !selectedParents.isEmpty else { return false }

        taskManager.setExpandedState(for: selectedParents, expanded: expanded, kind: .live)
        return true
    }

    private func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        guard window.isKeyWindow else { return false }

        if taskManager.isTaskInputFocused {
            return false
        }

        if let responder = window.firstResponder, responder is NSTextView {
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
