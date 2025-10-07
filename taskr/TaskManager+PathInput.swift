import AppKit
import Foundation
import SwiftData

extension TaskManager {
    func addTaskFromPath(pathOverride: String? = nil) {
        pathCoordinator.addTaskFromPath(pathOverride: pathOverride)
    }

    func updateAutocompleteSuggestions(for text: String) {
        pathCoordinator.updateAutocompleteSuggestions(for: text)
    }

    func selectNextSuggestion() {
        pathCoordinator.selectNextSuggestion()
    }

    func selectPreviousSuggestion() {
        pathCoordinator.selectPreviousSuggestion()
    }

    func applySelectedSuggestion() {
        pathCoordinator.applySelectedSuggestion()
    }

    func clearAutocomplete() {
        pathCoordinator.clearAutocomplete()
    }

    func copyTaskPath(_ task: Task) {
        let path = taskPath(for: task)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func taskPath(for task: Task) -> String {
        pathCoordinator.taskPath(for: task)
    }

    func findUserTask(named name: String, under parent: Task?) -> Task? {
        let parentID = parent?.id
        let predicate: Predicate<Task> = parentID.map { pID in
            #Predicate<Task> {
                !$0.isTemplateComponent && $0.name == name && $0.parentTask?.id == pID
            }
        } ?? #Predicate<Task> {
            !$0.isTemplateComponent && $0.name == name && $0.parentTask == nil
        }

        let descriptor = FetchDescriptor<Task>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    fileprivate func encodePathComponent(_ component: String) -> String {
        guard !component.isEmpty else { return "\"\"" }

        let needsQuoting: Bool = component.contains("/") ||
            component.contains("\"") ||
            component.first?.isWhitespace == true ||
            component.last?.isWhitespace == true

        var escaped = ""
        escaped.reserveCapacity(component.count)
        for char in component {
            if char == "\"" || char == "\\" {
                escaped.append("\\")
            }
            escaped.append(char)
        }

        if needsQuoting {
            return "\"" + escaped + "\""
        } else {
            return escaped
        }
    }
}

extension TaskManager {
    @MainActor
    final class PathInputCoordinator {
        private unowned let taskManager: TaskManager

        init(taskManager: TaskManager) {
            self.taskManager = taskManager
        }

        func addTaskFromPath(pathOverride: String?) {
            let pathToProcess = pathOverride ?? taskManager.currentPathInput
            var path = pathToProcess.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                clearAutocomplete()
                return
            }

            if !path.starts(with: "/") {
                path = "/" + path
            }
            guard path.count > 1 else {
                taskManager.currentPathInput = ""
                clearAutocomplete()
                return
            }

            let pathContent = String(path.dropFirst())
            var tokenized = tokenizePathContent(pathContent)
            if !tokenized.endedWithSeparator && !tokenized.remainder.isEmpty {
                tokenized.components.append(tokenized.remainder)
            }

            let finalComponents = tokenized.components
            guard !finalComponents.isEmpty else {
                taskManager.currentPathInput = ""
                clearAutocomplete()
                return
            }

            var currentParent: Task? = nil
            for componentName in finalComponents {
                if let existingTask = taskManager.findUserTask(named: componentName, under: currentParent) {
                    currentParent = existingTask
                    continue
                }

                let placeAtTop: Bool
                if currentParent == nil {
                    placeAtTop = UserDefaults.standard.bool(forKey: addRootTasksToTopPreferenceKey)
                } else {
                    placeAtTop = UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey)
                }

                let newDisplayOrder = taskManager.getDisplayOrderForInsertion(
                    for: currentParent,
                    placeAtTop: placeAtTop,
                    in: taskManager.modelContext
                )

                let newTask = Task(
                    name: componentName,
                    displayOrder: newDisplayOrder,
                    isTemplateComponent: false,
                    parentTask: currentParent
                )
                taskManager.modelContext.insert(newTask)
                currentParent = newTask
            }

