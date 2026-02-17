// taskr/taskr/TemplateView.swift
import SwiftUI
import SwiftData
import AppKit

struct TemplateView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var selectionManager: SelectionManager
    @Environment(\.modelContext) private var modelContext
    var isActive: Bool = true

    @Query(sort: [SortDescriptor(\TaskTemplate.name)]) private var templates: [TaskTemplate]
    @Query(
        filter: #Predicate<Task> { $0.isTemplateComponent },
        sort: [SortDescriptor(\Task.displayOrder, order: .forward)]
    ) private var templateTasks: [Task]
    @State private var editingTemplateID: UUID? = nil
    @State private var editingTemplateName: String = ""
    
    // Selection system state
    @State private var isWindowKey: Bool = false
    @State private var isLiveScrolling: Bool = false
    @State private var hostingWindow: NSWindow?
    @State private var windowObserverTokens: [NSObjectProtocol] = []
    
    // Keyboard handling state
    @State private var keyboardMonitor: Any?
    @State private var isMKeyPressed: Bool = false
    
    private var palette: ThemePalette { taskManager.themePalette }
    private var backgroundColor: Color {
        taskManager.frostedBackgroundEnabled ? .clear : palette.backgroundColor
    }
    private var templateChildrenByParentID: [UUID: [Task]] {
        var grouped: [UUID: [Task]] = [:]
        for task in templateTasks {
            guard let parentID = task.parentTask?.id else { continue }
            grouped[parentID, default: []].append(task)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.displayOrder < $1.displayOrder }
        }
        return grouped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Main VStack

            // --- Add Template Section ---
            HStack(alignment: .top, spacing: 8) {
                ExpandingTaskInput(
                    text: $taskManager.newTemplateName,
                    placeholder: "New Template Name",
                    onCommit: { taskManager.addTemplate() },
                    onTextChange: { _ in },
                    onTab: { },
                    onShiftTab: { },
                    onArrowDown: { false },
                    onArrowUp: { false },
                    fieldTextColor: palette.primaryText,
                    placeholderTextColor: palette.secondaryText
                )
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(palette.controlBackgroundColor)
                .cornerRadius(10)
                Button(action: { taskManager.addTemplate() }) {
                    Image(systemName: "plus.circle.fill")
                        .taskrFont(.title2)
                        .foregroundColor(palette.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .help("Create a new empty template")
                .padding(.vertical, 8)
                .padding(.trailing, -4)
            }
            .padding([.horizontal, .top]).padding(.bottom, 8) // Padding for this section
            // --- End Add Template Section ---

            // --- Add Divider Here ---
            Divider().background(palette.dividerColor)
            // --- End Divider ---

            // --- Template List Section ---
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if templates.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "square.on.square")
                                    .font(.system(size: 40))
                                    .foregroundColor(palette.secondaryTextColor.opacity(0.5))
                                Text("No templates yet")
                                    .taskrFont(.headline)
                                    .foregroundColor(palette.primaryTextColor)
                                Text("Templates let you create reusable task lists.\nAdd one above to get started.")
                                    .taskrFont(.subheadline)
                                    .foregroundColor(palette.secondaryTextColor)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            let childrenByParent = templateChildrenByParentID
                            ForEach(templates, id: \.persistentModelID) { template in
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        // Expand/collapse chevron based on the template's container task ID
                                        let containerID = template.taskStructure?.id
                                        let isExpanded = containerID.map { taskManager.isTaskExpanded($0) } ?? false
                                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                            .taskrFont(.caption)
                                            .foregroundColor(palette.secondaryTextColor)
                                            .padding(5)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                if let id = containerID { taskManager.toggleTaskExpansion(id) }
                                            }

                                        if editingTemplateID == template.id {
                                            CustomTextField(
                                                text: $editingTemplateName,
                                                placeholder: "",
                                                onCommit: { commitTemplateNameEdit(template) }
                                            )
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 6)
                                            .background(palette.controlBackgroundColor)
                                            .cornerRadius(8)
                                            .frame(maxWidth: 220)
                                            .onSubmit { commitTemplateNameEdit(template) }
                                            .onDisappear { if editingTemplateID == template.id { commitTemplateNameEdit(template) } }
                                        } else {
                                            Text(template.name)
                                                .taskrFont(.headline)
                                                .onTapGesture(count: 2) {
                                                    editingTemplateID = template.id
                                                    editingTemplateName = template.name
                                                }
                                        }
                                        Spacer()
                                        // Apply template to live tasks
                                        Button(action: { taskManager.applyTemplate(template) }) {
                                            Label("Apply", systemImage: "tray.and.arrow.down")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help("Instantiate these tasks in the main list")
                                        // Add a root-level task under this template
                                        Button { taskManager.addTemplateRootTask(to: template) } label: {
                                            Label("Add Item", systemImage: "plus")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help("Add a new root task to this template")
                                        // Delete template
                                        Button { deleteTemplate(template) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .foregroundColor(.red)
                                        .help("Delete this template")
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .contextMenu {
                                        Button {
                                            taskManager.duplicateTemplate(template)
                                        } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }
                                    }

                                    if let container = template.taskStructure,
                                       taskManager.isTaskExpanded(container.id) {
                                        // Render root tasks from pre-grouped children for fewer repeated scans/sorts.
                                        let subs = childrenByParent[container.id] ?? []
                                        ForEach(subs, id: \.persistentModelID) { t in
                                            TaskRowView(task: t, mode: .template)
                                                .padding(.leading, 20)
                                                .padding(.vertical, 4)
                                                .id(t.id)
                                            if t.persistentModelID != subs.last?.persistentModelID {
                                                Divider().background(palette.dividerColor).padding(.leading, 20)
                                            }
                                        }
                                    }
                                }
                                Divider().background(palette.dividerColor)
                            }
                        }
                    }
                    .allowsHitTesting(!isLiveScrolling)
                }
                .background(LiveScrollObserver(isLiveScrolling: $isLiveScrolling))
                .onChange(of: selectionManager.selectionCursorID) { _, newCursorID in
                    guard let cursorID = newCursorID else { return }
                    proxy.scrollTo(cursorID)
                }
            }
            // --- End Template List Section ---
        }
        .foregroundColor(palette.primaryTextColor)
        .background(backgroundColor)
        .environment(\.isWindowKey, isWindowKey)
        .environment(\.isLiveScrolling, isLiveScrolling)
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    DispatchQueue.main.async {
                        if !taskManager.consumeInteractionCapture(),
                           !selectionManager.selectedTaskIDs.isEmpty {
                            selectionManager.clearSelection()
                        }
                    }
                }
        )
        .background {
            if isActive {
                WindowAccessor { window in
                    DispatchQueue.main.async {
                        handleWindowChange(window)
                    }
                }
            }
        }
        .onAppear {
            if isActive {
                installKeyboardMonitorIfNeeded()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                installKeyboardMonitorIfNeeded()
                syncWindowFocusState()
            } else {
                removeKeyboardMonitor()
                removeWindowObservers(resetFocus: false)
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
            removeWindowObservers()
        }
    }

    private func commitTemplateNameEdit(_ template: TaskTemplate) {
        let trimmed = editingTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && template.name != trimmed {
            template.name = trimmed
            try? modelContext.save()
        }
        editingTemplateID = nil
        editingTemplateName = ""
    }

    private func deleteTemplate(_ template: TaskTemplate) {
        modelContext.delete(template)
        try? modelContext.save()
        taskManager.pruneCollapsedState()
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
            isWindowKey = false
            return
        }

        isWindowKey = window.isKeyWindow

        let become = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in
                isWindowKey = true
            }
        }
        let resign = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in
                isWindowKey = false
            }
        }
        windowObserverTokens = [become, resign]
    }

    @MainActor
    private func syncWindowFocusState() {
        if let hostingWindow {
            isWindowKey = hostingWindow.isKeyWindow
        } else {
            isWindowKey = NSApp.isActive
        }
    }
    
    @MainActor
    private func removeWindowObservers(resetFocus: Bool = true) {
        let center = NotificationCenter.default
        for token in windowObserverTokens {
            center.removeObserver(token)
        }
        windowObserverTokens.removeAll()
        hostingWindow = nil
        if resetFocus {
            isWindowKey = false
        }
    }
}

