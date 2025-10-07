// taskr/taskr/SettingsView.swift
import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var taskManager: TaskManager
    @StateObject private var preferences = PreferencesStore()

    @State private var launchAtLoginEnabled: Bool = SMAppService.mainApp.status == .enabled

    let updateIconAction: (String) -> Void
    let setDockIconVisibilityAction: (Bool) -> Void
    let enableGlobalHotkeyAction: (Bool) -> Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSection {
                    HStack {
                        Text("Launch Taskr at login")
                        Spacer()
                        Toggle(isOn: $launchAtLoginEnabled) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .onChange(of: launchAtLoginEnabled) { _, newValue in
                            toggleLaunchAtLogin(enable: newValue)
                        }
                    }
                }

                Divider()

                SettingsSection {
                    HStack {
                        Text("Menu Bar Icon")
                        Spacer()
                        Picker("", selection: $preferences.selectedIcon) {
                            ForEach(MenuBarIcon.allCases) { icon in
                                HStack {
                                    Image(systemName: icon.systemName)
                                    Text(icon.displayName)
                                }
                                .tag(icon)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 150, maxWidth: 200)
                        .onChange(of: preferences.selectedIcon) { _, icon in
                            updateIconAction(icon.systemName)
                        }
                    }
                }

                Divider()

                SettingsSection(caption: "Changes to Dock icon visibility may require an app restart.") {
                    HStack {
                        Text("Show App in Dock")
                        Spacer()
                        Toggle(isOn: $preferences.showDockIcon) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .onChange(of: preferences.showDockIcon) { _, newValue in
                            setDockIconVisibilityAction(newValue)
                        }
                    }
                }

                Divider()

                SettingsSection(caption: "Exports your non-template tasks as JSON; import appends to current list.") {
                    HStack {
                        Text("Import / Export Tasks")
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Export…", action: exportTasks)
                            Button("Import…", action: importTasks)
                        }
                    }
                }

                Divider()

                SettingsSection(caption: "Requires Accessibility permission in System Settings.") {
                    HStack {
                        Text("Enable Global Hotkey (⌃⌥N)")
                        Spacer()
                        Toggle(isOn: Binding(
                            get: { preferences.globalHotkeyEnabled },
                            set: { updateGlobalHotkey(to: $0) }
                        )) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                SettingsSection {
                    HStack {
                        Text("New root tasks")
                        Spacer()
                        Picker("", selection: Binding<NewTaskPosition>(
                            get: { preferences.addRootTasksToTop ? .top : .bottom },
                            set: { preferences.addRootTasksToTop = ($0 == .top) }
                        )) {
                            Text("Top").tag(NewTaskPosition.top)
                            Text("Bottom").tag(NewTaskPosition.bottom)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                }

                Divider()

                SettingsSection {
                    HStack {
                        Text("New subtasks")
                        Spacer()
                        Picker("", selection: Binding<NewTaskPosition>(
                            get: { preferences.addSubtasksToTop ? .top : .bottom },
                            set: { preferences.addSubtasksToTop = ($0 == .top) }
                        )) {
                            Text("Top").tag(NewTaskPosition.top)
                            Text("Bottom").tag(NewTaskPosition.bottom)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                }

                Divider()

                SettingsSection {
                    HStack {
                        Text("Enable Completion Animations")
                        Spacer()
                        Toggle(isOn: $preferences.completionAnimationsEnabled) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                SettingsSection {
                    HStack {
                        Text("Checkbox alignment")
                        Spacer()
                        Picker("", selection: $preferences.checkboxTopAligned) {
                            Text("Top").tag(true)
                            Text("Centered").tag(false)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                }

                Divider()

                SettingsSection(caption: "When clearing, remove completed parents and all subtasks even if subtasks aren't completed.") {
                    HStack {
                        Text("Clear Crossed-out Descendants")
                        Spacer()
                        Toggle(isOn: $preferences.allowClearingStruckDescendants) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                SettingsSection {
                    HStack {
                        Text(appVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Quit Taskr") { NSApp.terminate(nil) }
                            .keyboardShortcut("q", modifiers: .command)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.top, 8)
        }
        .onAppear(perform: syncState)
    }

    private func syncState() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func updateGlobalHotkey(to enabled: Bool) {
        if enabled {
            let success = enableGlobalHotkeyAction(true)
            if success {
                preferences.globalHotkeyEnabled = true
            } else {
                preferences.globalHotkeyEnabled = false
                print("SettingsView: Hotkey enabling failed, toggle reverted.")
            }
        } else {
            _ = enableGlobalHotkeyAction(false)
            preferences.globalHotkeyEnabled = false
        }
    }

    private func toggleLaunchAtLogin(enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            print("Failed to update launch at login: \(error)")
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let caption: String?
    let backgroundColor: Color
    let content: Content

    init(
        caption: String? = nil,
        backgroundColor: Color = Color(nsColor: .windowBackgroundColor),
        @ViewBuilder content: () -> Content
    ) {
        self.caption = caption
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }
}

private extension SettingsView {
    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }
}

// MARK: - Import / Export helpers
extension SettingsView {
    @MainActor
    private func exportTasks() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "taskr-tasks.json"
        panel.title = "Export Tasks"
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    do {
                        try taskManager.exportUserTasks(to: url)
                        showAlert(title: "Export Complete", message: "Tasks exported to \(url.lastPathComponent)")
                    } catch {
                        showAlert(title: "Export Failed", message: String(describing: error))
                    }
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try taskManager.exportUserTasks(to: url)
                    showAlert(title: "Export Complete", message: "Tasks exported to \(url.lastPathComponent)")
                } catch {
                    showAlert(title: "Export Failed", message: String(describing: error))
                }
            }
        }
    }

    @MainActor
    private func importTasks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.title = "Import Tasks"
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    do {
                        try taskManager.importUserTasks(from: url)
                        showAlert(title: "Import Complete", message: "Tasks imported from \(url.lastPathComponent)")
                    } catch {
                        showAlert(title: "Import Failed", message: String(describing: error))
                    }
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try taskManager.importUserTasks(from: url)
                    showAlert(title: "Import Complete", message: "Tasks imported from \(url.lastPathComponent)")
                } catch {
                    showAlert(title: "Import Failed", message: String(describing: error))
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)

        return SettingsView(
            updateIconAction: { _ in },
            setDockIconVisibilityAction: { _ in },
            enableGlobalHotkeyAction: { _ in true }
        )
        .modelContainer(container)
        .environmentObject(taskManager)
        .frame(width: 380, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
