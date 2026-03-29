import XCTest
import SwiftData
@testable import taskr

@MainActor
final class TaskManagerMovePerformanceTests: XCTestCase {
    var container: ModelContainer!
    var manager: TaskManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Task.self, TaskTemplate.self, TaskTag.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        manager = TaskManager(modelContext: container.mainContext)
    }

    override func tearDownWithError() throws {
        manager = nil
        container = nil
        try super.tearDownWithError()
    }

    func testSingleTaskMoveUpUsesSingleSaveAndUpdatesOnlyAffectedBucket() throws {
        let root = makeTask("Root", order: 0)
        let a = makeTask("A", order: 0, parent: root)
        let b = makeTask("B", order: 1, parent: root)
        let otherRoot = makeTask("Other Root", order: 1)
        let otherChild = makeTask("Other Child", order: 0, parent: otherRoot)
        try saveTasks([root, a, b, otherRoot, otherChild])

        _ = try manager.siblingTasks(for: root, kind: .live)
        _ = try manager.siblingTasks(for: otherRoot, kind: .live)
        _ = manager.snapshotVisibleTaskIDs()

        let baselineSaves = manager.saveInvocationCount
        manager.moveTaskUp(b)

        XCTAssertEqual(manager.saveInvocationCount - baselineSaves, 1)
        XCTAssertEqual(try liveSiblingNames(parent: root), ["B", "A"])
        XCTAssertEqual(try liveSiblingNames(parent: otherRoot), ["Other Child"])
        XCTAssertNil(manager.visibleLiveTaskIDsCache)
        XCTAssertEqual(manager.childTaskCache[.live]?[otherRoot.id]?.map(\.id), [otherChild.id])
    }

    func testMoveTaskAcrossParentsReusesTargetedCaches() throws {
        let sourceRoot = makeTask("Source", order: 0)
        let moveMe = makeTask("Move Me", order: 0, parent: sourceRoot)
        let sourceSibling = makeTask("Stay Put", order: 1, parent: sourceRoot)
        let targetRoot = makeTask("Target", order: 1)
        let targetA = makeTask("Target A", order: 0, parent: targetRoot)
        let targetB = makeTask("Target B", order: 1, parent: targetRoot)
        try saveTasks([sourceRoot, moveMe, sourceSibling, targetRoot, targetA, targetB])

        _ = try manager.siblingTasks(for: sourceRoot, kind: .live)
        _ = try manager.siblingTasks(for: targetRoot, kind: .live)

        let baselineSaves = manager.saveInvocationCount
        manager.moveTask(
            draggedTaskID: moveMe.id,
            targetTaskID: targetA.id,
            parentOfList: targetRoot,
            moveBeforeTarget: false
        )

        XCTAssertEqual(manager.saveInvocationCount - baselineSaves, 1)
        XCTAssertEqual(try liveSiblingNames(parent: sourceRoot), ["Stay Put"])
        XCTAssertEqual(try liveSiblingNames(parent: targetRoot), ["Target A", "Move Me", "Target B"])
        XCTAssertNotNil(manager.childTaskCache[.live])
        XCTAssertNotNil(manager.taskIndexCache[.live]?[sourceSibling.id])
        XCTAssertEqual(manager.taskIndexCache[.live]?[moveMe.id]?.parentTask?.id, targetRoot.id)
    }

    func testMoveSelectedTasksDownUsesSingleSave() throws {
        let root = makeTask("Root", order: 0)
        let a = makeTask("A", order: 0, parent: root)
        let b = makeTask("B", order: 1, parent: root)
        let c = makeTask("C", order: 2, parent: root)
        let d = makeTask("D", order: 3, parent: root)
        try saveTasks([root, a, b, c, d])

        manager.selectTasks(orderedIDs: [b.id, c.id], anchor: b.id, cursor: c.id)

        let baselineSaves = manager.saveInvocationCount
        manager.moveSelectedTasksDown()

        XCTAssertEqual(manager.saveInvocationCount - baselineSaves, 1)
        XCTAssertEqual(try liveSiblingNames(parent: root), ["A", "D", "B", "C"])
    }

    func testTemplateMoveDoesNotInvalidateLiveVisibleCache() throws {
        let liveRoot = makeTask("Live Root", order: 0)
        let liveChild = makeTask("Live Child", order: 0, parent: liveRoot)
        let templateA = makeTask("Template A", order: 0, isTemplate: true)
        let templateB = makeTask("Template B", order: 1, isTemplate: true)
        try saveTasks([liveRoot, liveChild, templateA, templateB])

        _ = manager.snapshotVisibleTaskIDs()
        XCTAssertNotNil(manager.visibleLiveTaskIDsCache)

        let baselineSaves = manager.saveInvocationCount
        manager.moveTemplateTask(
            draggedTaskID: templateB.id,
            targetTaskID: templateA.id,
            parentOfList: nil,
            moveBeforeTarget: true
        )

        XCTAssertEqual(manager.saveInvocationCount - baselineSaves, 1)
        XCTAssertNotNil(manager.visibleLiveTaskIDsCache)
        XCTAssertEqual(try templateSiblingNames(parent: nil), ["Template B", "Template A"])
    }

    func testLockedThreadCacheUpdatesWhenTaskMovesIntoAndOutOfLockedBranch() throws {
        let unlockedRoot = makeTask("Unlocked Root", order: 0)
        let moving = makeTask("Moving", order: 0, parent: unlockedRoot)
        let lockedRoot = makeTask("Locked Root", order: 1, isLocked: true)
        let lockedTarget = makeTask("Locked Target", order: 0, parent: lockedRoot)
        let safeTarget = makeTask("Safe Target", order: 1, parent: unlockedRoot)
        try saveTasks([unlockedRoot, moving, lockedRoot, lockedTarget, safeTarget])

        XCTAssertFalse(manager.isTaskInLockedThreadCached(for: moving.id, kind: .live))

        manager.moveTask(
            draggedTaskID: moving.id,
            targetTaskID: lockedTarget.id,
            parentOfList: lockedRoot,
            moveBeforeTarget: false
        )

        XCTAssertTrue(manager.isTaskInLockedThreadCached(for: moving.id, kind: .live))

        manager.moveTask(
            draggedTaskID: moving.id,
            targetTaskID: safeTarget.id,
            parentOfList: unlockedRoot,
            moveBeforeTarget: true
        )

        XCTAssertFalse(manager.isTaskInLockedThreadCached(for: moving.id, kind: .live))
    }

    private func makeTask(
        _ name: String,
        order: Int,
        parent: Task? = nil,
        isTemplate: Bool = false,
        isLocked: Bool = false
    ) -> Task {
        Task(
            name: name,
            displayOrder: order,
            isTemplateComponent: isTemplate,
            isLocked: isLocked,
            parentTask: parent
        )
    }

    private func saveTasks(_ tasks: [Task]) throws {
        for task in tasks {
            container.mainContext.insert(task)
        }
        try container.mainContext.save()
        container.mainContext.processPendingChanges()
    }

    private func liveSiblingNames(parent: Task?) throws -> [String] {
        try fetchSiblingNames(parent: parent, kind: .live)
    }

    private func templateSiblingNames(parent: Task?) throws -> [String] {
        try fetchSiblingNames(parent: parent, kind: .template)
    }

    private func fetchSiblingNames(parent: Task?, kind: TaskManager.TaskListKind) throws -> [String] {
        let parentID = parent?.id
        let predicate: Predicate<Task> = {
            switch (kind, parentID) {
            case (.live, .some(let id)):
                return #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask?.id == id }
            case (.live, .none):
                return #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil }
            case (.template, .some(let id)):
                return #Predicate<Task> { $0.isTemplateComponent && $0.parentTask?.id == id }
            case (.template, .none):
                return #Predicate<Task> { $0.isTemplateComponent && $0.parentTask == nil }
            }
        }()

        let descriptor = FetchDescriptor<Task>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.displayOrder, order: .forward)]
        )
        return try container.mainContext.fetch(descriptor).map(\.name)
    }
}
