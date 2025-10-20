import XCTest
import SwiftData
import AppKit
@testable import taskr

@MainActor
final class TaskManagerSelectionTests: XCTestCase {
    var container: ModelContainer!
    var manager: TaskManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Task.self, TaskTemplate.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        manager = TaskManager(modelContext: container.mainContext)
    }

    override func tearDownWithError() throws {
        manager = nil
        container = nil
        try super.tearDownWithError()
    }

    func testRangeSelectionFollowsVisibleOrdering() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let taskBeta = try XCTUnwrap(seeded["Task Beta"])
        let subtaskAlpha = try XCTUnwrap(seeded["Subtask Alpha"])

        manager.replaceSelection(with: taskAlpha.id)
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id])

        manager.extendSelection(to: subtaskAlpha.id)
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, subtaskAlpha.id])

        manager.stepSelection(.down, extend: false)
        XCTAssertEqual(manager.selectedTaskIDs, [taskBeta.id])

        manager.stepSelection(.up, extend: false)
        XCTAssertEqual(manager.selectedTaskIDs, [subtaskAlpha.id])

        manager.stepSelection(.up, extend: true)
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, subtaskAlpha.id])

        manager.toggleSelection(for: taskBeta.id)
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, subtaskAlpha.id, taskBeta.id])

        manager.setTaskExpanded(taskAlpha.id, expanded: false)
        manager.selectAllVisibleTasks()
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, taskBeta.id])
    }

    func testToggleSelectionMaintainsVisibleOrderAndResetsAnchor() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let subtaskBeta = try XCTUnwrap(seeded["Subtask Beta"])

        manager.toggleSelection(for: subtaskBeta.id)
        XCTAssertEqual(manager.selectedTaskIDs, [subtaskBeta.id])
        XCTAssertEqual(manager.selectionAnchorID, subtaskBeta.id)
        XCTAssertEqual(manager.selectionCursorID, subtaskBeta.id)

        manager.toggleSelection(for: taskAlpha.id)
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, subtaskBeta.id])
        XCTAssertEqual(manager.selectionAnchorID, subtaskBeta.id)
        XCTAssertEqual(manager.selectionCursorID, taskAlpha.id)

        manager.toggleSelection(for: subtaskBeta.id)
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id])
        XCTAssertEqual(manager.selectionAnchorID, taskAlpha.id)
        XCTAssertEqual(manager.selectionCursorID, taskAlpha.id)

        manager.clearSelection()
        XCTAssertTrue(manager.selectedTaskIDs.isEmpty)
        XCTAssertNil(manager.selectionAnchorID)
        XCTAssertNil(manager.selectionCursorID)
    }

    func testSelectAllVisibleTasksHonorsExpansionState() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let taskBeta = try XCTUnwrap(seeded["Task Beta"])
        let subtaskAlpha = try XCTUnwrap(seeded["Subtask Alpha"])
        let subtaskBeta = try XCTUnwrap(seeded["Subtask Beta"])

        manager.selectAllVisibleTasks()
        XCTAssertEqual(
            manager.selectedTaskIDs,
            [taskAlpha.id, subtaskAlpha.id, subtaskBeta.id, taskBeta.id]
        )
        XCTAssertEqual(manager.selectionAnchorID, taskAlpha.id)
        XCTAssertEqual(manager.selectionCursorID, taskBeta.id)

        manager.setTaskExpanded(taskAlpha.id, expanded: false)
        manager.selectAllVisibleTasks()
        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, taskBeta.id])
        XCTAssertEqual(manager.selectionAnchorID, taskAlpha.id)
        XCTAssertEqual(manager.selectionCursorID, taskBeta.id)
    }

    func testDeleteSelectedTasksRemovesAllTargets() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let subtaskAlpha = try XCTUnwrap(seeded["Subtask Alpha"])
        let taskBeta = try XCTUnwrap(seeded["Task Beta"])

        manager.replaceSelection(with: taskAlpha.id)
        manager.toggleSelection(for: subtaskAlpha.id)
        manager.toggleSelection(for: taskBeta.id)

        manager.deleteSelectedTasks()

        let remaining = try container.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        )
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(manager.selectedTaskIDs.isEmpty)
    }

    func testDuplicateSelectedTasksCreatesCopiesAndSelectsThem() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let taskBeta = try XCTUnwrap(seeded["Task Beta"])

        manager.replaceSelection(with: taskAlpha.id)
        manager.toggleSelection(for: taskBeta.id)

        manager.duplicateSelectedTasks()

        let roots = try container.mainContext.fetch(
            FetchDescriptor<Task>(
                predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
                sortBy: [SortDescriptor(\Task.displayOrder)]
            )
        )
        XCTAssertEqual(roots.map(\.name), [
            "Task Alpha",
            "Task Alpha (copy)",
            "Task Beta",
            "Task Beta (copy)"
        ])
        let selectedNames = manager.selectedTaskIDs.compactMap { manager.task(withID: $0)?.name }
        XCTAssertEqual(selectedNames, ["Task Alpha (copy)", "Task Beta (copy)"])
    }

    func testMoveSelectedTasksUpAsBlock() throws {
        let tasks = try seedRootTasks(names: ["Root A", "Root B", "Root C"])
        let rootA = tasks[0]
        let rootB = tasks[1]
        let rootC = tasks[2]

        manager.replaceSelection(with: rootB.id)
        manager.toggleSelection(for: rootC.id)

        XCTAssertTrue(manager.canMoveSelectedTasksUp())
        manager.moveSelectedTasksUp()

        let roots = try container.mainContext.fetch(
            FetchDescriptor<Task>(
                predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
                sortBy: [SortDescriptor(\Task.displayOrder)]
            )
        )
        XCTAssertEqual(roots.map(\.name), ["Root B", "Root C", "Root A"])
        XCTAssertEqual(manager.selectedTaskIDs, [rootB.id, rootC.id])
    }

    func testMoveSelectedTasksDownAsBlock() throws {
        let tasks = try seedRootTasks(names: ["Top", "Mid A", "Mid B", "Bottom"])
        let midA = tasks[1]
        let midB = tasks[2]

        manager.replaceSelection(with: midA.id)
        manager.toggleSelection(for: midB.id)

        XCTAssertTrue(manager.canMoveSelectedTasksDown())
        manager.moveSelectedTasksDown()

        let roots = try container.mainContext.fetch(
            FetchDescriptor<Task>(
                predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
                sortBy: [SortDescriptor(\Task.displayOrder)]
            )
        )
        XCTAssertEqual(roots.map(\.name), ["Top", "Bottom", "Mid A", "Mid B"])
        XCTAssertEqual(manager.selectedTaskIDs, [midA.id, midB.id])
    }

    func testMoveSelectedTasksRequiresContiguousSiblings() throws {
        let tasks = try seedRootTasks(names: ["One", "Two", "Three"])
        let one = tasks[0]
        let three = tasks[2]

        manager.replaceSelection(with: one.id)
        manager.toggleSelection(for: three.id)

        XCTAssertFalse(manager.canMoveSelectedTasksUp())
        manager.moveSelectedTasksUp()

        let roots = try container.mainContext.fetch(
            FetchDescriptor<Task>(
                predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil },
                sortBy: [SortDescriptor(\Task.displayOrder)]
            )
        )
        XCTAssertEqual(roots.map(\.name), ["One", "Two", "Three"])
    }

    func testShiftDragSelectionExpandsRange() throws {
        let tasks = try seedRootTasks(names: ["One", "Two", "Three", "Four"])
        let one = tasks[0]
        let three = tasks[2]

        manager.replaceSelection(with: one.id)
        manager.beginShiftSelection(at: one.id)
        manager.updateShiftSelection(to: three.id)
        manager.endShiftSelection()

        XCTAssertEqual(manager.selectedTaskIDs, [one.id, tasks[1].id, three.id])
    }

    func testShiftDragFromUnselectedStartKeepsOriginalAnchor() throws {
        let tasks = try seedRootTasks(names: ["One", "Two", "Three"])
        let one = tasks[0]
        let three = tasks[2]

        manager.replaceSelection(with: one.id)
        manager.beginShiftSelection(at: three.id)
        manager.endShiftSelection()

        XCTAssertEqual(manager.selectedTaskIDs, [one.id, tasks[1].id, three.id])
        XCTAssertEqual(manager.selectionAnchorID, one.id)
    }

    func testShiftDragSelectionUsesExistingAnchor() throws {
        let tasks = try seedRootTasks(names: ["Alpha", "Beta", "Gamma", "Delta"])
        let beta = tasks[1]
        let delta = tasks[3]

        manager.replaceSelection(with: beta.id)
        manager.beginShiftSelection(at: beta.id)
        manager.updateShiftSelection(to: delta.id)
        manager.endShiftSelection()

        XCTAssertEqual(manager.selectedTaskIDs, [beta.id, tasks[2].id, delta.id])
    }

    func testCopySelectedTasksFormatsExpectedOutput() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let taskBeta = try XCTUnwrap(seeded["Task Beta"])
        let subtaskAlpha = try XCTUnwrap(seeded["Subtask Alpha"])

        subtaskAlpha.isCompleted = true
        taskBeta.isCompleted = true
        try container.mainContext.save()

        NSPasteboard.general.clearContents()

        manager.replaceSelection(with: taskAlpha.id)
        manager.extendSelection(to: subtaskAlpha.id)
        manager.toggleSelection(for: taskBeta.id)

        manager.copySelectedTasksToPasteboard()

        let expected = """
        () - Task Alpha
        \t(x) - Subtask Alpha
        (x) - Task Beta
        """
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
    }

    func testCopySubtaskWithoutParentRemovesIndentation() throws {
        let seeded = try seedSampleHierarchy()
        let subtaskAlpha = try XCTUnwrap(seeded["Subtask Alpha"])

        NSPasteboard.general.clearContents()

        manager.replaceSelection(with: subtaskAlpha.id)
        manager.copySelectedTasksToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "() - Subtask Alpha")
    }

    func testCollapsingParentPrunesDescendantSelection() throws {
        let seeded = try seedSampleHierarchy()
        let taskAlpha = try XCTUnwrap(seeded["Task Alpha"])
        let taskBeta = try XCTUnwrap(seeded["Task Beta"])
        let subtaskAlpha = try XCTUnwrap(seeded["Subtask Alpha"])
        let subtaskBeta = try XCTUnwrap(seeded["Subtask Beta"])

        NSPasteboard.general.clearContents()

        manager.replaceSelection(with: subtaskAlpha.id)
        manager.toggleSelection(for: subtaskBeta.id)
        manager.toggleSelection(for: taskAlpha.id)

        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, subtaskAlpha.id, subtaskBeta.id])

        manager.setTaskExpanded(taskAlpha.id, expanded: false)

        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id])

        manager.toggleSelection(for: taskBeta.id)

        XCTAssertEqual(manager.selectedTaskIDs, [taskAlpha.id, taskBeta.id])

        manager.copySelectedTasksToPasteboard()
        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        let expected = """
        () - Task Alpha
        () - Task Beta
        """
        XCTAssertEqual(copied, expected)
    }

    @discardableResult
    private func seedSampleHierarchy() throws -> [String: Task] {
        let taskAlpha = Task(name: "Task Alpha", displayOrder: 0, isTemplateComponent: false)
        container.mainContext.insert(taskAlpha)

        let subtaskAlpha = Task(
            name: "Subtask Alpha",
            displayOrder: 0,
            isTemplateComponent: false,
            parentTask: taskAlpha
        )
        container.mainContext.insert(subtaskAlpha)
        taskAlpha.subtasks?.append(subtaskAlpha)

        let subtaskBeta = Task(
            name: "Subtask Beta",
            displayOrder: 1,
            isTemplateComponent: false,
            parentTask: taskAlpha
        )
        container.mainContext.insert(subtaskBeta)
        taskAlpha.subtasks?.append(subtaskBeta)

        let taskBeta = Task(name: "Task Beta", displayOrder: 1, isTemplateComponent: false)
        container.mainContext.insert(taskBeta)

        try container.mainContext.save()
        return [
            "Task Alpha": taskAlpha,
            "Subtask Alpha": subtaskAlpha,
            "Task Beta": taskBeta,
            "Subtask Beta": subtaskBeta
        ]
    }

    @discardableResult
    private func seedRootTasks(names: [String]) throws -> [Task] {
        var tasks: [Task] = []
        for (index, name) in names.enumerated() {
            let task = Task(
                name: name,
                displayOrder: index,
                isTemplateComponent: false
            )
            container.mainContext.insert(task)
            tasks.append(task)
        }
        try container.mainContext.save()
        return tasks
    }
}
