import Foundation
import SwiftData

extension TaskManager {
    func fetchAllTags() -> [TaskTag] {
        let descriptor = FetchDescriptor<TaskTag>(
            sortBy: [
                SortDescriptor(\TaskTag.displayOrder, order: .forward),
                SortDescriptor(\TaskTag.creationDate, order: .forward)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func createTag(phrase: String, colorKey: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = fetchAllTags()
        let lowered = trimmed.lowercased()
        if existing.contains(where: { $0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered }) {
            return
        }

        let tag = TaskTag(
            phrase: trimmed,
            colorKey: TaskTagPalette.options.contains(where: { $0.key == colorKey }) ? colorKey : TaskTagPalette.defaultKey,
            creationDate: Date(),
            displayOrder: existing.count
        )
        modelContext.insert(tag)

        do {
            try modelContext.save()
            objectWillChange.send()
        } catch {
            modelContext.rollback()
            print("Error creating tag: \(error)")
        }
    }

    func updateTag(_ tag: TaskTag, phrase: String, colorKey: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        tag.phrase = trimmed
        tag.colorKey = TaskTagPalette.options.contains(where: { $0.key == colorKey }) ? colorKey : TaskTagPalette.defaultKey

        do {
            try modelContext.save()
            objectWillChange.send()
        } catch {
            modelContext.rollback()
            print("Error updating tag: \(error)")
        }
    }

    func deleteTag(_ tag: TaskTag) {
        let linkedTasks = tag.tasks ?? []
        for task in linkedTasks {
            task.tags?.removeAll(where: { $0.id == tag.id })
        }

        modelContext.delete(tag)

        do {
            try modelContext.save()
            resequenceTags()
            objectWillChange.send()
        } catch {
            modelContext.rollback()
            print("Error deleting tag: \(error)")
        }
    }

    func toggleTag(_ tag: TaskTag, for task: Task) {
        guard !task.isTemplateComponent else { return }

        var tags = task.tags ?? []
        if tags.contains(where: { $0.id == tag.id }) {
            tags.removeAll(where: { $0.id == tag.id })
        } else {
            tags.append(tag)
        }
        task.tags = tags.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
            }
            return $0.displayOrder < $1.displayOrder
        }

        do {
            try modelContext.save()
            objectWillChange.send()
        } catch {
            modelContext.rollback()
            print("Error toggling tag assignment: \(error)")
        }
    }

    func toggleTag(_ tag: TaskTag, for tasks: [Task]) {
        let liveTasks = tasks.filter { !$0.isTemplateComponent }
        guard !liveTasks.isEmpty else { return }

        let shouldApplyToAll = !liveTasks.allSatisfy { task in
            (task.tags ?? []).contains(where: { $0.id == tag.id })
        }

        for task in liveTasks {
            var tags = task.tags ?? []
            if shouldApplyToAll {
                if !tags.contains(where: { $0.id == tag.id }) {
                    tags.append(tag)
                }
            } else {
                tags.removeAll(where: { $0.id == tag.id })
            }
            task.tags = tags.sorted {
                if $0.displayOrder == $1.displayOrder {
                    return $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
                }
                return $0.displayOrder < $1.displayOrder
            }
        }

        do {
            try modelContext.save()
            objectWillChange.send()
        } catch {
            modelContext.rollback()
            print("Error toggling tag assignment for multiple tasks: \(error)")
        }
    }

    func taskHasTag(taskID: UUID, tagID: UUID) -> Bool {
        guard let task = task(withID: taskID) else { return false }
        return (task.tags ?? []).contains(where: { $0.id == tagID })
    }

    func tagsForDisplay(on task: Task) -> [TaskTag] {
        (task.tags ?? []).sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
            }
            return $0.displayOrder < $1.displayOrder
        }
    }

    private func resequenceTags() {
        let tags = fetchAllTags()
        for (index, tag) in tags.enumerated() {
            if tag.displayOrder != index {
                tag.displayOrder = index
            }
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            print("Error resequencing tags: \(error)")
        }
    }
}