            try? taskManager.modelContext.save()
            taskManager.currentPathInput = ""
            clearAutocomplete()
        }

        func updateAutocompleteSuggestions(for text: String) {
            taskManager.currentPathInput = text
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                clearAutocomplete()
                return
            }

            let content = trimmedText.hasPrefix("/") ? String(trimmedText.dropFirst()) : trimmedText
            let tokenized = tokenizePathContent(content)

            var parentContextForSuggestions: Task? = nil
            for component in tokenized.components {
                guard let found = taskManager.findUserTask(named: component, under: parentContextForSuggestions) else {
                    clearAutocomplete()
                    return
                }
                parentContextForSuggestions = found
            }

            var pathPrefix = "/"
            for component in tokenized.components {
                pathPrefix += taskManager.encodePathComponent(component) + "/"
            }

            let segmentToSearch = tokenized.endedWithSeparator ? "" : tokenized.remainder
            let segmentToSearchLower = segmentToSearch.lowercased()
            let pID = parentContextForSuggestions?.id

            let fetchPredicate: Predicate<Task> = pID.map { parentId in
                #Predicate<Task> {
                    !$0.isTemplateComponent && $0.parentTask?.id == parentId
                }
            } ?? #Predicate<Task> {
                !$0.isTemplateComponent && $0.parentTask == nil
            }

            let descriptor = FetchDescriptor<Task>(
                predicate: fetchPredicate,
                sortBy: [SortDescriptor(\.name)]
            )

            var potentialMatches: [Task] = []
            do {
                potentialMatches = try taskManager.modelContext.fetch(descriptor)
            } catch {
                print("Error fetching candidates: \(error)")
                clearAutocomplete()
                return
            }

            if tokenized.endedWithSeparator {
                taskManager.autocompleteSuggestions = potentialMatches.map { pathPrefix + taskManager.encodePathComponent($0.name) }
                taskManager.selectedSuggestionIndex = taskManager.autocompleteSuggestions.isEmpty ? nil : 0
                return
            }

            let filtered = potentialMatches
                .filter { $0.name.lowercased().contains(segmentToSearchLower) }
                .map { task in pathPrefix + taskManager.encodePathComponent(task.name) }

            taskManager.autocompleteSuggestions = filtered
            taskManager.selectedSuggestionIndex = filtered.isEmpty ? nil : 0
        }

        func selectNextSuggestion() {
            guard !taskManager.autocompleteSuggestions.isEmpty else { return }
            let nextIndex: Int
            if let current = taskManager.selectedSuggestionIndex {
                nextIndex = min(current + 1, taskManager.autocompleteSuggestions.count - 1)
            } else {
                nextIndex = 0
            }
            taskManager.selectedSuggestionIndex = nextIndex
        }

        func selectPreviousSuggestion() {
            guard !taskManager.autocompleteSuggestions.isEmpty else { return }
            let previousIndex: Int
            if let current = taskManager.selectedSuggestionIndex {
                previousIndex = max(0, current - 1)
            } else {
                previousIndex = taskManager.autocompleteSuggestions.count - 1
            }
            taskManager.selectedSuggestionIndex = previousIndex
        }

        func applySelectedSuggestion() {
            guard let suggestion = currentSuggestion() else { return }
            taskManager.currentPathInput = suggestion
            updateAutocompleteSuggestions(for: suggestion)
        }

        func clearAutocomplete() {
            taskManager.autocompleteSuggestions = []
            taskManager.selectedSuggestionIndex = nil
        }

        func taskPath(for task: Task) -> String {
            var components: [String] = []
            var current: Task? = task
            while let node = current {
                components.append(node.name)
                current = node.parentTask
            }
            let encoded = components.reversed().map(taskManager.encodePathComponent).joined(separator: "/")
            return "/" + encoded
        }

        private func currentSuggestion() -> String? {
            guard let index = taskManager.selectedSuggestionIndex,
                  index >= 0,
                  index < taskManager.autocompleteSuggestions.count else { return nil }
            return taskManager.autocompleteSuggestions[index]
        }

        private func tokenizePathContent(_ content: String) -> TokenizedPath {
            var components: [String] = []
            var currentSegment = ""
            var inQuotes = false
            var segmentHadQuotes = false
            var escaped = false

            for char in content {
                if escaped {
                    currentSegment.append(char)
                    escaped = false
                    continue
                }

                if char == "\\" {
                    escaped = true
                    continue
                }

                if char == "\"" {
                    segmentHadQuotes = true
                    inQuotes.toggle()
                    continue
                }

                if char == "/" && !inQuotes {
                    let processed = segmentHadQuotes ? currentSegment : currentSegment.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !processed.isEmpty {
                        components.append(processed)
                    }
                    currentSegment.removeAll(keepingCapacity: true)
                    segmentHadQuotes = false
                    continue
                }

                currentSegment.append(char)
            }

            if escaped {
                currentSegment.append("\\")
            }

            let usesQuotesForRemainder = segmentHadQuotes || inQuotes
            let remainder = usesQuotesForRemainder
                ? currentSegment
                : currentSegment.trimmingCharacters(in: .whitespacesAndNewlines)

            return TokenizedPath(
                components: components,
                remainder: remainder,
                remainderUsesQuotes: usesQuotesForRemainder,
                endedWithSeparator: content.last == "/"
            )
        }
    }
}

extension TaskManager.PathInputCoordinator {
    struct TokenizedPath {
        var components: [String]
        var remainder: String
        var remainderUsesQuotes: Bool
        var endedWithSeparator: Bool
    }
}
