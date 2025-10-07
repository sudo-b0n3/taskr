import XCTest
import SwiftData
@testable import taskr

@MainActor
final class TaskManagerTests: XCTestCase {
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
}
