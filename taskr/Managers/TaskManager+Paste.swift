import AppKit
import Foundation
import SwiftData

// MARK: - Paste Result Types

extension TaskManager {
    enum PasteResult: Equatable {
        case success(count: Int)
        case noSelection
        case multipleSelection
        case emptyClipboard
        case parseError
        case limitExceeded(message: String)
    }
    
    struct ParsedTaskEntry {
        let name: String
        let depth: Int
        let isCompleted: Bool
    }
}

// MARK: - Clipboard Parsing

extension TaskManager {
    nonisolated private static let maxPasteBytes = 1 * 1024 * 1024
    nonisolated private static let maxPasteTaskCount = 2_000
    nonisolated private static let maxPasteDepth = 64
    
    private enum PasteParseOutcome {
        case success([ParsedTaskEntry])
        case failure(PasteResult)
    }

    /// Cached regex for taskr format parsing — compiled once for efficiency
    private static let taskrFormatRegex: NSRegularExpression? = {
        let pattern = #"^(\t*)\((x?)\) - (.+)$"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()
    
    /// Parses clipboard content, trying taskr format first, then plain text fallback
    func parseClipboardContent(_ content: String) -> [ParsedTaskEntry]? {
        let lines = content.components(separatedBy: .newlines)
        
        // Try taskr format first
        if let taskrParsed = parseTaskrFormat(lines), !taskrParsed.isEmpty {
            return taskrParsed
        }
        
        // Fallback to plain text (each non-empty line is a task at depth 0)
        let plainTextEntries = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ParsedTaskEntry(name: $0, depth: 0, isCompleted: false) }
        
        return plainTextEntries.isEmpty ? nil : plainTextEntries
    }
    
    /// Parses taskr format: `\t*() - Name` or `\t*(x) - Name`
    private func parseTaskrFormat(_ lines: [String]) -> [ParsedTaskEntry]? {
        guard let regex = Self.taskrFormatRegex else {
            return nil
        }
        
        var entries: [ParsedTaskEntry] = []
        var matchedAny = false
        
        for line in lines {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range) else {
                // If any non-empty line doesn't match, this isn't taskr format
                return nil
            }
            
            matchedAny = true
            
            let tabsRange = Range(match.range(at: 1), in: line)!
            let statusRange = Range(match.range(at: 2), in: line)!
            let nameRange = Range(match.range(at: 3), in: line)!
            
            let depth = line[tabsRange].count
            let isCompleted = line[statusRange] == "x"
            let name = String(line[nameRange])
            
            entries.append(ParsedTaskEntry(name: name, depth: depth, isCompleted: isCompleted))
        }
        
        return matchedAny ? entries : nil
    }
    
    /// Entry point called by ⌘V keyboard shortcut
    /// Handles the paste and publishes result for UI to handle dialogs
    func triggerPaste() {
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pendingPasteResult = .emptyClipboard
            return
        }

        switch parseAndValidateClipboardContent(content) {
        case .failure(let errorResult):
            pendingPasteResult = errorResult
            return
        case .success(let entries):
            let result = pasteTasksFromParsed(entries: entries)

            switch result {
            case .success:
                pendingPasteResult = nil
            case .noSelection:
                if UserDefaults.standard.bool(forKey: skipPasteRootConfirmationPreferenceKey) {
                    let createdCount = createTasksFromParsed(entries: entries, under: nil)
                    pendingPasteResult = nil
                    _ = createdCount
                } else {
                    pendingPasteResult = result
                }
            case .multipleSelection, .emptyClipboard, .parseError, .limitExceeded:
                pendingPasteResult = result
            }
        }
    }

    private func parseAndValidateClipboardContent(_ content: String) -> PasteParseOutcome {
        let byteCount = content.lengthOfBytes(using: .utf8)
        guard byteCount <= Self.maxPasteBytes else {
            let maximum = ByteCountFormatter.string(fromByteCount: Int64(Self.maxPasteBytes), countStyle: .file)
            return .failure(.limitExceeded(message: "Clipboard content is too large. Maximum allowed is \(maximum)."))
        }

        guard let entries = parseClipboardContent(content), !entries.isEmpty else {
            return .failure(.parseError)
        }

        guard entries.count <= Self.maxPasteTaskCount else {
            return .failure(.limitExceeded(message: "Clipboard contains too many tasks. Maximum allowed is \(Self.maxPasteTaskCount)."))
        }

        let minDepth = entries.map(\.depth).min() ?? 0
        let adjustedMaxDepth = entries.map { max(0, $0.depth - minDepth) }.max() ?? 0
        guard adjustedMaxDepth <= Self.maxPasteDepth else {
            return .failure(.limitExceeded(message: "Clipboard task nesting is too deep. Maximum allowed depth is \(Self.maxPasteDepth)."))
        }

        return .success(entries)
    }
}

