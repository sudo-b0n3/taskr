// taskr/taskr/HelpView.swift
import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                basicsSection
                pathsSection
                completionSection
                templatesSection
                menusSection
                shortcutsSection
                supportSection
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 620)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Taskr Help")
                .font(.largeTitle)
                .bold()
            Text("Quick reference for adding tasks, managing paths, and working with templates.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var basicsSection: some View {
        helpSection(title: "Adding Tasks") {
            Text("• Type in the entry field using `/` to create nested subtasks (for example `/Work/Follow up`).")
            Text("• Press Return to add the task; Taskr automatically creates any missing parents.")
            Text("• Use the context menu (right-click) to reorder, duplicate, or add subtasks after creation.")
        }
    }

    private var pathsSection: some View {
        helpSection(title: "Using Quotes In Paths") {
            Text("• Wrap a path segment in quotes to keep `/` as part of the name: `/\"foo/bar\"/Notes`. This creates a `foo/bar` task instead of splitting into `foo` and `bar`.")
            Text("• Quotes also preserve leading/trailing spaces. You can include a literal quote by escaping it: `/\"Release \"v2\"\"`.")
            Text("• The Copy Path command (context menu → Copy Path) emits the path with the necessary quoting so you can paste/edit safely.")
        }
    }

    private var completionSection: some View {
        helpSection(title: "Completing & Clearing") {
            Text("• Click the circle beside a task to toggle completion. Subtasks visually strike when any ancestor is complete.")
            Text("• Use Clear Completed from the toolbar to purge finished items; the list keeps its current scroll position.")
        }
    }

    private var templatesSection: some View {
        helpSection(title: "Templates") {
            Text("• Build reusable checklists in the Templates tab. Right-click in the template editor to add subtasks or duplicate entries.")
            Text("• Apply a template to the live task list using the Apply button; Taskr merges existing tasks by name when possible.")
        }
    }

    private var menusSection: some View {
        helpSection(title: "Menu Bar & Dock") {
            Text("• Taskr lives in the menu bar by default; click the icon or press the global hotkey (⌃⌥N) to open it quickly.")
            Text("• In Settings you can keep a Dock icon visible or hide it when the standalone window is closed.")
        }
    }

    private var shortcutsSection: some View {
        helpSection(title: "Keyboard & Autocomplete") {
            Text("• Use Tab/Shift-Tab to accept suggestions, ↑/↓ to navigate them, and Return to commit.")
            Text("• Add tasks from anywhere with the global hotkey once accessibility access is granted (prompt appears on first use).")
        }
    }

    private var supportSection: some View {
        helpSection(title: "Need More Help?") {
            Text("• Send feedback or questions to hello@b0n3.net. Include reproduction steps if you run into issues.")
        }
    }

    private func helpSection<T: View>(title: String, @ViewBuilder content: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3)
                .bold()
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .font(.body)
        }
    }
}

#Preview {
    HelpView()
        .frame(width: 520, height: 640)
}
