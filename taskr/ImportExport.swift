// taskr/taskr/ImportExport.swift
import Foundation
import SwiftData

struct ExportTaskNode: Codable {
    var name: String
    var isCompleted: Bool
    var creationDate: Date
    var subtasks: [ExportTaskNode]
}

extension TaskManager {
    // MARK: - Export
    func exportUserTasksData() throws -> Data {
        // Fetch top-level user tasks (non-templates)
        let roots = try fetchUserRootTasks()
        let nodes = roots.sorted(by: { $0.displayOrder < $1.displayOrder }).map { taskToNode($0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(nodes)
    }

    func exportUserTasks(to url: URL) throws {
        let data = try exportUserTasksData()
        try data.write(to: url, options: .atomic)
    }

    private func taskToNode(_ task: Task) -> ExportTaskNode {
        let children = (task.subtasks ?? []).sorted { $0.displayOrder < $1.displayOrder }
        return ExportTaskNode(
            name: task.name,
            isCompleted: task.isCompleted,
            creationDate: task.creationDate,
            subtasks: children.map { taskToNode($0) }
        )
    }

    private func fetchUserRootTasks() throws -> [Task] {
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate { !$0.isTemplateComponent && $0.parentTask == nil },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Import (append)
    func importUserTasks(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try importUserTasks(from: data)
    }

    func importUserTasks(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let nodes = try decoder.decode([ExportTaskNode].self, from: data)
        try appendImported(nodes: nodes)
    }

    private func appendImported(nodes: [ExportTaskNode]) throws {
        // Append to end of current root tasks
        for node in nodes {
            _ = try createTask(from: node, parent: nil)
        }
        try modelContext.save()
    }

    @discardableResult
    private func createTask(from node: ExportTaskNode, parent: Task?) throws -> Task {
        let order = nextDisplayOrder(for: parent)
        let t = Task(
            name: node.name,
            isCompleted: node.isCompleted,
            creationDate: node.creationDate,
            displayOrder: order,
            isTemplateComponent: false,
            parentTask: parent
        )
        modelContext.insert(t)
        t.subtasks = []
        for child in node.subtasks {
            let childTask = try createTask(from: child, parent: t)
            t.subtasks?.append(childTask)
        }
        return t
    }

    private func nextDisplayOrder(for parent: Task?) -> Int {
        let pID = parent?.id
        let predicate: Predicate<Task>
        if let parentId = pID {
            predicate = #Predicate<Task> { task in
                !task.isTemplateComponent && task.parentTask?.id == parentId
            }
        } else {
            predicate = #Predicate<Task> { task in
                !task.isTemplateComponent && task.parentTask == nil
            }
        }
        let descriptor = FetchDescriptor<Task>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.displayOrder, order: .reverse)]
        )
        do {
            let highestTask = try modelContext.fetch(descriptor).first
            return (highestTask?.displayOrder ?? -1) + 1
        } catch {
            let countDescriptor = FetchDescriptor<Task>(predicate: predicate)
            let count = (try? modelContext.fetchCount(countDescriptor)) ?? 0
            return count
        }
    }
}