// MARK: - Paste Operations

extension TaskManager {
    /// Attempts to paste pre-parsed entries under the selected task
    /// Returns the result for UI to handle (confirmation dialogs, errors)
    private func pasteTasksFromParsed(entries: [ParsedTaskEntry]) -> PasteResult {
        // Check selection state
        let selectedCount = selectedTaskIDs.count
        
        if selectedCount > 1 {
            return .multipleSelection
        }
        
        if selectedCount == 0 {
            return .noSelection
        }
        
        // Single task selected - paste under it
        guard let parentID = selectedTaskIDs.first,
              let parentTask = task(withID: parentID) else {
            return .parseError
        }
        
        let createdCount = createTasksFromParsed(entries: entries, under: parentTask)
        return .success(count: createdCount)
    }
    
    /// Pastes tasks at root level (called from confirmation dialog)
    func pasteTasksAtRootLevel() -> PasteResult {
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyClipboard
        }

        switch parseAndValidateClipboardContent(content) {
        case .failure(let errorResult):
            return errorResult
        case .success(let entries):
            let createdCount = createTasksFromParsed(entries: entries, under: nil)
            return .success(count: createdCount)
        }
    }
    
    /// Creates tasks from parsed entries under the given parent (nil = root level)
    @discardableResult
    private func createTasksFromParsed(entries: [ParsedTaskEntry], under parent: Task?) -> Int {
        guard !entries.isEmpty else { return 0 }
        
        let minDepth = entries.map(\.depth).min() ?? 0
        let placeAtTop = UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey)
        
        var createdTasks: [Task] = []
        var taskStack: [(task: Task, depth: Int)] = []
        
        return performListMutation {
            do {
                for entry in entries {
                    let adjustedDepth = entry.depth - minDepth
                    
                    // Find the correct parent for this depth
                    let effectiveParent: Task?
                    if adjustedDepth == 0 {
                        // Top-level entry goes under the selected parent (or root)
                        effectiveParent = parent
                    } else {
                        // Find the most recent task at depth-1 to be our parent
                        while let last = taskStack.last, last.depth >= adjustedDepth {
                            taskStack.removeLast()
                        }
                        effectiveParent = taskStack.last?.task ?? parent
                    }
                    
                    // Calculate display order
                    let displayOrder = displayOrderForInsertion(
                        for: effectiveParent,
                        kind: .live,
                        placeAtTop: placeAtTop,
                        in: modelContext
                    )
                    
                    // Create the task
                    let newTask = Task(
                        name: entry.name,
                        isCompleted: entry.isCompleted,
                        creationDate: Date(),
                        displayOrder: displayOrder,
                        isTemplateComponent: false,
                        parentTask: effectiveParent
                    )
                    modelContext.insert(newTask)
                    createdTasks.append(newTask)
                    
                    // Add to stack for potential children
                    taskStack.append((task: newTask, depth: adjustedDepth))
                }
                
                try modelContext.save()
                
                // Expand parent to show pasted tasks
                if let parent = parent {
                    setTaskExpanded(parent.id, expanded: true)
                }
                
                // Resequence all affected parents
                var parentsToResequence: Set<UUID?> = []
                for task in createdTasks {
                    parentsToResequence.insert(task.parentTask?.id)
                }
                for parentID in parentsToResequence {
                    if let parentID = parentID, let parentTask = task(withID: parentID) {
                        resequenceDisplayOrder(for: parentTask, kind: .live)
                    } else if parentID == nil {
                        resequenceDisplayOrder(for: nil, kind: .live)
                    }
                }
                
                // Select the first created task
                if let firstTask = createdTasks.first {
                    replaceSelection(with: firstTask.id)
                }
                
                return createdTasks.count
            } catch {
                modelContext.rollback()
                print("Error pasting tasks: \(error)")
                return 0
            }
        } ?? 0
    }
}
