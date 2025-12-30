import SwiftUI

/// A standardized sheet wrapper for info panels like Keyboard Shortcuts and About.
/// Auto-sizes to content with consistent styling and a close button.
struct InfoSheet<Content: View>: View {
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    private var palette: ThemePalette { taskManager.themePalette }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            HStack {
                Text(title)
                    .taskrFont(.headline)
                    .foregroundColor(palette.primaryTextColor)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(palette.secondaryTextColor)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(palette.headerBackgroundColor)
            
            Divider()
                .background(palette.dividerColor)
            
            // Content - scrollable
            ScrollView {
                content
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 500)
        .background(palette.backgroundColor)
        .environment(\.taskrFontScale, taskManager.fontScale)
        .environment(\.font, TaskrTypography.scaledFont(for: .body, scale: taskManager.fontScale))
    }
}
