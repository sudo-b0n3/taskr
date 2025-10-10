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

        let taskBeta = Task(name: "Task Beta", displayOrder: 1, isTemplateComponent: false)
        container.mainContext.insert(taskBeta)

        try container.mainContext.save()
        return [
            "Task Alpha": taskAlpha,
            "Subtask Alpha": subtaskAlpha,
            "Task Beta": taskBeta
        ]
    }
}
