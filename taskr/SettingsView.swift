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
    private var palette: ThemePalette { taskManager.themePalette }
    private var checkboxToggleStyle: SettingsCheckboxToggleStyle {
        SettingsCheckboxToggleStyle(palette: palette, animate: preferences.animationsMasterEnabled)
    }

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
                        .toggleStyle(checkboxToggleStyle)
                        .accessibilityLabel(Text("Launch Taskr at login"))
                        .onChange(of: launchAtLoginEnabled) { _, newValue in
                            toggleLaunchAtLogin(enable: newValue)
                        }
                    }
                }

                Divider().background(palette.dividerColor)

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
                        .tint(palette.accentColor)
                        .onChange(of: preferences.selectedIcon) { _, icon in
                            updateIconAction(icon.systemName)
                        }
                    }
                }

                Divider().background(palette.dividerColor)

                SettingsSection(caption: "Change Taskr's appearance using terminal-inspired palettes.") {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Picker(
                            "",
                            selection: Binding(
                                get: { taskManager.selectedTheme },
                                set: { taskManager.setTheme($0) }
                            )
                        ) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 150, maxWidth: 200)
                        .tint(palette.accentColor)
                    }
                }

                Divider().background(palette.dividerColor)

                SettingsSection(caption: "Adds a subtle glass blur behind the window content.") {
                    HStack {
                        Text("Frosted background")
                        Spacer()
                        Toggle(isOn: $preferences.enableFrostedBackground) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .toggleStyle(checkboxToggleStyle)
                        .accessibilityLabel(Text("Frosted background"))
                        .onChange(of: preferences.enableFrostedBackground) { _, newValue in
                            taskManager.setFrostedBackgroundEnabled(newValue)
                        }
                    }
                }

                Divider().background(palette.dividerColor)

                SettingsSection(caption: "Changes to Dock icon visibility may require an app restart.") {
                    HStack {
                        Text("Show App in Dock")
                        Spacer()
                        Toggle(isOn: $preferences.showDockIcon) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .toggleStyle(checkboxToggleStyle)
                        .accessibilityLabel(Text("Show app in Dock"))
                        .onChange(of: preferences.showDockIcon) { _, newValue in
                            setDockIconVisibilityAction(newValue)
                        }
                    }
                }

                Divider().background(palette.dividerColor)

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

                Divider().background(palette.dividerColor)

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
                        .toggleStyle(checkboxToggleStyle)
                        .accessibilityLabel(Text("Enable global hotkey"))
                    }
                }

                Divider().background(palette.dividerColor)

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
                        .tint(palette.accentColor)
                    }
                }

                Divider().background(palette.dividerColor)

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
                        .tint(palette.accentColor)
                    }
                }

                Divider().background(palette.dividerColor)

                SettingsSection(caption: "Fine-tune how lively Taskr feels.") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Enable All Animations")
                            Spacer()
                            Toggle(isOn: $preferences.animationsMasterEnabled) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(checkboxToggleStyle)
                            .accessibilityLabel(Text("Enable all animations"))
                            .onChange(of: preferences.animationsMasterEnabled) { _, newValue in
                                taskManager.setAnimationsMasterEnabled(newValue)
                            }
                        }

                        HStack {
                            Text("Task List Changes")
                            Spacer()
                            Toggle(isOn: $preferences.listAnimationsEnabled) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(checkboxToggleStyle)
                            .accessibilityLabel(Text("Animate task list changes"))
                            .onChange(of: preferences.listAnimationsEnabled) { _, newValue in
                                taskManager.setListAnimationsEnabled(newValue)
                            }
                        }
                        .disabled(!preferences.animationsMasterEnabled)

                        HStack {
                            Text("Expand / Collapse")
                            Spacer()
                            Toggle(isOn: $preferences.collapseAnimationsEnabled) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(checkboxToggleStyle)
                            .accessibilityLabel(Text("Animate expand or collapse transitions"))
                            .onChange(of: preferences.collapseAnimationsEnabled) { _, newValue in
                                taskManager.setCollapseAnimationsEnabled(newValue)
                            }
                        }
                        .disabled(!preferences.animationsMasterEnabled)

                        HStack {
                            Text("Completion Effects")
                            Spacer()
                            Toggle(isOn: $preferences.completionAnimationsEnabled) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(checkboxToggleStyle)
                            .accessibilityLabel(Text("Animate completion effects"))
                        }
                        .disabled(!preferences.animationsMasterEnabled)
                    }
                }

                Divider().background(palette.dividerColor)

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
                        .tint(palette.accentColor)
                    }
                }

                Divider().background(palette.dividerColor)

                SettingsSection(caption: "When clearing, remove completed parents and all subtasks even if subtasks aren't completed.") {
                    HStack {
                        Text("Clear Crossed-out Descendants")
                        Spacer()
                        Toggle(isOn: $preferences.allowClearingStruckDescendants) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .toggleStyle(checkboxToggleStyle)
                        .accessibilityLabel(Text("Clear crossed-out descendants"))
                    }
                }

                Divider().background(palette.dividerColor)

                SettingsSection {
                    HStack {
                        Text(appVersion)
                            .font(.caption)
                            .foregroundColor(palette.secondaryTextColor)
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
        .foregroundColor(palette.primaryTextColor)
        .background(Color.clear)
        .scrollContentBackground(.hidden)
    }

    private func syncState() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        taskManager.setFrostedBackgroundEnabled(preferences.enableFrostedBackground)
        taskManager.setAnimationsMasterEnabled(preferences.animationsMasterEnabled)
        taskManager.setListAnimationsEnabled(preferences.listAnimationsEnabled)
        taskManager.setCollapseAnimationsEnabled(preferences.collapseAnimationsEnabled)
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

private struct SettingsCheckboxToggleStyle: ToggleStyle {
    let palette: ThemePalette
    var animate: Bool = true

    private let circleScale: CGFloat = 0.55
    private let animation: Animation = .easeInOut(duration: 0.16)

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            ZStack {
                Image(systemName: "circle")
                    .foregroundColor(palette.secondaryTextColor)
                Circle()
                    .fill(palette.accentColor)
                    .scaleEffect(configuration.isOn ? circleScale : 0.0001)
                    .animation(animate ? animation : .none, value: configuration.isOn)
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            configuration.label
                .opacity(0)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

private struct SettingsSection<Content: View>: View {
    @EnvironmentObject private var taskManager: TaskManager
    private var palette: ThemePalette { taskManager.themePalette }

    let caption: String?
    let content: Content

    init(
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .foregroundColor(palette.primaryTextColor)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(palette.secondaryTextColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .background(taskManager.themePalette.backgroundColor)
    }
}
