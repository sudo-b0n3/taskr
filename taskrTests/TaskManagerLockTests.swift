import XCTest
import SwiftData
@testable import taskr

@MainActor
final class TaskManagerLockTests: XCTestCase {
    var container: ModelContainer!
    var manager: TaskManager!
    private var originalAllowClearingStruckDescendants: Bool?
    private var originalSkipClearingHiddenDescendants: Bool?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Task.self, TaskTemplate.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        manager = TaskManager(modelContext: container.mainContext)

        originalAllowClearingStruckDescendants = UserDefaults.standard.object(forKey: allowClearingStruckDescendantsPreferenceKey) as? Bool
        originalSkipClearingHiddenDescendants = UserDefaults.standard.object(forKey: skipClearingHiddenDescendantsPreferenceKey) as? Bool

        // Default settings for tests
        UserDefaults.standard.set(false, forKey: allowClearingStruckDescendantsPreferenceKey)
        UserDefaults.standard.set(false, forKey: skipClearingHiddenDescendantsPreferenceKey)
    }

    override func tearDownWithError() throws {
        if let original = originalAllowClearingStruckDescendants {
            UserDefaults.standard.set(original, forKey: allowClearingStruckDescendantsPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: allowClearingStruckDescendantsPreferenceKey)
        }

        if let original = originalSkipClearingHiddenDescendants {
            UserDefaults.standard.set(original, forKey: skipClearingHiddenDescendantsPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: skipClearingHiddenDescendantsPreferenceKey)
        }

        manager = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Lock Toggle Tests

    func testToggleLockForTaskSetsIsLocked() throws {
        let task = Task(name: "Test Task", displayOrder: 0)
        container.mainContext.insert(task)
        try container.mainContext.save()

        XCTAssertFalse(task.isLocked)
        manager.toggleLockForTask(task)
        XCTAssertTrue(task.isLocked)
        manager.toggleLockForTask(task)
        XCTAssertFalse(task.isLocked)
    }

    func testIsTaskInLockedThreadReturnsTrueForLockedTask() throws {
        let task = Task(name: "Locked Task", displayOrder: 0, isLocked: true)
        container.mainContext.insert(task)
        try container.mainContext.save()

        XCTAssertTrue(manager.isTaskInLockedThread(task))
    }

    func testIsTaskInLockedThreadReturnsTrueForChildOfLockedTask() throws {
        let parent = Task(name: "Locked Parent", displayOrder: 0, isLocked: true)
        container.mainContext.insert(parent)
        let child = Task(name: "Child", displayOrder: 0, parentTask: parent)
        container.mainContext.insert(child)
        try container.mainContext.save()

        XCTAssertTrue(manager.isTaskInLockedThread(child))
    }

    func testIsTaskInLockedThreadReturnsFalseForUnlockedTask() throws {
        let task = Task(name: "Unlocked Task", displayOrder: 0, isLocked: false)
        container.mainContext.insert(task)
        try container.mainContext.save()

        XCTAssertFalse(manager.isTaskInLockedThread(task))
    }

    // MARK: - Clear Completed Tests

    func testClearCompletedSkipsLockedTasks() throws {
        let lockedTask = Task(name: "Locked", displayOrder: 0, isLocked: true)
        lockedTask.isCompleted = true
        container.mainContext.insert(lockedTask)

        let unlockedTask = Task(name: "Unlocked", displayOrder: 1, isLocked: false)
        unlockedTask.isCompleted = true
        container.mainContext.insert(unlockedTask)

        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remaining = try container.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent })
        )

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "Locked")
    }

    func testClearCompletedSkipsTasksWithLockedAncestor() throws {
        let lockedParent = Task(name: "Locked Parent", displayOrder: 0, isLocked: true)
        container.mainContext.insert(lockedParent)

        let completedChild = Task(name: "Completed Child", displayOrder: 0, parentTask: lockedParent)
        completedChild.isCompleted = true
        container.mainContext.insert(completedChild)

        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remaining = try container.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent })
        )

        XCTAssertEqual(remaining.count, 2) // Both parent and child remain
        XCTAssertTrue(remaining.contains { $0.name == "Locked Parent" })
        XCTAssertTrue(remaining.contains { $0.name == "Completed Child" })
    }

    func testClearCompletedClearsUnlockedTasks() throws {
        let task1 = Task(name: "Complete 1", displayOrder: 0)
        task1.isCompleted = true
        container.mainContext.insert(task1)

        let task2 = Task(name: "Complete 2", displayOrder: 1)
        task2.isCompleted = true
        container.mainContext.insert(task2)

        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remaining = try container.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent })
        )

        XCTAssertTrue(remaining.isEmpty)
    }

    func testUnlockTaskAllowsClearing() throws {
        let task = Task(name: "Was Locked", displayOrder: 0, isLocked: true)
        task.isCompleted = true
        container.mainContext.insert(task)

        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        // First clear should not remove locked task
        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        var remaining = try container.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent })
        )
        XCTAssertEqual(remaining.count, 1)

        // Unlock the task
        manager.toggleLockForTask(task)
        XCTAssertFalse(task.isLocked)

        // Now clear should remove it
        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        remaining = try container.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent })
        )
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Multi-selection Lock Tests

    func testToggleLockForSelectedTasksLocksAllWhenAnyUnlocked() throws {
        let task1 = Task(name: "Task 1", displayOrder: 0, isLocked: true)
        container.mainContext.insert(task1)
        let task2 = Task(name: "Task 2", displayOrder: 1, isLocked: false)
        container.mainContext.insert(task2)

        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        manager.selectTasks(orderedIDs: [task1.id, task2.id], anchor: task1.id, cursor: task2.id)
        manager.toggleLockForSelectedTasks()

        XCTAssertTrue(task1.isLocked)
        XCTAssertTrue(task2.isLocked)
    }

    func testToggleLockForSelectedTasksUnlocksAllWhenAllLocked() throws {
        let task1 = Task(name: "Task 1", displayOrder: 0, isLocked: true)
        container.mainContext.insert(task1)
        let task2 = Task(name: "Task 2", displayOrder: 1, isLocked: true)
        container.mainContext.insert(task2)

        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        manager.selectTasks(orderedIDs: [task1.id, task2.id], anchor: task1.id, cursor: task2.id)
        manager.toggleLockForSelectedTasks()

        XCTAssertFalse(task1.isLocked)
        XCTAssertFalse(task2.isLocked)
    }
}
