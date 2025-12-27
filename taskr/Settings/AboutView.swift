import SwiftUI

struct AboutView: View {
    @EnvironmentObject var taskManager: TaskManager
    
    private var palette: ThemePalette { taskManager.themePalette }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "Version \(version) (\(build))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Taskr")
                        .taskrFont(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.primaryTextColor)
                    
                    Text(appVersion)
                        .taskrFont(.caption)
                        .foregroundColor(palette.secondaryTextColor)
                }
            }
            
            Divider()
            
            // Description
            Text("A simple, elegant task manager for your menu bar.")
                .taskrFont(.body)
                .foregroundColor(palette.primaryTextColor)
            
            // Links Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Links")
                    .taskrFont(.headline)
                    .foregroundColor(palette.primaryTextColor)
                
                // TODO: Replace these placeholder URLs with your actual links
                AboutLinkRow(
                    icon: "globe",
                    title: "b0n3.net",
                    url: "https://b0n3.net",
                    palette: palette
                )
                
                AboutLinkRow(
                    icon: "heart.fill",
                    title: "Buy me a coffee",
                    url: "https://ko-fi.com/b0n3",
                    palette: palette
                )
                
                AboutLinkRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Twitter / X",
                    url: "https://x.com/bonecrisis",
                    palette: palette
                )
                
                AboutLinkRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "GitHub",
                    url: "https://github.com/sudo-b0n3/taskr",
                    palette: palette
                )
            }
            
            Divider()
            
            // Credits / Copyright
            Text("© 2025 b0n3. All rights reserved.")
                .taskrFont(.caption)
                .foregroundColor(palette.secondaryTextColor)
        }
        .padding(20)
        .frame(width: 280)
        .background(palette.backgroundColor)
    }
}

struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String
    let palette: ThemePalette
    
    var body: some View {
        Button(action: {
            if let linkURL = URL(string: url) {
                NSWorkspace.shared.open(linkURL)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(palette.accentColor)
                
                Text(title)
                    .taskrFont(.body)
                    .foregroundColor(palette.primaryTextColor)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .taskrFont(.caption)
                    .foregroundColor(palette.secondaryTextColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(palette.controlBackgroundColor.opacity(0.5))
        .cornerRadius(6)
    }
}
