import SwiftData
import Foundation

extension TaskManager {
    enum MoveDirection {
        case up
        case down
    }

    func predicate(for parent: Task?, kind: TaskListKind) -> Predicate<Task> {
        let parentID: UUID?
        if let parent = parent, parent.modelContext != nil {
            parentID = parent.id
        } else {
            parentID = nil
        }

        switch (kind, parentID) {
        case (.live, .some(let id)):
            return #Predicate<Task> {
                !$0.isTemplateComponent && $0.parentTask?.id == id
            }
        case (.live, .none):
            return #Predicate<Task> {
                !$0.isTemplateComponent && $0.parentTask == nil
            }
        case (.template, .some(let id)):
            return #Predicate<Task> {
                $0.isTemplateComponent && $0.parentTask?.id == id
            }
        case (.template, .none):
            return #Predicate<Task> {
                $0.isTemplateComponent && $0.parentTask == nil
            }
        }
    }

    func fetchSiblings(
        for parent: Task?,
        kind: TaskListKind,
        order: SortOrder = .forward
    ) throws -> [Task] {
        let descriptor = FetchDescriptor<Task>(
            predicate: predicate(for: parent, kind: kind),
            sortBy: [SortDescriptor<Task>(\Task.displayOrder, order: order)]
        )
        return try modelContext.fetch(descriptor)
    }

    func nextDisplayOrder(
        for parent: Task?,
        kind: TaskListKind,
        in context: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<Task>(
            predicate: predicate(for: parent, kind: kind),
            sortBy: [SortDescriptor<Task>(\Task.displayOrder, order: .reverse)]
        )
        if let highestTask = (try? context.fetch(descriptor))?.first {
            return highestTask.displayOrder + 1
        }

        let countDescriptor = FetchDescriptor<Task>(predicate: predicate(for: parent, kind: kind))
        let count = (try? context.fetchCount(countDescriptor)) ?? 0
        return count
    }

    func displayOrderForInsertion(
        for parent: Task?,
        kind: TaskListKind,
        placeAtTop: Bool,
        in context: ModelContext
    ) -> Int {
        guard placeAtTop else {
            return nextDisplayOrder(for: parent, kind: kind, in: context)
        }

        let descriptor = FetchDescriptor<Task>(
            predicate: predicate(for: parent, kind: kind),
            sortBy: [SortDescriptor<Task>(\Task.displayOrder, order: .forward)]
        )
        if let minOrder = (try? context.fetch(descriptor))?.first?.displayOrder {
            return minOrder - 1
        }
        return 0
    }

    func resequenceDisplayOrder(for parent: Task?, kind: TaskListKind) {
        let descriptor = FetchDescriptor<Task>(
            predicate: predicate(for: parent, kind: kind),
            sortBy: [SortDescriptor<Task>(\Task.displayOrder)]
        )
        do {
            let siblings = try modelContext.fetch(descriptor)
            var hasChangesToSave = false
            for (index, task) in siblings.enumerated() where task.displayOrder != index {
                task.displayOrder = index
                hasChangesToSave = true
            }
            if hasChangesToSave {
                try modelContext.save()
            }
        } catch {
            print("Error re-sequencing display order for parent \(parent?.name ?? "nil"): \(error)")
        }
    }

    func moveItem(
        _ task: Task,
        kind: TaskListKind,
        direction: MoveDirection
    ) {
        performListMutation {
            let parent = task.parentTask
            do {
                let siblings = try fetchSiblings(for: parent, kind: kind)
                guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return }

                switch direction {
                case .up:
                    guard index > 0 else { return }
                    let neighbor = siblings[index - 1]
                    swapDisplayOrder(task, neighbor)
                case .down:
                    guard index < siblings.count - 1 else { return }
                    let neighbor = siblings[index + 1]
                    swapDisplayOrder(task, neighbor)
                }

                try modelContext.save()
                resequenceDisplayOrder(for: parent, kind: kind)
            } catch {
                print("Error moving task (kind: \(kind)) : \(error)")
            }
        }
    }

    private func swapDisplayOrder(_ lhs: Task, _ rhs: Task) {
        let currentOrder = lhs.displayOrder
        lhs.displayOrder = rhs.displayOrder
        rhs.displayOrder = currentOrder
    }
}