// MARK: - Keyboard Handling
private extension TemplateView {
    func installKeyboardMonitorIfNeeded() {
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

    func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        isMKeyPressed = false
    }

    func handleKeyUpEvent(_ event: NSEvent) {
        // Track M key release (keyCode 46 is 'm')
        if event.keyCode == 46 {
            isMKeyPressed = false
        }
    }

    func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard shouldHandleKeyEvent(event) else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let effectiveFlags = flags.subtracting([.numericPad, .function])
        let shiftOnly = effectiveFlags == [.shift]
        let commandOnly = effectiveFlags == [.command]
        let noModifiers = effectiveFlags.isEmpty

        if commandOnly {
            switch event.keyCode {
            case 51, 117: // Delete and Forward Delete
                deleteSelectedTemplateTasks()
                return true
            default:
                break
            }
            if let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "a":
                    selectAllVisibleTemplateTasks()
                    return true
                case "v":
                    pasteIntoSelectedTemplateTask()
                    return true
                case "d":
                    duplicateSelectedTemplateTasks()
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
            return !selectionManager.selectedTaskIDs.isEmpty
        case 125: // Down arrow
            if noModifiers && isMKeyPressed {
                // M + Down Arrow = Move selected template tasks down
                moveSelectedTemplateTasksDown()
                return true
            }
            guard noModifiers || shiftOnly else { return false }
            stepTemplateSelection(.down, extend: shiftOnly)
            return true
        case 126: // Up arrow
            if noModifiers && isMKeyPressed {
                // M + Up Arrow = Move selected template tasks up
                moveSelectedTemplateTasksUp()
                return true
            }
            guard noModifiers || shiftOnly else { return false }
            stepTemplateSelection(.up, extend: shiftOnly)
            return true
        case 123: // Left arrow
            guard noModifiers else { return false }
            return updateSelectedTemplateExpansion(expanded: false)
        case 124: // Right arrow
            guard noModifiers else { return false }
            return updateSelectedTemplateExpansion(expanded: true)
        case 36, 76: // Return and Enter
            guard noModifiers || shiftOnly else { return false }
            let selectedIDs = selectionManager.selectedTaskIDs
            guard selectedIDs.count == 1, let targetID = selectedIDs.first else { return false }
            if shiftOnly {
                // Add subtask to selected template task
                guard let targetTask = taskManager.task(withID: targetID) else { return false }
                taskManager.addTemplateSubtask(to: targetTask)
                return true
            }
            taskManager.requestInlineEdit(for: targetID)
            return true
        case 53: // Escape
            guard noModifiers else { return false }
            if !selectionManager.selectedTaskIDs.isEmpty {
                selectionManager.clearSelection()
                return true
            }
            return false
        default:
            break
        }

