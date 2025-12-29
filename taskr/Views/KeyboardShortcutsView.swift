import SwiftUI
import SwiftData

/// A compact, readable view showing all keyboard shortcuts
struct KeyboardShortcutsView: View {
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .taskrFont(.headline)
                    .foregroundColor(taskManager.themePalette.primaryTextColor)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(taskManager.themePalette.secondaryTextColor)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Shortcuts list
            VStack(alignment: .center, spacing: 6) {
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
            }
            
            Spacer()
        }
        .padding(16)
        .frame(width: 300, height: 480)
        .background {
            if taskManager.frostedBackgroundEnabled {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            } else {
                taskManager.themePalette.backgroundColor
            }
        }
        .environment(\.taskrFontScale, taskManager.fontScale)
        .environment(\.font, TaskrTypography.scaledFont(for: .body, scale: taskManager.fontScale))
    }
    
    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .taskrFont(.callout)
                .fontWeight(.medium)
                .foregroundColor(taskManager.themePalette.accentColor)
                .frame(width: 70, alignment: .trailing)
            
            Text(description)
                .taskrFont(.callout)
                .foregroundColor(taskManager.themePalette.primaryTextColor)
            
            Spacer()
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .taskrFont(.caption)
            .fontWeight(.semibold)
            .foregroundColor(taskManager.themePalette.secondaryTextColor)
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
