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
    var tagIDs: [UUID]? = nil
    var subtasks: [ExportTaskNode]
}

struct ExportTemplateNode: Codable {
    var name: String
    var roots: [ExportTaskNode]
}

struct ExportTagNode: Codable {
    var id: UUID?
    var phrase: String
    var colorKey: String
    var creationDate: Date
    var displayOrder: Int?
}

struct ExportBackupPayload: Codable {
    var tasks: [ExportTaskNode]
    var templates: [ExportTemplateNode]
    var tags: [ExportTagNode]

    init(tasks: [ExportTaskNode], templates: [ExportTemplateNode], tags: [ExportTagNode] = []) {
        self.tasks = tasks
        self.templates = templates
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([ExportTaskNode].self, forKey: .tasks)
        templates = try container.decode([ExportTemplateNode].self, forKey: .templates)
        tags = try container.decodeIfPresent([ExportTagNode].self, forKey: .tags) ?? []
    }
}

extension TaskManager {
    enum ImportExportError: LocalizedError, Equatable {
        case fileTooLarge(actualBytes: Int, maxBytes: Int)
        case tooManyTasks(actualCount: Int, maxCount: Int)
        case taskTreeTooDeep(actualDepth: Int, maxDepth: Int)
        case unsupportedImportFileType

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let actualBytes, let maxBytes):
                return "Import file is too large (\(Self.byteCountString(actualBytes))). Maximum allowed is \(Self.byteCountString(maxBytes))."
            case .tooManyTasks(_, let maxCount):
                return "Import contains too many tasks. Maximum allowed is \(maxCount)."
            case .taskTreeTooDeep(_, let maxDepth):
                return "Import task nesting is too deep. Maximum allowed depth is \(maxDepth)."
            case .unsupportedImportFileType:
                return "Import requires a regular file."
            }
        }

        private static func byteCountString(_ bytes: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    nonisolated static let maxImportBytes = 5 * 1024 * 1024
    nonisolated static let maxImportTaskCount = 10_000
    nonisolated static let maxImportDepth = 64

    private struct ImportStats {
        let nodeCount: Int
        let maxDepth: Int
    }

    private enum ImportScanRootMode {
        case taskArray
        case templateArray
        case backupOrTaskArray
    }

    private enum ImportArrayRole {
        case generic
        case taskList(parentDepth: Int)
    }

    private enum ImportArrayState {
        case valueOrEnd
        case commaOrEnd
    }

    private struct ImportArrayContext {
        var role: ImportArrayRole
        var state: ImportArrayState = .valueOrEnd
    }

    private enum ImportObjectState {
        case keyOrEnd
        case colon(String)
        case value(String)
        case commaOrEnd
    }

    private struct ImportObjectContext {
        var taskDepth: Int?
        var state: ImportObjectState = .keyOrEnd
    }

    private enum ImportContainer {
        case object(ImportObjectContext)
        case array(ImportArrayContext)
    }

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
            tagIDs: task.tagsForExport.map(\.id),
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
        let tags = try exportTagNodes()
        let payload = ExportBackupPayload(tasks: tasks, templates: templates, tags: tags)
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
    func importUserTasks(from url: URL) async throws {
        let data = try await readValidatedImportDataOffMain(from: url)
        try importUserTasks(from: data)
    }

    func importUserTasks(from data: Data) throws {
        try Self.validateImportDataSize(data.count)
        try prevalidateImportStructure(in: data, rootMode: .taskArray)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let nodes = try decoder.decode([ExportTaskNode].self, from: data)
        try validateImportTaskNodes(nodes)
        try appendImported(nodes: nodes, preserveMetadata: false)
        try modelContext.save()
    }

    func importUserBackup(from url: URL) async throws {
        let data = try await readValidatedImportDataOffMain(from: url)
        try importUserBackup(from: data)
    }

    func importUserBackup(from data: Data) throws {
        try Self.validateImportDataSize(data.count)
        try prevalidateImportStructure(in: data, rootMode: .backupOrTaskArray)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let payload = try? decoder.decode(ExportBackupPayload.self, from: data) {
            try validateImportBackupPayload(payload)
            let tagLookup = try appendImportedTags(nodes: payload.tags, preserveMetadata: true)
            if !payload.tasks.isEmpty {
                try appendImported(nodes: payload.tasks, preserveMetadata: true, tagLookup: tagLookup)
            }
            if !payload.templates.isEmpty {
                try appendImportedTemplates(nodes: payload.templates, preserveMetadata: true)
            }
            try modelContext.save()
            return
        }

        let nodes = try decoder.decode([ExportTaskNode].self, from: data)
        try validateImportTaskNodes(nodes)
        try appendImported(nodes: nodes, preserveMetadata: false)
        try modelContext.save()
    }

    private func appendImported(
        nodes: [ExportTaskNode],
        preserveMetadata: Bool,
        tagLookup: [UUID: TaskTag] = [:]
    ) throws {
        // Append to end of current root tasks
        for node in nodes {
            _ = try createTask(from: node, parent: nil, preserveMetadata: preserveMetadata, tagLookup: tagLookup)
        }
    }

    func importUserTasksBackup(from data: Data) throws {
        try Self.validateImportDataSize(data.count)
        try prevalidateImportStructure(in: data, rootMode: .taskArray)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let nodes = try decoder.decode([ExportTaskNode].self, from: data)
        try validateImportTaskNodes(nodes)
        try appendImported(nodes: nodes, preserveMetadata: true)
        try modelContext.save()
    }

    func importUserTemplates(from data: Data) throws {
        try Self.validateImportDataSize(data.count)
        try prevalidateImportStructure(in: data, rootMode: .templateArray)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let nodes = try decoder.decode([ExportTemplateNode].self, from: data)
        try validateImportTemplateNodes(nodes)
        try appendImportedTemplates(nodes: nodes, preserveMetadata: true)
        try modelContext.save()
    }

    @discardableResult
    private func createTask(
        from node: ExportTaskNode,
        parent: Task?,
        preserveMetadata: Bool,
        tagLookup: [UUID: TaskTag]
    ) throws -> Task {
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
        if preserveMetadata {
            t.tags = tagsForImport(node: node, tagLookup: tagLookup)
        }
        t.subtasks = []
        for child in node.subtasks {
            let childTask = try createTask(from: child, parent: t, preserveMetadata: preserveMetadata, tagLookup: tagLookup)
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

    private func exportTagNodes() throws -> [ExportTagNode] {
        let descriptor = FetchDescriptor<TaskTag>(
            sortBy: [
                SortDescriptor(\TaskTag.displayOrder, order: .forward),
                SortDescriptor(\TaskTag.creationDate, order: .forward)
            ]
        )
        let tags = try modelContext.fetch(descriptor)
        return tags.map { tag in
            ExportTagNode(
                id: tag.id,
                phrase: tag.phrase,
                colorKey: tag.colorKey,
                creationDate: tag.creationDate,
                displayOrder: tag.displayOrder
            )
        }
    }

    private func appendImportedTags(nodes: [ExportTagNode], preserveMetadata: Bool) throws -> [UUID: TaskTag] {
        guard !nodes.isEmpty else { return [:] }

        let existingTags = try modelContext.fetch(FetchDescriptor<TaskTag>())
        var existingByID: [UUID: TaskTag] = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.id, $0) })
        var lookup: [UUID: TaskTag] = [:]
        var nextDisplayOrder = (existingTags.map(\.displayOrder).max() ?? -1) + 1

        for node in nodes {
            let rawColorKey = node.colorKey
            let safeColorKey = TaskTagPalette.options.contains(where: { $0.key == rawColorKey }) ? rawColorKey : TaskTagPalette.defaultKey

            if preserveMetadata, let nodeID = node.id, let existing = existingByID[nodeID] {
                existing.phrase = node.phrase
                existing.colorKey = safeColorKey
                existing.creationDate = node.creationDate
                existing.displayOrder = node.displayOrder ?? existing.displayOrder
                lookup[nodeID] = existing
                continue
            }

            let tagID = preserveMetadata ? (node.id ?? UUID()) : UUID()
            let tag = TaskTag(
                id: tagID,
                phrase: node.phrase,
                colorKey: safeColorKey,
                creationDate: node.creationDate,
                displayOrder: preserveMetadata ? (node.displayOrder ?? nextDisplayOrder) : nextDisplayOrder
            )
            modelContext.insert(tag)
            if let nodeID = node.id {
                lookup[nodeID] = tag
            }
            existingByID[tag.id] = tag
            nextDisplayOrder += 1
        }

        return lookup
    }

    private func tagsForImport(node: ExportTaskNode, tagLookup: [UUID: TaskTag]) -> [TaskTag] {
        guard let tagIDs = node.tagIDs, !tagIDs.isEmpty else { return [] }

        let importedTags = tagIDs.compactMap { tagLookup[$0] }
        return importedTags.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
            }
            return $0.displayOrder < $1.displayOrder
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

    nonisolated private func readValidatedImportDataOffMain(from url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Self.validatedImportData(from: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func validatedImportData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw ImportExportError.unsupportedImportFileType
        }
        if let fileSize = values.fileSize {
            try validateImportDataSize(fileSize)
        }
        return try readImportDataWithLimit(from: url, maxBytes: maxImportBytes)
    }

    nonisolated private static func validateImportDataSize(_ byteCount: Int) throws {
        guard byteCount <= maxImportBytes else {
            throw ImportExportError.fileTooLarge(actualBytes: byteCount, maxBytes: maxImportBytes)
        }
    }

    nonisolated private static func readImportDataWithLimit(from url: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var collected = Data()
        let chunkSize = min(64 * 1024, maxBytes + 1)

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }

            collected.append(chunk)
            if collected.count > maxBytes {
                throw ImportExportError.fileTooLarge(actualBytes: collected.count, maxBytes: maxBytes)
            }
        }

        return collected
    }

    private func validateImportBackupPayload(_ payload: ExportBackupPayload) throws {
        let taskStats = collectImportStats(from: payload.tasks)
        let templateStats = collectImportStats(from: payload.templates.flatMap(\.roots))
        let totalCount = taskStats.nodeCount + templateStats.nodeCount
        let totalDepth = max(taskStats.maxDepth, templateStats.maxDepth)

        try validateImportStats(nodeCount: totalCount, maxDepth: totalDepth)
    }

    private func validateImportTaskNodes(_ nodes: [ExportTaskNode]) throws {
        let stats = collectImportStats(from: nodes)
        try validateImportStats(nodeCount: stats.nodeCount, maxDepth: stats.maxDepth)
    }

    private func validateImportTemplateNodes(_ nodes: [ExportTemplateNode]) throws {
        let stats = collectImportStats(from: nodes.flatMap(\.roots))
        try validateImportStats(nodeCount: stats.nodeCount, maxDepth: stats.maxDepth)
    }

    private func validateImportStats(nodeCount: Int, maxDepth: Int) throws {
        guard nodeCount <= Self.maxImportTaskCount else {
            throw ImportExportError.tooManyTasks(actualCount: nodeCount, maxCount: Self.maxImportTaskCount)
        }
        guard maxDepth <= Self.maxImportDepth else {
            throw ImportExportError.taskTreeTooDeep(actualDepth: maxDepth, maxDepth: Self.maxImportDepth)
        }
    }

    // Fast pre-decode guard: scans JSON structure iteratively to cap task count/depth
    // before Codable recursion can consume unbounded resources.
    private func prevalidateImportStructure(in data: Data, rootMode: ImportScanRootMode) throws {
        let bytes = Array(data)
        var index = 0
        var rootSeen = false
        var nodeCount = 0
        var observedMaxDepth = 0
        var stack: [ImportContainer] = []

        while true {
            skipJSONWhitespace(bytes, &index)
            guard index < bytes.count else { break }
            let byte = bytes[index]

            if !rootSeen {
                rootSeen = true
                if byte == asciiLeftBracket {
                    let role: ImportArrayRole = {
                        switch rootMode {
                        case .taskArray, .backupOrTaskArray:
                            return .taskList(parentDepth: 0)
                        case .templateArray:
                            return .generic
                        }
                    }()
                    stack.append(.array(ImportArrayContext(role: role)))
                    index += 1
                    continue
                }
                if byte == asciiLeftBrace {
                    stack.append(.object(ImportObjectContext(taskDepth: nil)))
                    index += 1
                    continue
                }
            }

            guard let last = stack.last else {
                index += 1
                continue
            }

            switch last {
            case .object(var objectContext):
                switch objectContext.state {
                case .keyOrEnd:
                    if byte == asciiRightBrace {
                        stack.removeLast()
                        index += 1
                        finishCurrentValue(in: &stack)
                        continue
                    }
                    guard byte == asciiQuote,
                          let key = parseJSONString(bytes, &index, decodeEscapes: true)
                    else {
                        return
                    }
                    objectContext.state = .colon(key)
                    stack[stack.count - 1] = .object(objectContext)
                case .colon(let key):
                    guard byte == asciiColon else { return }
                    index += 1
                    objectContext.state = .value(key)
                    stack[stack.count - 1] = .object(objectContext)
                case .value(let key):
                    let (consumed, pushedContainer, taskDepth) = parseJSONValue(
                        bytes: bytes,
                        index: &index,
                        key: key,
                        parentTaskDepth: objectContext.taskDepth,
                        rootMode: rootMode,
                        stack: stack
                    )
                    guard consumed else { return }

                    objectContext.state = .commaOrEnd
                    stack[stack.count - 1] = .object(objectContext)

                    if let taskDepth {
                        nodeCount += 1
                        observedMaxDepth = max(observedMaxDepth, taskDepth)
                        try validateImportStats(nodeCount: nodeCount, maxDepth: observedMaxDepth)
                    }
                    if let pushedContainer {
                        stack.append(pushedContainer)
                    }
                case .commaOrEnd:
                    if byte == asciiComma {
                        index += 1
                        objectContext.state = .keyOrEnd
                        stack[stack.count - 1] = .object(objectContext)
                    } else if byte == asciiRightBrace {
                        stack.removeLast()
                        index += 1
                        finishCurrentValue(in: &stack)
                    } else {
                        return
                    }
                }

            case .array(var arrayContext):
                switch arrayContext.state {
                case .valueOrEnd:
                    if byte == asciiRightBracket {
                        stack.removeLast()
                        index += 1
                        finishCurrentValue(in: &stack)
                        continue
                    }

                    let (consumed, pushedContainer, taskDepth) = parseJSONValue(
                        bytes: bytes,
                        index: &index,
                        key: nil,
                        parentTaskDepth: parentDepth(for: arrayContext.role),
                        rootMode: rootMode,
                        stack: stack
                    )
                    guard consumed else { return }
                    arrayContext.state = .commaOrEnd
                    stack[stack.count - 1] = .array(arrayContext)

                    if let taskDepth {
                        nodeCount += 1
                        observedMaxDepth = max(observedMaxDepth, taskDepth)
                        try validateImportStats(nodeCount: nodeCount, maxDepth: observedMaxDepth)
                    }
                    if let pushedContainer {
                        stack.append(pushedContainer)
                    }
                case .commaOrEnd:
                    if byte == asciiComma {
                        index += 1
                        arrayContext.state = .valueOrEnd
                        stack[stack.count - 1] = .array(arrayContext)
                    } else if byte == asciiRightBracket {
                        stack.removeLast()
                        index += 1
                        finishCurrentValue(in: &stack)
                    } else {
                        return
                    }
                }
            }
        }
    }

    private func parseJSONValue(
        bytes: [UInt8],
        index: inout Int,
        key: String?,
        parentTaskDepth: Int?,
        rootMode: ImportScanRootMode,
        stack: [ImportContainer]
    ) -> (consumed: Bool, pushedContainer: ImportContainer?, taskDepth: Int?) {
        guard index < bytes.count else { return (false, nil, nil) }
        let byte = bytes[index]

        if byte == asciiLeftBrace {
            index += 1
            let taskDepth: Int?
            if let parentTaskDepth {
                taskDepth = parentTaskDepth + 1
            } else {
                taskDepth = nil
            }
            return (
                true,
                .object(ImportObjectContext(taskDepth: taskDepth)),
                taskDepth
            )
        }

        if byte == asciiLeftBracket {
            let role = roleForArrayValue(
                key: key,
                parentTaskDepth: parentTaskDepth,
                rootMode: rootMode,
                stack: stack
            )
            index += 1
            return (true, .array(ImportArrayContext(role: role)), nil)
        }

        if byte == asciiQuote {
            guard parseJSONString(bytes, &index, decodeEscapes: false) != nil else {
                return (false, nil, nil)
            }
            return (true, nil, nil)
        }

        if consumeJSONLiteral(bytes: bytes, index: &index) {
            return (true, nil, nil)
        }

        return (false, nil, nil)
    }

    private func finishCurrentValue(in stack: inout [ImportContainer]) {
        guard !stack.isEmpty else { return }
        switch stack[stack.count - 1] {
        case .object(var objectContext):
            if case .value = objectContext.state {
                objectContext.state = .commaOrEnd
                stack[stack.count - 1] = .object(objectContext)
            }
        case .array(var arrayContext):
            if arrayContext.state == .valueOrEnd {
                arrayContext.state = .commaOrEnd
                stack[stack.count - 1] = .array(arrayContext)
            }
        }
    }

    private func parentDepth(for role: ImportArrayRole) -> Int? {
        switch role {
        case .generic:
            return nil
        case .taskList(let depth):
            return depth
        }
    }

    private func roleForArrayValue(
        key: String?,
        parentTaskDepth: Int?,
        rootMode: ImportScanRootMode,
        stack: [ImportContainer]
    ) -> ImportArrayRole {
        if let key {
            if key == "subtasks", let parentTaskDepth {
                return .taskList(parentDepth: parentTaskDepth)
            }
            if key == "tasks" || key == "roots" {
                return .taskList(parentDepth: 0)
            }
            return .generic
        }

        if stack.isEmpty {
            switch rootMode {
            case .taskArray, .backupOrTaskArray:
                return .taskList(parentDepth: 0)
            case .templateArray:
                return .generic
            }
        }

        return .generic
    }

    private func skipJSONWhitespace(_ bytes: [UInt8], _ index: inout Int) {
        while index < bytes.count {
            let byte = bytes[index]
            if byte == asciiSpace || byte == asciiTab || byte == asciiNewline || byte == asciiCarriageReturn {
                index += 1
            } else {
                break
            }
        }
    }

    private func parseJSONString(_ bytes: [UInt8], _ index: inout Int, decodeEscapes: Bool) -> String? {
        guard index < bytes.count, bytes[index] == asciiQuote else { return nil }
        index += 1
        var output = ""
        while index < bytes.count {
            let byte = bytes[index]
            if byte == asciiQuote {
                index += 1
                return decodeEscapes ? output : ""
            }
            if byte == asciiBackslash {
                index += 1
                guard index < bytes.count else { return nil }
                let escaped = bytes[index]
                if decodeEscapes {
                    switch escaped {
                    case asciiQuote: output.append("\"")
                    case asciiBackslash: output.append("\\")
                    case asciiSlash: output.append("/")
                    case asciiB: output.append("\u{0008}")
                    case asciiF: output.append("\u{000C}")
                    case asciiN: output.append("\n")
                    case asciiR: output.append("\r")
                    case asciiT: output.append("\t")
                    case asciiU:
                        guard index + 4 < bytes.count else { return nil }
                        let hexBytes = Array(bytes[(index + 1)...(index + 4)])
                        guard let scalar = decodeHexScalar(hexBytes) else { return nil }
                        output.append(scalar)
                        index += 4
                    default:
                        return nil
                    }
                } else if escaped == asciiU {
                    guard index + 4 < bytes.count else { return nil }
                    index += 4
                }
                index += 1
                continue
            }

            if decodeEscapes {
                output.append(Character(UnicodeScalar(byte)))
            }
            index += 1
        }

        return nil
    }

    private func consumeJSONLiteral(bytes: [UInt8], index: inout Int) -> Bool {
        guard index < bytes.count else { return false }
        let byte = bytes[index]
        if byte == asciiMinus || (asciiZero...asciiNine).contains(byte) {
            index += 1
            while index < bytes.count {
                let current = bytes[index]
                if (asciiZero...asciiNine).contains(current) || current == asciiPlus || current == asciiMinus || current == asciiDot || current == asciiE || current == asciiLowerE {
                    index += 1
                } else {
                    break
                }
            }
            return true
        }
        if matchesLiteral(bytes: bytes, index: index, literal: [asciiT, asciiR, asciiU, asciiE]) {
            index += 4
            return true
        }
        if matchesLiteral(bytes: bytes, index: index, literal: [asciiF, asciiA, asciiL, asciiS, asciiE]) {
            index += 5
            return true
        }
        if matchesLiteral(bytes: bytes, index: index, literal: [asciiN, asciiU, asciiL, asciiL]) {
            index += 4
            return true
        }
        return false
    }

    private func matchesLiteral(bytes: [UInt8], index: Int, literal: [UInt8]) -> Bool {
        guard index + literal.count <= bytes.count else { return false }
        return Array(bytes[index..<(index + literal.count)]) == literal
    }

    private func decodeHexScalar(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 4 else { return nil }
        var value: UInt32 = 0
        for byte in bytes {
            value <<= 4
            switch byte {
            case asciiZero...asciiNine:
                value += UInt32(byte - asciiZero)
            case asciiA...asciiF:
                value += UInt32(byte - asciiA + 10)
            case asciiLowerA...asciiLowerF:
                value += UInt32(byte - asciiLowerA + 10)
            default:
                return nil
            }
        }
        guard let scalar = UnicodeScalar(value) else { return nil }
        return String(scalar)
    }

    private var asciiQuote: UInt8 { 34 }
    private var asciiBackslash: UInt8 { 92 }
    private var asciiSlash: UInt8 { 47 }
    private var asciiLeftBrace: UInt8 { 123 }
    private var asciiRightBrace: UInt8 { 125 }
    private var asciiLeftBracket: UInt8 { 91 }
    private var asciiRightBracket: UInt8 { 93 }
    private var asciiColon: UInt8 { 58 }
    private var asciiComma: UInt8 { 44 }
    private var asciiSpace: UInt8 { 32 }
    private var asciiTab: UInt8 { 9 }
    private var asciiNewline: UInt8 { 10 }
    private var asciiCarriageReturn: UInt8 { 13 }
    private var asciiMinus: UInt8 { 45 }
    private var asciiPlus: UInt8 { 43 }
    private var asciiDot: UInt8 { 46 }
    private var asciiZero: UInt8 { 48 }
    private var asciiNine: UInt8 { 57 }
    private var asciiA: UInt8 { 65 }
    private var asciiF: UInt8 { 70 }
    private var asciiE: UInt8 { 69 }
    private var asciiLowerA: UInt8 { 97 }
    private var asciiLowerE: UInt8 { 101 }
    private var asciiLowerF: UInt8 { 102 }
    private var asciiB: UInt8 { 98 }
    private var asciiN: UInt8 { 110 }
    private var asciiR: UInt8 { 114 }
    private var asciiT: UInt8 { 116 }
    private var asciiU: UInt8 { 117 }
    private var asciiL: UInt8 { 108 }
    private var asciiS: UInt8 { 115 }

    private func collectImportStats(from roots: [ExportTaskNode]) -> ImportStats {
        guard !roots.isEmpty else {
            return ImportStats(nodeCount: 0, maxDepth: 0)
        }

        var stack: [(node: ExportTaskNode, depth: Int)] = roots.map { ($0, 1) }
        var nodeCount = 0
        var observedMaxDepth = 0

        while let current = stack.popLast() {
            nodeCount += 1
            if current.depth > observedMaxDepth {
                observedMaxDepth = current.depth
            }
            for child in current.node.subtasks {
                stack.append((child, current.depth + 1))
            }
        }

        return ImportStats(nodeCount: nodeCount, maxDepth: observedMaxDepth)
    }
}

private extension Task {
    var tagsForExport: [TaskTag] {
        (tags ?? []).sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}
