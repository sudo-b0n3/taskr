// taskr/taskr/DataModels.swift
import Foundation
import SwiftData

enum TaskTagColorKey: String, CaseIterable, Codable, Identifiable {
    case slate
    case blue
    case green
    case amber
    case red
    case teal
    case gray

    var id: String { rawValue }
}

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
    
    var tags: [TaskTag]?

    init(
        id: UUID = UUID(),
        name: String = "",
        isCompleted: Bool = false,
        creationDate: Date = Date(),
        displayOrder: Int = 0,
        isTemplateComponent: Bool = false, // Default to false
        isLocked: Bool = false,
        parentTask: Task? = nil,
        tags: [TaskTag] = []
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
        self.tags = tags
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

@Model
final class TaskTag {
    @Attribute(.unique) var id: UUID
    var phrase: String
    var colorKey: String
    var creationDate: Date
    var displayOrder: Int

    var tasks: [Task]?

    init(
        id: UUID = UUID(),
        phrase: String = "",
        colorKey: String = TaskTagColorKey.slate.rawValue,
        creationDate: Date = Date(),
        displayOrder: Int = 0
    ) {
        self.id = id
        self.phrase = phrase
        self.colorKey = colorKey
        self.creationDate = creationDate
        self.displayOrder = displayOrder
        self.tasks = []
    }
}
