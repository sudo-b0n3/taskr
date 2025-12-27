import XCTest
import SwiftData
@testable import taskr

@MainActor
final class TaskManagerTests: XCTestCase {
    var container: ModelContainer!
    var manager: TaskManager!
    private var originalAddRootTasksToTop: Bool?
    private var originalAddSubtasksToTop: Bool?
    private var originalCollapsedTaskIDs: [String]?
    private var originalAllowClearingStruckDescendants: Bool?
    private var originalSkipClearingHiddenDescendants: Bool?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Task.self, TaskTemplate.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        manager = TaskManager(modelContext: container.mainContext)
        originalAddRootTasksToTop = UserDefaults.standard.object(forKey: addRootTasksToTopPreferenceKey) as? Bool
        originalAddSubtasksToTop = UserDefaults.standard.object(forKey: addSubtasksToTopPreferenceKey) as? Bool
        originalCollapsedTaskIDs = UserDefaults.standard.array(forKey: collapsedTaskIDsPreferenceKey) as? [String]
        originalAllowClearingStruckDescendants = UserDefaults.standard.object(forKey: allowClearingStruckDescendantsPreferenceKey) as? Bool
        originalSkipClearingHiddenDescendants = UserDefaults.standard.object(forKey: skipClearingHiddenDescendantsPreferenceKey) as? Bool
        UserDefaults.standard.set(false, forKey: addRootTasksToTopPreferenceKey)
        UserDefaults.standard.set(false, forKey: addSubtasksToTopPreferenceKey)
        UserDefaults.standard.removeObject(forKey: collapsedTaskIDsPreferenceKey)
        UserDefaults.standard.set(false, forKey: allowClearingStruckDescendantsPreferenceKey)
        UserDefaults.standard.set(true, forKey: skipClearingHiddenDescendantsPreferenceKey)
    }

    override func tearDownWithError() throws {
        if let originalAddRootTasksToTop = originalAddRootTasksToTop {
            UserDefaults.standard.set(originalAddRootTasksToTop, forKey: addRootTasksToTopPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: addRootTasksToTopPreferenceKey)
        }

        if let originalAddSubtasksToTop = originalAddSubtasksToTop {
            UserDefaults.standard.set(originalAddSubtasksToTop, forKey: addSubtasksToTopPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: addSubtasksToTopPreferenceKey)
        }

        if let originalCollapsedTaskIDs = originalCollapsedTaskIDs {
            UserDefaults.standard.set(originalCollapsedTaskIDs, forKey: collapsedTaskIDsPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: collapsedTaskIDsPreferenceKey)
        }

        if let originalAllowClearingStruckDescendants = originalAllowClearingStruckDescendants {
            UserDefaults.standard.set(originalAllowClearingStruckDescendants, forKey: allowClearingStruckDescendantsPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: allowClearingStruckDescendantsPreferenceKey)
        }

        if let originalSkipClearingHiddenDescendants = originalSkipClearingHiddenDescendants {
            UserDefaults.standard.set(originalSkipClearingHiddenDescendants, forKey: skipClearingHiddenDescendantsPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: skipClearingHiddenDescendantsPreferenceKey)
        }

        manager = nil
        container = nil
        try super.tearDownWithError()
    }

    func testAddTaskFromPathCreatesHierarchy() throws {
        manager.addTaskFromPath(pathOverride: "/Work/Status Updates")

        let fetchDescriptor = FetchDescriptor<Task>(predicate: #Predicate { !$0.isTemplateComponent && $0.parentTask == nil })
        let roots = try container.mainContext.fetch(fetchDescriptor)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.name, "Work")
        XCTAssertEqual(roots.first?.subtasks?.count, 1)
        XCTAssertEqual(roots.first?.subtasks?.first?.name, "Status Updates")
    }

    func testDuplicateTaskClonesSubtree() throws {
        manager.addTaskFromPath(pathOverride: "/Planning/Launch Checklist")
        guard let planning = try container.mainContext.fetch(FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.name == "Planning" && task.parentTask == nil
        })).first,
              let original = planning.subtasks?.first else {
            return XCTFail("Expected seed task")
        }

        _ = manager.duplicateTask(original)

        let parentID = planning.id
        let fetchDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.parentTask?.id == parentID
        })
        let children = try container.mainContext.fetch(fetchDescriptor).sorted(by: { $0.displayOrder < $1.displayOrder })
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.contains(where: { $0.name.contains("copy") }))
    }

    func testAddSubtaskAppendsToParentAndReorders() throws {
        manager.addTaskFromPath(pathOverride: "/Parent/Existing")

        let parentDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil }
        )
        guard let parent = try container.mainContext.fetch(parentDescriptor).first else {
            return XCTFail("Expected parent task")
        }

        let parentID = parent.id
        let childDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask?.id == parentID },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        var children = try container.mainContext.fetch(childDescriptor)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.displayOrder, 0)

        let newChild = manager.addSubtask(to: parent)
        XCTAssertNotNil(newChild)

        children = try container.mainContext.fetch(childDescriptor)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].name, "Existing")
        XCTAssertEqual(children[1].id, newChild?.id)
        XCTAssertEqual(children.map(\.displayOrder), [0, 1])
    }

    func testApplySelectedSuggestionAppendsSlashAndSurfacesChildren() throws {
        manager.addTaskFromPath(pathOverride: "/Projects/Alpha")
        manager.addTaskFromPath(pathOverride: "/Projects/Beta")

        manager.updateAutocompleteSuggestions(for: "/Pro")

        XCTAssertEqual(manager.autocompleteSuggestions, ["/Projects"])
        XCTAssertEqual(manager.selectedSuggestionIndex, 0)

        manager.applySelectedSuggestion()

        XCTAssertEqual(manager.currentPathInput, "/Projects/")
        let childSuggestions = Set(manager.autocompleteSuggestions)
        XCTAssertEqual(childSuggestions, ["/Projects/Alpha", "/Projects/Beta"])
        XCTAssertEqual(manager.selectedSuggestionIndex, 0)
    }

    func testBulkPathInsertionMaintainsSequentialDisplayOrder() throws {
        let total = 100
        for index in 0..<total {
            manager.addTaskFromPath(pathOverride: "/Bulk/Item \(index)")
        }

        let rootDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.parentTask == nil && task.name == "Bulk"
        })
        guard let bulkRoot = try container.mainContext.fetch(rootDescriptor).first else {
            return XCTFail("Expected root Bulk task")
        }

        let bulkRootID = bulkRoot.id
        let childDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                !task.isTemplateComponent && task.parentTask?.id == bulkRootID
            },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        let children = try container.mainContext.fetch(childDescriptor)

        XCTAssertEqual(children.count, total)
        for (index, task) in children.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
            XCTAssertEqual(task.name, "Item \(index)")
        }
    }

    func testDeepPathInsertionDoesNotProduceFutureBackings() throws {
        let components = Array(repeating: "test", count: 12)
        let deepPath = "/" + components.joined(separator: "/")

        manager.addTaskFromPath(pathOverride: deepPath)

        let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        let tasks = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(tasks.count, components.count)
        for task in tasks {
            _ = task.displayOrder
        }

        let visibleIDs = manager.snapshotVisibleTaskIDs()
        XCTAssertEqual(visibleIDs.count, components.count)
    }

    func testClearingDeepCompletedTasksRemovesHierarchy() throws {
        let components = Array(repeating: "test", count: 18)
        let deepPath = "/" + components.joined(separator: "/")

        manager.addTaskFromPath(pathOverride: deepPath)

        let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        let tasks = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(tasks.count, components.count)

        let visibleIDs = manager.snapshotVisibleTaskIDs()
        XCTAssertEqual(visibleIDs.count, components.count)

        for id in visibleIDs {
            manager.toggleTaskCompletion(taskID: id)
        }

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remaining = try container.mainContext.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(manager.snapshotVisibleTaskIDs().isEmpty)
    }

    func testClearingDeepCompletedTasksWithLeafFirstCompletion() throws {
        let components = Array(repeating: "test", count: 18)
        let deepPath = "/" + components.joined(separator: "/")

        manager.addTaskFromPath(pathOverride: deepPath)

        let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        let tasks = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(tasks.count, components.count)

        let visibleIDs = manager.snapshotVisibleTaskIDs()
        XCTAssertEqual(visibleIDs.count, components.count)

        for id in visibleIDs.reversed() {
            manager.toggleTaskCompletion(taskID: id)
        }

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remaining = try container.mainContext.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(manager.snapshotVisibleTaskIDs().isEmpty)
    }

    func testClearCompletedSkipsHiddenDescendants() throws {
        manager.addTaskFromPath(pathOverride: "/Parent/Child")

        let parentDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> {
            !$0.isTemplateComponent && $0.parentTask == nil && $0.name == "Parent"
        })

        guard let parent = try container.mainContext.fetch(parentDescriptor).first,
              let child = parent.subtasks?.first else {
            return XCTFail("Expected Parent with Child hierarchy")
        }

        manager.toggleTaskCompletion(taskID: child.id)
        manager.setTaskExpanded(parent.id, expanded: false)

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remainingDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        let remaining = try container.mainContext.fetch(remainingDescriptor)
        XCTAssertEqual(remaining.count, 2)

        let childID = child.id
        let childFetch = FetchDescriptor<Task>(predicate: #Predicate<Task> {
            !$0.isTemplateComponent && $0.id == childID
        })
        let childResult = try container.mainContext.fetch(childFetch)
        XCTAssertEqual(childResult.count, 1)
    }

    func testClearCompletedRemovesHiddenDescendantsWhenPreferenceDisabled() throws {
        manager.addTaskFromPath(pathOverride: "/Parent/Child")

        let parentDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> {
            !$0.isTemplateComponent && $0.parentTask == nil && $0.name == "Parent"
        })

        guard let parent = try container.mainContext.fetch(parentDescriptor).first,
              let child = parent.subtasks?.first else {
            return XCTFail("Expected Parent with Child hierarchy")
        }

        manager.toggleTaskCompletion(taskID: child.id)
        manager.setTaskExpanded(parent.id, expanded: false)
        UserDefaults.standard.set(false, forKey: skipClearingHiddenDescendantsPreferenceKey)

        manager.clearCompletedTasks()
        container.mainContext.processPendingChanges()

        let remainingDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        let remaining = try container.mainContext.fetch(remainingDescriptor)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, parent.id)
    }

    func testBulkDeletionResequencesAndPrunesCollapsedState() throws {
        let total = 50
        for index in 0..<total {
            manager.addTaskFromPath(pathOverride: "/Cleanup/Child \(index)")
        }

        let rootDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.parentTask == nil && task.name == "Cleanup"
        })
        guard let cleanupRoot = try container.mainContext.fetch(rootDescriptor).first else {
            return XCTFail("Expected root Cleanup task")
        }

        let cleanupRootID = cleanupRoot.id
        let childDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                !task.isTemplateComponent && task.parentTask?.id == cleanupRootID
            },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        let initialChildren = try container.mainContext.fetch(childDescriptor)
        XCTAssertEqual(initialChildren.count, total)

        for child in initialChildren.prefix(10) {
            manager.setTaskExpanded(child.id, expanded: false)
        }

        let toDelete = Array(initialChildren.prefix(5))
        let survivingCollapsedIDs = Set(initialChildren[5..<10].map { $0.id })
        for task in toDelete {
            manager.deleteTask(task)
        }

        let remaining = try container.mainContext.fetch(childDescriptor)
        XCTAssertEqual(remaining.count, total - toDelete.count)
        let expectedNames = (5..<total).map { "Child \($0)" }
        XCTAssertEqual(remaining.map { $0.name }, expectedNames)
        for (index, task) in remaining.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }

        let collapsedIDs = manager.collapsedTaskIDs
        for deleted in toDelete {
            XCTAssertFalse(collapsedIDs.contains(deleted.id))
        }
        XCTAssertEqual(collapsedIDs, survivingCollapsedIDs)
    }

    func testToggleCompletionAdvancesMutationVersion() throws {
        manager.addTaskFromPath(pathOverride: "/Ops/Review")
        manager.addTaskFromPath(pathOverride: "/Ops/Deploy")
        manager.addTaskFromPath(pathOverride: "/Ops/Monitor")

        let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.parentTask?.name == "Ops" && task.parentTask?.parentTask == nil
        })
        let tasks = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(tasks.count, 3)

        let initialVersion = manager.completionMutationVersion
        for task in tasks {
            manager.toggleTaskCompletion(taskID: task.id)
        }
        XCTAssertEqual(manager.completionMutationVersion, initialVersion + tasks.count)

        for task in tasks {
            manager.toggleTaskCompletion(taskID: task.id)
        }
        XCTAssertEqual(manager.completionMutationVersion, initialVersion + (tasks.count * 2))
    }

    func testReorderOperationsMaintainStableDisplayOrder() throws {
        let parent = try XCTUnwrap(seedLinearHierarchy(rootName: "Order", childCount: 20))
        let parentID = parent.id
        let childDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                !task.isTemplateComponent && task.parentTask?.id == parentID
            },
            sortBy: [SortDescriptor(\.displayOrder)]
        )

        let children = try container.mainContext.fetch(childDescriptor)
        XCTAssertEqual(children.count, 20)

        manager.moveTask(
            draggedTaskID: children[0].id,
            targetTaskID: children[5].id,
            parentOfList: parent,
            moveBeforeTarget: false
        )

        manager.moveTask(
            draggedTaskID: children[8].id,
            targetTaskID: children[2].id,
            parentOfList: parent,
            moveBeforeTarget: true
        )

        var updated = try container.mainContext.fetch(childDescriptor)
        let idsAfterMoves = updated.map { $0.id }
        let uniqueIDs = Set(idsAfterMoves)
        XCTAssertEqual(idsAfterMoves.count, uniqueIDs.count)
        for (index, task) in updated.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }

        let focusChild = try XCTUnwrap(updated.first(where: { $0.name == "Child 5" }))
        manager.addSubtask(to: focusChild)
        manager.addSubtask(to: focusChild)
        manager.addSubtask(to: focusChild)

        let focusChildID = focusChild.id
        let grandchildDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                !task.isTemplateComponent && task.parentTask?.id == focusChildID
            },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        var grandchildren = try container.mainContext.fetch(grandchildDescriptor)
        XCTAssertEqual(grandchildren.count, 3)

        manager.moveTask(
            draggedTaskID: grandchildren[2].id,
            targetTaskID: grandchildren[0].id,
            parentOfList: focusChild,
            moveBeforeTarget: true
        )

        grandchildren = try container.mainContext.fetch(grandchildDescriptor)
        for (index, task) in grandchildren.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }

        updated = try container.mainContext.fetch(childDescriptor)
        XCTAssertEqual(updated.count, 20)
        for (index, task) in updated.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }
    }

    func testQuotedAndEscapedPathSegmentsFlow() throws {
        let complexPath = "/Ops/\"Release / Beta (QA)\"/\"Deploy \\\"Prod\\\"\"/SRE"
        manager.addTaskFromPath(pathOverride: complexPath)

        let rootFetch = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.parentTask == nil && task.name == "Ops"
        })
        guard let opsRoot = try container.mainContext.fetch(rootFetch).first else {
            return XCTFail("Expected Ops root task")
        }

        XCTAssertEqual(opsRoot.subtasks?.count ?? 0, 1)
        let release = try XCTUnwrap(opsRoot.subtasks?.first)
        XCTAssertEqual(release.name, "Release / Beta (QA)")
        XCTAssertEqual(release.subtasks?.count ?? 0, 1)
        let deploy = try XCTUnwrap(release.subtasks?.first)
        XCTAssertEqual(deploy.name, "Deploy \"Prod\"")
        XCTAssertEqual(deploy.subtasks?.count ?? 0, 1)
        XCTAssertEqual(deploy.subtasks?.first?.name, "SRE")

        manager.updateAutocompleteSuggestions(for: "/Ops/\"Release / Beta (QA)\"/De")
        let expectedEncodedDeploy = "/Ops/\"Release / Beta (QA)\"/\"Deploy \\\"Prod\\\"\""
        XCTAssertEqual(manager.autocompleteSuggestions, [expectedEncodedDeploy])
        XCTAssertEqual(manager.selectedSuggestionIndex, 0)

        manager.applySelectedSuggestion()
        XCTAssertEqual(manager.currentPathInput, expectedEncodedDeploy + "/")

        let expectedLeaf = expectedEncodedDeploy + "/SRE"
        XCTAssertEqual(Set(manager.autocompleteSuggestions), [expectedLeaf])
        XCTAssertEqual(manager.selectedSuggestionIndex, 0)
    }

    func testTemplateBulkOperationsMaintainConsistency() throws {
        manager.newTemplateName = "Launch Prep"
        manager.addTemplate()

        let templateFetch = FetchDescriptor<TaskTemplate>()
        guard let template = try container.mainContext.fetch(templateFetch).first else {
            return XCTFail("Expected template to be created")
        }
        let containerTask = try XCTUnwrap(template.taskStructure)

        for index in 0..<10 {
            manager.addTemplateRootTask(to: template, name: "Phase \(index)")
        }

        var rootNodes = try manager.fetchTemplateSiblings(for: containerTask)
        XCTAssertEqual(rootNodes.count, 10)

        let phase0 = try XCTUnwrap(rootNodes.first(where: { $0.name == "Phase 0" }))
        let phase3 = try XCTUnwrap(rootNodes.first(where: { $0.name == "Phase 3" }))
        let phase5 = try XCTUnwrap(rootNodes.first(where: { $0.name == "Phase 5" }))
        let phase7 = try XCTUnwrap(rootNodes.first(where: { $0.name == "Phase 7" }))
        let phase9 = try XCTUnwrap(rootNodes.first(where: { $0.name == "Phase 9" }))

        for index in 0..<5 {
            manager.addTemplateSubtask(to: phase0, name: "Checklist A\(index)")
        }
        for index in 0..<3 {
            manager.addTemplateSubtask(to: phase5, name: "Checklist B\(index)")
        }

        manager.moveTemplateTask(
            draggedTaskID: phase9.id,
            targetTaskID: phase0.id,
            parentOfList: containerTask,
            moveBeforeTarget: true
        )
        manager.moveTemplateTask(
            draggedTaskID: phase3.id,
            targetTaskID: phase7.id,
            parentOfList: containerTask,
            moveBeforeTarget: false
        )

        rootNodes = try manager.fetchTemplateSiblings(for: containerTask)
        for (index, task) in rootNodes.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }

        let movedStepName = "Checklist A0"
        let phase0Children = try manager.fetchTemplateSiblings(for: phase0)
        let toMove = try XCTUnwrap(phase0Children.first(where: { $0.name == movedStepName }))
        manager.reparentTemplateTask(draggedTaskID: toMove.id, newParentID: phase5.id)

        let phase0Updated = try manager.fetchTemplateSiblings(for: phase0)
        XCTAssertEqual(phase0Updated.count, 4)
        XCTAssertFalse(phase0Updated.contains(where: { $0.name == movedStepName }))

        let phase5Updated = try manager.fetchTemplateSiblings(for: phase5)
        XCTAssertEqual(phase5Updated.count, 4)
        XCTAssertTrue(phase5Updated.contains(where: { $0.name == movedStepName }))
        for (index, task) in phase5Updated.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }

        let rootsBeforeDelete = try manager.fetchTemplateSiblings(for: containerTask)
        for task in rootsBeforeDelete.suffix(2) {
            manager.deleteTemplateTask(task)
        }

        let remainingRoots = try manager.fetchTemplateSiblings(for: containerTask)
        XCTAssertEqual(remainingRoots.count, 8)
        for (index, task) in remainingRoots.enumerated() {
            XCTAssertEqual(task.displayOrder, index)
        }

        let remainingNames = remainingRoots.map(\.name)
        manager.applyTemplate(template)

        let liveRootFetch = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.parentTask == nil
        })
        let liveRoots = try container.mainContext.fetch(liveRootFetch)
        XCTAssertEqual(liveRoots.count, remainingRoots.count)
        XCTAssertEqual(Set(liveRoots.map(\.name)), Set(remainingNames))

        guard let livePhase5 = liveRoots.first(where: { $0.name == phase5.name }) else {
            return XCTFail("Expected live Phase 5 task")
        }
        let livePhase5Children = (livePhase5.subtasks ?? []).sorted(by: { $0.displayOrder < $1.displayOrder })
        XCTAssertTrue(livePhase5Children.contains(where: { $0.name == movedStepName }))
    }

    func testExportBackupIncludesTemplatesAndStatuses() throws {
        manager.addTaskFromPath(pathOverride: "/Work/Item")

        let rootDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { !$0.isTemplateComponent && $0.parentTask == nil && $0.name == "Work" }
        )
        guard let root = try container.mainContext.fetch(rootDescriptor).first,
              let item = root.subtasks?.first else {
            return XCTFail("Expected Work/Item hierarchy")
        }

        manager.toggleTaskCompletion(taskID: item.id)
        manager.toggleLockForTask(root)

        manager.newTemplateName = "Morning"
        manager.addTemplate()

        let templateDescriptor = FetchDescriptor<TaskTemplate>(
            predicate: #Predicate<TaskTemplate> { $0.name == "Morning" }
        )
        guard let template = try container.mainContext.fetch(templateDescriptor).first else {
            return XCTFail("Expected Morning template")
        }

        manager.addTemplateRootTask(to: template, name: "Coffee")
        guard let templateTask = template.taskStructure?.subtasks?.first else {
            return XCTFail("Expected template root task")
        }
        templateTask.isCompleted = true

        let data = try manager.exportUserBackupData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ExportBackupPayload.self, from: data)

        XCTAssertEqual(payload.tasks.count, 1)
        XCTAssertEqual(payload.templates.count, 1)
        guard let exportedRoot = payload.tasks.first else {
            return XCTFail("Expected exported root task")
        }
        XCTAssertEqual(exportedRoot.name, "Work")
        XCTAssertEqual(exportedRoot.isLocked, true)
        XCTAssertEqual(exportedRoot.subtasks.first?.name, "Item")
        XCTAssertEqual(exportedRoot.subtasks.first?.isCompleted, true)

        guard let exportedTemplate = payload.templates.first else {
            return XCTFail("Expected exported template")
        }
        XCTAssertEqual(exportedTemplate.name, "Morning")
        XCTAssertEqual(exportedTemplate.roots.first?.isCompleted, true)
    }

    func testDuplicateTemplateCopiesStructureAndStatus() throws {
        manager.newTemplateName = "Morning"
        manager.addTemplate()

        let templateFetch = FetchDescriptor<TaskTemplate>(predicate: #Predicate<TaskTemplate> { $0.name == "Morning" })
        guard let template = try container.mainContext.fetch(templateFetch).first else {
            return XCTFail("Expected Morning template")
        }

        manager.addTemplateRootTask(to: template, name: "Coffee")
        guard let root = template.taskStructure?.subtasks?.first else {
            return XCTFail("Expected template root task")
        }
        manager.addTemplateSubtask(to: root, name: "Beans")
        guard let child = root.subtasks?.first else {
            return XCTFail("Expected template subtask")
        }

        root.isCompleted = true
        root.isLocked = true
        child.isCompleted = false

        manager.duplicateTemplate(template)

        let templates = try container.mainContext.fetch(FetchDescriptor<TaskTemplate>())
        XCTAssertEqual(templates.count, 2)
        guard let duplicate = templates.first(where: { $0.name == "Morning (copy)" }) else {
            return XCTFail("Expected duplicate template")
        }

        let dupRoots = (duplicate.taskStructure?.subtasks ?? []).sorted(by: { $0.displayOrder < $1.displayOrder })
        XCTAssertEqual(dupRoots.count, 1)
        let dupRoot = try XCTUnwrap(dupRoots.first)
        XCTAssertEqual(dupRoot.name, "Coffee")
        XCTAssertTrue(dupRoot.isCompleted)
        XCTAssertTrue(dupRoot.isLocked)

        let dupChildren = (dupRoot.subtasks ?? []).sorted(by: { $0.displayOrder < $1.displayOrder })
        XCTAssertEqual(dupChildren.count, 1)
        let dupChild = try XCTUnwrap(dupChildren.first)
        XCTAssertEqual(dupChild.name, "Beans")
        XCTAssertFalse(dupChild.isCompleted)
    }

    func testStressDeleteNestedTasksDoesNotLeaveDanglingState() throws {
        let rootCount = 12
        let childrenPerRoot = 6
        let grandchildrenPerChild = 4

        var rootIDs: [UUID] = []

        for rootIndex in 0..<rootCount {
            let rootName = "Stress Parent \(rootIndex)"
            manager.addTaskFromPath(pathOverride: "/\(rootName)")
            let rootTask = try XCTUnwrap(manager.findUserTask(named: rootName, under: nil))
            rootIDs.append(rootTask.id)
            manager.setTaskExpanded(rootTask.id, expanded: true)

            for childIndex in 0..<childrenPerRoot {
                let childName = "Child \(rootIndex)-\(childIndex)"
                manager.addTaskFromPath(pathOverride: "/\(rootName)/\(childName)")
                let childTask = try XCTUnwrap(manager.findUserTask(named: childName, under: rootTask))
                if childIndex % 2 == 0 {
                    manager.toggleTaskCompletion(taskID: childTask.id)
                }
                manager.setTaskExpanded(childTask.id, expanded: childIndex % 3 == 0)

                for grandIndex in 0..<grandchildrenPerChild {
                    let grandName = "Grandchild \(rootIndex)-\(childIndex)-\(grandIndex)"
                    manager.addTaskFromPath(pathOverride: "/\(rootName)/\(childName)/\(grandName)")
                    let grandTask = try XCTUnwrap(manager.findUserTask(named: grandName, under: childTask))
                    if grandIndex % 3 == 0 {
                        manager.toggleTaskCompletion(taskID: grandTask.id)
                    }
                }
            }
        }

        for (index, rootID) in rootIDs.enumerated() {
            let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> {
                !$0.isTemplateComponent && $0.id == rootID
            })
            guard let root = try container.mainContext.fetch(descriptor).first else {
                continue
            }

            let rootChildren = (root.subtasks ?? []).sorted(by: { $0.displayOrder < $1.displayOrder })

            switch index % 3 {
            case 0:
                for child in rootChildren {
                    let grandchildren = Array(child.subtasks ?? [])
                    for grandchild in grandchildren {
                        manager.deleteTask(grandchild)
                    }
                    manager.deleteTask(child)
                }
                manager.deleteTask(root)
            case 1:
                for (childIdx, child) in rootChildren.enumerated() {
                    if childIdx % 2 == 0 {
                        manager.deleteTask(child)
                    } else {
                        let grandchildren = Array(child.subtasks ?? [])
                        for (grandIdx, grandchild) in grandchildren.enumerated() where grandIdx % 2 == 0 {
                            manager.deleteTask(grandchild)
                        }
                    }
                }
                manager.deleteTask(root)
            default:
                manager.deleteTask(root)
            }
        }

        let remainingDescriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { !$0.isTemplateComponent })
        let remaining = try container.mainContext.fetch(remainingDescriptor)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(manager.collapsedTaskIDs.isEmpty)
    }

    @discardableResult
    private func seedLinearHierarchy(rootName: String, childCount: Int) throws -> Task? {
        manager.addTaskFromPath(pathOverride: "/\(rootName)")
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { task in
            !task.isTemplateComponent && task.name == rootName && task.parentTask == nil
        })

        guard let parent = try container.mainContext.fetch(descriptor).first else {
            return nil
        }

        for index in 0..<childCount {
            manager.addTaskFromPath(pathOverride: "/\(rootName)/Child \(index)")
        }
        return parent
    }
}
