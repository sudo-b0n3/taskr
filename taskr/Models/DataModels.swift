// taskr/taskr/DataModels.swift
import Foundation
import SwiftData

@Model
final class Task {
    @Attribute(.unique) var id: UUID
    var name: String
    var isCompleted: Bool
    var creationDate: Date
    var displayOrder: Int
    var isTemplateComponent: Bool // New flag
    var isLocked: Bool = false // When true, task thread is protected from "Clear Completed"

    @Relationship(deleteRule: .cascade, inverse: \Task.parentTask)
    var subtasks: [Task]?

    var parentTask: Task?

    init(
        id: UUID = UUID(),
        name: String = "",
        isCompleted: Bool = false,
        creationDate: Date = Date(),
        displayOrder: Int = 0,
        isTemplateComponent: Bool = false, // Default to false
        isLocked: Bool = false,
        parentTask: Task? = nil
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.creationDate = creationDate
        self.displayOrder = displayOrder
        self.isTemplateComponent = isTemplateComponent
        self.isLocked = isLocked
        self.parentTask = parentTask
        self.subtasks = []
    }
}

@Model
final class TaskTemplate {
    @Attribute(.unique) var id: UUID
    var name: String

    @Relationship(deleteRule: .cascade)
    var taskStructure: Task? // This will be the "TEMPLATE_INTERNAL_ROOT_CONTAINER"

    init(id: UUID = UUID(), name: String = "", taskStructure: Task? = nil) {
        self.id = id
        self.name = name
        self.taskStructure = taskStructure
    }
}
