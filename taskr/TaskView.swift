// taskr/taskr/TaskView.swift
import SwiftUI
import SwiftData
import AppKit

struct TaskView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var selectionManager: SelectionManager
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
    @State private var isLiveScrolling: Bool = false

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
                                releaseInputFocus: releaseTaskInputFocus
                            )
                                .padding(.top, 4)
                                .padding(.bottom, 4)
                                .id(entry.task.id)
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
            .background(
                ScrollViewConfigurator { scrollView in
                    scrollView.scrollerStyle = .legacy
                    scrollView.hasHorizontalScroller = false
                    scrollView.hasVerticalScroller = true
                    scrollView.automaticallyAdjustsContentInsets = false
                    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
                    scrollView.verticalScrollElasticity = .automatic
#if DEBUG
                    if scrollView.contentView.postsBoundsChangedNotifications == false {
                        scrollView.contentView.postsBoundsChangedNotifications = true
                        NotificationCenter.default.addObserver(
                            forName: NSView.boundsDidChangeNotification,
                            object: scrollView.contentView,
                            queue: .main
                        ) { [weak scrollView] _ in
                            guard let scrollView else { return }
                            let visibleWidth = scrollView.contentView.documentVisibleRect.width
                            let scrollerWidth = scrollView.verticalScroller?.frame.width ?? 0
                            let knobProportion = scrollView.verticalScroller?.knobProportion ?? 0
                            print("Scroll debug -> visibleWidth: \(visibleWidth), scrollerWidth: \(scrollerWidth), knobProportion: \(knobProportion)")
                        }
                }
#endif
                }
            )
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
            HStack {
                CustomTextField(
                    text: $inputState.text,
                    placeholder: "Type task or path /task/subtask",
                    onCommit: { taskManager.addTaskFromPath(); isInputFocused.wrappedValue = true },
                    onTextChange: { newText in taskManager.updateAutocompleteSuggestions(for: newText) },
                    onTab: { if inputState.hasSuggestions { taskManager.applySelectedSuggestion(); isInputFocused.wrappedValue = true }},
                    onShiftTab: { if inputState.hasSuggestions { taskManager.selectPreviousSuggestion() }},
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
                Button(action: { taskManager.addTaskFromPath(); isInputFocused.wrappedValue = true }) {
                    Image(systemName: "plus.circle.fill")
                        .taskrFont(.title2)
                        .foregroundColor(palette.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 4)
            }
            .padding(.bottom, 8)

            HStack {
                Spacer()
                Button("Clear Completed") { taskManager.clearCompletedTasks() }
                    .padding(.top, 4)
                    .foregroundColor(palette.primaryTextColor)
            }

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
                                    isInputFocused.wrappedValue = true
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

private struct FlatTaskRowView: View {
    @Bindable var task: Task
    var depth: Int
    var releaseInputFocus: (() -> Void)?

    @EnvironmentObject var taskManager: TaskManager

    var body: some View {
        TaskRowContentView(task: task, mode: .live, releaseInputFocus: releaseInputFocus)
            .padding(.leading, CGFloat(depth) * 20)
    }
}

private struct ScrollViewConfigurator: NSViewRepresentable {
    var configure: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            apply(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView)
        }
    }

    private func apply(to view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        configure(scrollView)
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
        case 36, 76: // Return and Enter
            guard !commandPressed else { return false }
            let selectedIDs = taskManager.selectedTaskIDs
            guard selectedIDs.count == 1, let targetID = selectedIDs.first else { return false }
            taskManager.requestInlineEdit(for: targetID)
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
