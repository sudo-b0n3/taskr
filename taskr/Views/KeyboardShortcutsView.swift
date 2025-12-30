import SwiftUI
import SwiftData

/// A compact, readable view showing all keyboard shortcuts
struct KeyboardShortcutsView: View {
    @EnvironmentObject var taskManager: TaskManager
    
    private var palette: ThemePalette { taskManager.themePalette }
    
    var body: some View {
        InfoSheet(title: "Keyboard Shortcuts") {
            VStack(alignment: .leading, spacing: 6) {
                // Input
                sectionHeader("Input")
                shortcutRow("↩", "Commit task")
                shortcutRow("⇧↩", "Add subtask to selected")
                shortcutRow("⇥", "Accept suggestion")
                shortcutRow("⇧⇥", "Toggle input/list focus")
                
                // Navigation
                sectionHeader("Navigation")
                shortcutRow("↑ / ↓", "Navigate tasks")
                shortcutRow("→", "Expand parent")
                shortcutRow("←", "Collapse parent")
                
                // Selection
                sectionHeader("Selection")
                shortcutRow("⇧↑ / ⇧↓", "Extend selection")
                shortcutRow("⌘A", "Select all tasks")
                shortcutRow("Esc", "Clear selection")
                
                // Actions
                sectionHeader("Actions")
                shortcutRow("⌘↩", "Toggle completion")
                shortcutRow("⌘D", "Duplicate selected")
                shortcutRow("⌘C", "Copy selected tasks")
                shortcutRow("⌘V", "Paste under selected")
                shortcutRow("⌘⌫", "Delete selected")
                shortcutRow("⌘L", "Lock/unlock thread")
                shortcutRow("M + ↑/↓", "Move selected task")
                
                // Window
                sectionHeader("Window")
                shortcutRow("⌘P", "Pin/unpin window")
            }
        }
    }
    
    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .taskrFont(.callout)
                .fontWeight(.medium)
                .foregroundColor(palette.accentColor)
                .frame(width: 70, alignment: .trailing)
            
            Text(description)
                .taskrFont(.callout)
                .foregroundColor(palette.primaryTextColor)
            
            Spacer()
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .taskrFont(.caption)
            .fontWeight(.semibold)
            .foregroundColor(palette.secondaryTextColor)
            .padding(.top, 6)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Task.self, TaskTemplate.self, configurations: config)
    let taskManager = TaskManager(modelContext: container.mainContext)
    
    KeyboardShortcutsView()
        .environmentObject(taskManager)
}
