// taskr/taskr/ContentView.swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var controlActiveState

    // When true, this view is hosted in a standalone window (not popover)
    var isStandalone: Bool = false

    enum DisplayedView {
        case tasks, templates, settings
    }
    @State private var currentView: DisplayedView = .tasks

    var body: some View {
        Group {
            if isStandalone {
                // Standalone window: place header in the titlebar safe area for consistent transparency
                VStack(spacing: 0) {
                    headerBar
                        .background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                    contentArea
                }
            } else {
                // Popover: keep inline header and divider
                VStack(spacing: 0) {
                    headerBar
                        .background(Color(NSColor.windowBackgroundColor))
                    Divider()
                    contentArea
                }
            }
        }
        // Fixed size only for popover presentation
        .frame(width: isStandalone ? nil : 380, height: isStandalone ? nil : 450)
        .onAppear {
            if isStandalone {
                appDelegate.standaloneWindowAppeared()
            }
        }
        .onDisappear {
            if isStandalone {
                appDelegate.standaloneWindowDisappeared()
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 0) {
            Button(action: { currentView = .tasks }) {
                Text("Tasks").padding(.vertical, 8).padding(.horizontal, 12).frame(maxWidth: .infinity).contentShape(Rectangle())
                    .foregroundColor(currentView == .tasks ? .accentColor : .primary)
            }.buttonStyle(PlainButtonStyle())
            Divider().frame(height: 20)
            Button(action: { currentView = .templates }) {
                Text("Templates").padding(.vertical, 8).padding(.horizontal, 12).frame(maxWidth: .infinity).contentShape(Rectangle())
                    .foregroundColor(currentView == .templates ? .accentColor : .primary)
            }.buttonStyle(PlainButtonStyle())
            Divider().frame(height: 20)
            Button(action: { currentView = .settings }) {
                Image(systemName: "gearshape.fill").foregroundColor(currentView == .settings ? .accentColor : .primary)
                    .padding(.vertical, 8).frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(PlainButtonStyle()).frame(width: 40)

            // Subtle expand button to open full window (shown only in popover mode)
            if !isStandalone {
                Divider().frame(height: 20)
                Button(action: {
                    openWindow(id: "MainWindow")
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .help("Open Window")
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 28)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(isStandalone ? Color.clear : Color(NSColor.windowBackgroundColor))
    }

    private var contentArea: some View {
        Group {
            switch currentView {
            case .tasks:
                TaskView()
            case .templates:
                TemplateView()
            case .settings:
                SettingsView(
                    updateIconAction: appDelegate.updateStatusItemIcon,
                    setDockIconVisibilityAction: appDelegate.setDockIconVisibility,
                    enableGlobalHotkeyAction: { enable in
                        return appDelegate.enableGlobalHotkey(enable, showAlertIfNotGranted: true)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)
        let appDelegate = AppDelegate()

        let task1 = Task(name: "Preview Task in Content", isTemplateComponent: false)
        container.mainContext.insert(task1)

        return ContentView()
            .environmentObject(taskManager)
            .modelContainer(container)
            .environmentObject(appDelegate)
    }
}