        return false
    }

    func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        guard let window = event.window else { return false }
        guard window.isKeyWindow else { return false }

        // Don't handle if editing template name or task name
        if editingTemplateID != nil {
            return false
        }

        if let responder = window.firstResponder, responder is NSTextView {
            return false
        }

        return true
    }
    
    // MARK: - Template-specific Selection Operations
    
    func stepTemplateSelection(_ direction: TaskManager.SelectionDirection, extend: Bool) {
        let visibleTasks = snapshotVisibleTemplateTasks()
        let visibleIDs = visibleTasks.map(\.id)
        guard !visibleIDs.isEmpty else { return }
        
        let currentCursor = selectionManager.selectionCursorID
        guard let cursorIndex = currentCursor.flatMap({ visibleIDs.firstIndex(of: $0) }) else {
            // No current selection, select first or last based on direction
            let targetID = direction == .down ? visibleIDs.first! : visibleIDs.last!
            selectionManager.replaceSelection(with: targetID)
            return
        }
        
        let nextIndex: Int
        switch direction {
        case .down:
            nextIndex = min(cursorIndex + 1, visibleIDs.count - 1)
        case .up:
            nextIndex = max(cursorIndex - 1, 0)
        }
        
        let targetID = visibleIDs[nextIndex]
        if extend {
            selectionManager.extendSelection(to: targetID, visibleTaskIDs: visibleIDs)
        } else {
            selectionManager.replaceSelection(with: targetID)
        }
    }
    
    func selectAllVisibleTemplateTasks() {
        let visibleIDs = snapshotVisibleTemplateTasks().map(\.id)
        guard !visibleIDs.isEmpty else { return }
        selectionManager.selectTasks(orderedIDs: visibleIDs, anchor: visibleIDs.first, cursor: visibleIDs.last)
    }
    
    func deleteSelectedTemplateTasks() {
        let selectedIDs = selectionManager.selectedTaskIDs
        guard !selectedIDs.isEmpty else { return }
        
        for id in selectedIDs {
            if let task = taskManager.task(withID: id), task.isTemplateComponent {
                taskManager.deleteTemplateTask(task)
            }
        }
        selectionManager.clearSelection()
    }
    
    func moveSelectedTemplateTasksUp() {
        let selectedIDs = selectionManager.selectedTaskIDs
        guard selectedIDs.count == 1, let taskID = selectedIDs.first,
              let task = taskManager.task(withID: taskID) else { return }
        taskManager.moveTemplateTaskUp(task)
    }
    
    func moveSelectedTemplateTasksDown() {
        let selectedIDs = selectionManager.selectedTaskIDs
        guard selectedIDs.count == 1, let taskID = selectedIDs.first,
              let task = taskManager.task(withID: taskID) else { return }
        taskManager.moveTemplateTaskDown(task)
    }
    
    func pasteIntoSelectedTemplateTask() {
        let selectedIDs = selectionManager.selectedTaskIDs
        
        // Get clipboard content
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return // Empty clipboard
        }
        
        // Parse clipboard content using TaskManager's parser
        guard let entries = taskManager.parseClipboardContent(content), !entries.isEmpty else {
            return // Parse error
        }
        
        // Determine parent task for pasting
        guard selectedIDs.count == 1,
              let parentID = selectedIDs.first,
              let parentTask = taskManager.task(withID: parentID),
              parentTask.isTemplateComponent else {
            // No selection or invalid - can't paste without a target in template mode
            return
        }
        
        // Create template tasks from parsed entries
        taskManager.createTemplateTasksFromParsed(entries: entries, under: parentTask)
    }
    
    func duplicateSelectedTemplateTasks() {
        let selectedIDs = selectionManager.selectedTaskIDs
        guard !selectedIDs.isEmpty else { return }
        
        for id in selectedIDs {
            if let task = taskManager.task(withID: id), task.isTemplateComponent {
                taskManager.duplicateTemplateTask(task)
            }
        }
    }
    
    func updateSelectedTemplateExpansion(expanded: Bool) -> Bool {
        let selectedParents = selectionManager.selectedTaskIDs.filter {
            taskManager.hasCachedChildren(forParentID: $0, kind: .template)
        }
        guard !selectedParents.isEmpty else { return false }
        
        taskManager.setExpandedState(for: selectedParents, expanded: expanded, kind: .template)
        
        // After collapse, the setExpandedState may prune child selections using live tasks.
        // Ensure the collapsed parents remain selected for template mode.
        if !expanded {
            // Re-apply selection to the parents we just collapsed
            let visibleTasks = snapshotVisibleTemplateTasks()
            let visibleIDs = visibleTasks.map(\.id)
            let stillVisible = selectedParents.filter { visibleIDs.contains($0) }
            if !stillVisible.isEmpty {
                selectionManager.selectTasks(orderedIDs: stillVisible, anchor: stillVisible.first, cursor: stillVisible.last)
            }
        }
        return true
    }
    
    func snapshotVisibleTemplateTasks() -> [Task] {
        let childrenByParent = templateChildrenByParentID
        var result: [Task] = []
        for template in templates {
            guard let container = template.taskStructure,
                  taskManager.isTaskExpanded(container.id) else { continue }
            let rootTasks = childrenByParent[container.id] ?? []
            for task in rootTasks {
                result.append(contentsOf: collectVisibleTasks(from: task, childrenByParent: childrenByParent))
            }
        }
        return result
    }
    
    func collectVisibleTasks(from task: Task, childrenByParent: [UUID: [Task]]) -> [Task] {
        var result = [task]
        if taskManager.isTaskExpanded(task.id) {
            let children = childrenByParent[task.id] ?? []
            for child in children {
                result.append(contentsOf: collectVisibleTasks(from: child, childrenByParent: childrenByParent))
            }
        }
        return result
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

// Preview Provider remains the same
struct TemplateView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, TaskTag.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)

        let previewTemplateStructure = Task(name: "TEMPLATE_INTERNAL_ROOT_CONTAINER", isTemplateComponent: true)
        container.mainContext.insert(previewTemplateStructure)
        let previewTemplateTask = Task(name: "Task from Template Preview", isTemplateComponent: true, parentTask: previewTemplateStructure)
        container.mainContext.insert(previewTemplateTask)
        previewTemplateStructure.subtasks = [previewTemplateTask]

        let template1 = TaskTemplate(name: "Preview Template A", taskStructure: previewTemplateStructure)
        container.mainContext.insert(template1)
        let template2 = TaskTemplate(name: "Preview Template B")
        container.mainContext.insert(template2)

        return TemplateView()
            .modelContainer(container)
            .environmentObject(taskManager)
            .environmentObject(taskManager.selectionManager)
            .frame(width: 380, height: 400)
            .background(taskManager.themePalette.backgroundColor)
    }
}
