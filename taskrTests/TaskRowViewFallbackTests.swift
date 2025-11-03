import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import taskr

@MainActor
final class TaskRowViewFallbackTests: XCTestCase {
    func testDetachedTaskRowRendersFallbackWithoutCrashing() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Task.self,
            TaskTemplate.self,
            configurations: config
        )
        let manager = TaskManager(modelContext: container.mainContext)

        let task = Task(name: "Regression", displayOrder: 0, isTemplateComponent: false)
        container.mainContext.insert(task)
        try container.mainContext.save()

        manager.deleteTask(task)
        try container.mainContext.save()
        container.mainContext.processPendingChanges()

        XCTAssertNil(task.modelContext, "Sanity check: task should be detached")

        let row = TaskRowView(task: task).environmentObject(manager)

        XCTAssertNoThrow(
            NSHostingController(rootView: row).view.layoutSubtreeIfNeeded(),
            "Detached rows should render via the fallback without touching SwiftData properties"
        )
    }
}
