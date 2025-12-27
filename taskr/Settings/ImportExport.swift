// taskr/taskr/ImportExport.swift
import Foundation
import SwiftData

struct ExportTaskNode: Codable {
    var id: UUID?
    var name: String
    var isCompleted: Bool
    var creationDate: Date
    var displayOrder: Int?
    var isLocked: Bool?
    var subtasks: [ExportTaskNode]
}

struct ExportTemplateNode: Codable {
    var name: String
    var roots: [ExportTaskNode]
}

struct ExportBackupPayload: Codable {
    var tasks: [ExportTaskNode]
    var templates: [ExportTemplateNode]
}

extension TaskManager {
    // MARK: - Export
    func exportUserTasksData() throws -> Data {
        // Fetch top-level user tasks (non-templates)
        let nodes = try exportTaskNodes()
        return try encodeExportPayload(nodes)
    }

    func exportUserTasks(to url: URL) throws {
        let data = try exportUserTasksData()
        try data.write(to: url, options: .atomic)
    }

    private func taskToNode(_ task: Task) -> ExportTaskNode {
        let children = (task.subtasks ?? []).sorted { $0.displayOrder < $1.displayOrder }
        return ExportTaskNode(
            id: task.id,
            name: task.name,
            isCompleted: task.isCompleted,
            creationDate: task.creationDate,
            displayOrder: task.displayOrder,
            isLocked: task.isLocked,
            subtasks: children.map { taskToNode($0) }
        )
    }

    func exportUserTemplatesData() throws -> Data {
        let nodes = try exportTemplateNodes()
        return try encodeExportPayload(nodes)
    }

    func exportUserBackupData() throws -> Data {
        let tasks = try exportTaskNodes()
        let templates = try exportTemplateNodes()
        let payload = ExportBackupPayload(tasks: tasks, templates: templates)
        return try encodeExportPayload(payload)
    }

    func exportUserBackup(to url: URL) throws {
        let data = try exportUserBackupData()
        try data.write(to: url, options: .atomic)
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
        try appendImported(nodes: nodes, preserveMetadata: false)
    }

    func importUserBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try importUserBackup(from: data)
    }

    func importUserBackup(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(ExportBackupPayload.self, from: data)
            if !payload.tasks.isEmpty {
                try appendImported(nodes: payload.tasks, preserveMetadata: true)
            }
            if !payload.templates.isEmpty {
                try appendImportedTemplates(nodes: payload.templates, preserveMetadata: true)
            }
            try modelContext.save()
        } catch {
            let nodes = try decoder.decode([ExportTaskNode].self, from: data)
            try appendImported(nodes: nodes, preserveMetadata: false)
            try modelContext.save()
        }
    }

    private func appendImported(nodes: [ExportTaskNode], preserveMetadata: Bool) throws {
        // Append to end of current root tasks
        for node in nodes {
            _ = try createTask(from: node, parent: nil, preserveMetadata: preserveMetadata)
        }
    }

    func importUserTasksBackup(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let nodes = try decoder.decode([ExportTaskNode].self, from: data)
        try appendImported(nodes: nodes, preserveMetadata: true)
        try modelContext.save()
    }

    func importUserTemplates(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let nodes = try decoder.decode([ExportTemplateNode].self, from: data)
        try appendImportedTemplates(nodes: nodes, preserveMetadata: true)
        try modelContext.save()
    }

    @discardableResult
    private func createTask(from node: ExportTaskNode, parent: Task?, preserveMetadata: Bool) throws -> Task {
        let order = preserveMetadata ? (node.displayOrder ?? nextDisplayOrder(for: parent)) : nextDisplayOrder(for: parent)
        let id = preserveMetadata ? (node.id ?? UUID()) : UUID()
        let t = Task(
            id: id,
            name: node.name,
            isCompleted: node.isCompleted,
            creationDate: node.creationDate,
            displayOrder: order,
            isTemplateComponent: false,
            isLocked: preserveMetadata ? (node.isLocked ?? false) : false,
            parentTask: parent
        )
        modelContext.insert(t)
        t.subtasks = []
        for child in node.subtasks {
            let childTask = try createTask(from: child, parent: t, preserveMetadata: preserveMetadata)
            t.subtasks?.append(childTask)
        }
        return t
    }

    @discardableResult
    private func createTemplateTask(from node: ExportTaskNode, parent: Task?, preserveMetadata: Bool) throws -> Task {
        let order = preserveMetadata ? (node.displayOrder ?? getNextDisplayOrderForTemplates(for: parent, in: modelContext))
            : getNextDisplayOrderForTemplates(for: parent, in: modelContext)
        let id = preserveMetadata ? (node.id ?? UUID()) : UUID()
        let t = Task(
            id: id,
            name: node.name,
            isCompleted: node.isCompleted,
            creationDate: node.creationDate,
            displayOrder: order,
            isTemplateComponent: true,
            isLocked: preserveMetadata ? (node.isLocked ?? false) : false,
            parentTask: parent
        )
        modelContext.insert(t)
        t.subtasks = []
        for child in node.subtasks {
            let childTask = try createTemplateTask(from: child, parent: t, preserveMetadata: preserveMetadata)
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

    private func exportTaskNodes() throws -> [ExportTaskNode] {
        let roots = try fetchUserRootTasks()
        return roots.sorted(by: { $0.displayOrder < $1.displayOrder }).map { taskToNode($0) }
    }

    private func exportTemplateNodes() throws -> [ExportTemplateNode] {
        let templates = try modelContext.fetch(
            FetchDescriptor<TaskTemplate>(sortBy: [SortDescriptor(\.name)])
        )
        return templates.map { template in
            let rootTasks = (template.taskStructure?.subtasks ?? [])
                .sorted { $0.displayOrder < $1.displayOrder }
                .map { taskToNode($0) }
            return ExportTemplateNode(name: template.name, roots: rootTasks)
        }
    }

    private func appendImportedTemplates(nodes: [ExportTemplateNode], preserveMetadata: Bool) throws {
        for node in nodes {
            let container = Task(
                name: "TEMPLATE_INTERNAL_ROOT_CONTAINER",
                displayOrder: 0,
                isTemplateComponent: true
            )
            modelContext.insert(container)
            container.subtasks = []
            let template = TaskTemplate(name: node.name, taskStructure: container)
            modelContext.insert(template)
            for root in node.roots {
                let created = try createTemplateTask(from: root, parent: container, preserveMetadata: preserveMetadata)
                container.subtasks?.append(created)
            }
        }
    }

    private func encodeExportPayload<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}
