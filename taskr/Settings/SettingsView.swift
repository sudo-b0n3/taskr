import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var launchAtLogin: Bool = false
    @State private var globalHotkeyEnabled: Bool = false
    @State private var hotkeyDescription: String = HotkeyPreferences.load().displayString
    @State private var isRecordingHotkey: Bool = false
    var configuresWindow: Bool = true
    
    @AppStorage(showDockIconPreferenceKey) private var showDockIcon: Bool = false
    @AppStorage(moveCompletedTasksToBottomPreferenceKey) private var moveCompletedTasksToBottom: Bool = false
    @AppStorage(collapseCompletedParentsPreferenceKey) private var collapseCompletedParents: Bool = false
    @AppStorage(menuBarPresentationStylePreferenceKey) private var menuBarStyleRaw: String = MenuBarPresentationStyle.panel.rawValue
    @AppStorage(panelAlignmentPreferenceKey) private var panelAlignmentRaw: String = PanelAlignment.center.rawValue
    
    // We'll use a local binding for launch at login since it involves SMAppService
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                launchAtLogin = newValue
                if newValue {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
        )
    }
    
    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { showDockIcon },
            set: { newValue in
                showDockIcon = newValue
                appDelegate.setDockIconVisibility(show: newValue)
                if newValue {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return "v\(version)"
    }

    var body: some View {
        ZStack {
            // Background
            if taskManager.frostedBackgroundEnabled {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .ignoresSafeArea()
            } else {
                taskManager.themePalette.backgroundColor
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Text("Settings")
                        .taskrFont(.headline)
                        .foregroundColor(taskManager.themePalette.primaryTextColor)
                    Spacer()
                }
                .padding()
                .background(taskManager.frostedBackgroundEnabled ? taskManager.themePalette.headerBackgroundColor.opacity(taskManager.frostedBackgroundLevel.opacity) : taskManager.themePalette.headerBackgroundColor)
                
                Divider()
                    .background(taskManager.themePalette.dividerColor)

                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - General
                        SettingsSection(title: "General", palette: taskManager.themePalette) {
                            SettingsToggle(
                                title: "Launch at Login",
                                isOn: launchAtLoginBinding,
                                helpText: "Automatically start Taskr when you log in.",
                                palette: taskManager.themePalette
                            )
                            
                            SettingsToggle(
                                title: "Show in Dock",
                                isOn: showDockIconBinding,
                                helpText: "Show Taskr in the macOS Dock.",
                                palette: taskManager.themePalette
                            )
                            
                            SettingsToggle(
                                title: "Global Hotkey",
                                isOn: Binding(
                                    get: { globalHotkeyEnabled },
                                    set: { enable in
                                        if appDelegate.enableGlobalHotkey(enable, showAlertIfNotGranted: true) {
                                            globalHotkeyEnabled = enable
                                            UserDefaults.standard.set(enable, forKey: globalHotkeyEnabledPreferenceKey)
                                        } else {
                                            // Revert if failed (e.g. permission denied)
                                            globalHotkeyEnabled = false
                                            UserDefaults.standard.set(false, forKey: globalHotkeyEnabledPreferenceKey)
                                        }
                                    }
                                ),
                                helpText: "Toggle the task list from anywhere.",
                                palette: taskManager.themePalette
                            )
                            
                            HotkeyRecorderRow(
                                currentDescription: hotkeyDescription,
                                isRecording: $isRecordingHotkey,
                                palette: taskManager.themePalette
                            ) { configuration in
                                hotkeyDescription = configuration.displayString
                                appDelegate.updateHotkeyConfiguration(configuration)
                            }
                        }
                        
                        Divider()
                        
                        // MARK: - Behavior
                        SettingsSection(title: "Behavior", palette: taskManager.themePalette) {
                            SettingsPicker(title: "New Task Position", selection: Binding(
                                get: { UserDefaults.standard.bool(forKey: addRootTasksToTopPreferenceKey) ? NewTaskPosition.top : .bottom },
                                set: { UserDefaults.standard.set($0 == .top, forKey: addRootTasksToTopPreferenceKey) }
                            ), palette: taskManager.themePalette) {
                                ForEach(NewTaskPosition.allCases) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            
                            SettingsPicker(title: "New Subtask Position", selection: Binding(
                                get: { UserDefaults.standard.bool(forKey: addSubtasksToTopPreferenceKey) ? NewTaskPosition.top : .bottom },
                                set: { UserDefaults.standard.set($0 == .top, forKey: addSubtasksToTopPreferenceKey) }
                            ), palette: taskManager.themePalette) {
                                ForEach(NewTaskPosition.allCases) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }

                            SettingsToggle(
                                title: "Move Completed Tasks to Bottom",
                                isOn: $moveCompletedTasksToBottom,
                                helpText: "When checked items are completed, send them to the bottom of their current list.",
                                palette: taskManager.themePalette
                            )

                            SettingsToggle(
                                title: "Collapse Completed Parents",
                                isOn: $collapseCompletedParents,
                                helpText: "When a parent task is completed, collapse it automatically.",
                                palette: taskManager.themePalette
                            )
                            
                            SettingsToggle(
                                title: "Clear Inside Completed Parents",
                                isOn: Binding(
                                    get: { UserDefaults.standard.bool(forKey: allowClearingStruckDescendantsPreferenceKey) },
                                    set: { UserDefaults.standard.set($0, forKey: allowClearingStruckDescendantsPreferenceKey) }
                                ),
                                helpText: "Allow clearing completed tasks even if their parent is completed.",
                                palette: taskManager.themePalette
                            )
                            
                            SettingsToggle(
                                title: "Skip Hidden Completed Tasks",
                                isOn: Binding(
                                    get: { UserDefaults.standard.object(forKey: skipClearingHiddenDescendantsPreferenceKey) as? Bool ?? true },
                                    set: { UserDefaults.standard.set($0, forKey: skipClearingHiddenDescendantsPreferenceKey) }
                                ),
                                helpText: "Don't clear completed tasks that are hidden inside collapsed parents.",
                                palette: taskManager.themePalette
                            )
                        }
                        
                        Divider()
                        
                        // MARK: - Appearance
                        SettingsSection(title: "Appearance", palette: taskManager.themePalette) {
                            SettingsPicker(title: "Theme", selection: Binding(
                                get: { taskManager.selectedTheme },
                                set: { taskManager.setTheme($0) }
                            ), palette: taskManager.themePalette) {
                                ForEach(AppTheme.allCases, id: \.self) { theme in
                                    Text(theme.rawValue.capitalized).tag(theme)
                                }
                            }
                            
                            SettingsSlider(
                                title: "Font Size",
                                value: Binding(
                                    get: { taskManager.fontScale },
                                    set: { taskManager.setFontScale($0) }
                                ),
                                range: TaskManager.fontScaleRange,
                                step: TaskManager.fontScaleStep,
                                palette: taskManager.themePalette,
                                defaultValue: 1.0
                            )
                            
                            SettingsPicker(title: "Menu Bar Icon", selection: Binding(
                                get: {
                                    let name = UserDefaults.standard.string(forKey: menuBarIconPreferenceKey) ?? ""
                                    return MenuBarIcon(rawValue: name) ?? .defaultIcon
                                },
                                set: { icon in
                                    UserDefaults.standard.set(icon.rawValue, forKey: menuBarIconPreferenceKey)
                                    appDelegate.updateStatusItemIcon(systemSymbolName: icon.systemName)
                                }
                            ), palette: taskManager.themePalette) {
                                ForEach(MenuBarIcon.allCases) { icon in
                                    Text(icon.displayName).tag(icon)
                                }
                            }
                            
                            SettingsPicker(title: "Menu Bar Style", selection: Binding(
                                get: {
                                    let raw = UserDefaults.standard.string(forKey: menuBarPresentationStylePreferenceKey) ?? ""
                                    return MenuBarPresentationStyle(rawValue: raw) ?? .defaultStyle
                                },
                                set: { style in
                                    UserDefaults.standard.set(style.rawValue, forKey: menuBarPresentationStylePreferenceKey)
                                    appDelegate.resetMenuBarPresentation()
                                }
                            ), palette: taskManager.themePalette) {
                                ForEach(MenuBarPresentationStyle.allCases) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            
                            // Panel Alignment option - only shown when panel style is selected
                            if menuBarStyleRaw == MenuBarPresentationStyle.panel.rawValue {
                                SettingsPicker(title: "Panel Alignment", selection: Binding(
                                    get: { PanelAlignment(rawValue: panelAlignmentRaw) ?? .center },
                                    set: { panelAlignmentRaw = $0.rawValue }
                                ), palette: taskManager.themePalette) {
                                    ForEach(PanelAlignment.allCases) { alignment in
                                        Text(alignment.displayName).tag(alignment)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                            
                            SettingsToggle(
                                title: "Frosted Background",
                                isOn: Binding(
                                    get: { taskManager.frostedBackgroundEnabled },
                                    set: { taskManager.setFrostedBackgroundEnabled($0) }
                                ),
                                helpText: "Enable a translucent background effect.",
                                palette: taskManager.themePalette
                            )
                            
                            if taskManager.frostedBackgroundEnabled {
                                SettingsPicker(title: "Transparency Level", selection: Binding(
                                    get: { taskManager.frostedBackgroundLevel },
                                    set: { taskManager.setFrostedBackgroundLevel($0) }
                                ), palette: taskManager.themePalette) {
                                    ForEach(TaskManager.FrostLevel.allCases) { level in
                                        Text(level.displayName).tag(level)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                            
                            SettingsToggle(
                                title: "Align Checkbox to Top",
                                isOn: Binding(
                                    get: { UserDefaults.standard.object(forKey: checkboxTopAlignedPreferenceKey) as? Bool ?? true },
                                    set: { UserDefaults.standard.set($0, forKey: checkboxTopAlignedPreferenceKey) }
                                ),
                                helpText: "Align checkbox with the first line of text for multi-line tasks.",
                                palette: taskManager.themePalette
                            )
                        }
                        
                        Divider()
                        
                        // MARK: - Animations
                        SettingsSection(title: "Animations", palette: taskManager.themePalette) {
                            SettingsToggle(
                                title: "Enable Animations",
                                isOn: Binding(
                                    get: { taskManager.animationsMasterEnabled },
                                    set: { taskManager.setAnimationsMasterEnabled($0) }
                                ),
                                palette: taskManager.themePalette
                            )
                            
                            if taskManager.animationsMasterEnabled {
                                VStack(alignment: .leading, spacing: 10) {
                                    SettingsToggle(
                                        title: "List Changes",
                                        isOn: Binding(
                                            get: { taskManager.listAnimationsEnabled },
                                            set: { taskManager.setListAnimationsEnabled($0) }
                                        ),
                                        palette: taskManager.themePalette
                                    )
                                    .padding(.leading, 20)
                                    
                                    SettingsToggle(
                                        title: "Expand/Collapse",
                                        isOn: Binding(
                                            get: { taskManager.collapseAnimationsEnabled },
                                            set: { taskManager.setCollapseAnimationsEnabled($0) }
                                        ),
                                        palette: taskManager.themePalette
                                    )
                                    .padding(.leading, 20)
                                    
                                    SettingsToggle(
                                        title: "Completion",
                                        isOn: Binding(
                                            get: { taskManager.animationManager.completionAnimationsEnabled },
                                            set: { taskManager.setCompletionAnimationsEnabled($0) }
                                        ),
                                        palette: taskManager.themePalette
                                    )
                                    .padding(.leading, 20)
                                }
                            }
                        }
                        
                        Divider()
                        
                        SettingsSection(title: "Data", palette: taskManager.themePalette) {
                            HStack {
                                Text("Data Management")
                                    .taskrFont(.body)
                                    .foregroundColor(taskManager.themePalette.primaryTextColor)
                                Spacer()
                                Button("Export Tasks...") {
                                    exportTasks()
                                }
                                Button("Import Tasks...") {
                                    importTasks()
                                }
                            }
                            
                            Divider().padding(.vertical, 5)
                            
                            HStack {
                                Text("Reset")
                                    .taskrFont(.body)
                                    .foregroundColor(taskManager.themePalette.primaryTextColor)
                                Spacer()
                                Button("Re-do Setup") {
                                    UserDefaults.standard.set(false, forKey: "hasCompletedSetup")
                                }
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text(appVersion)
                                .taskrFont(.caption)
                                .foregroundColor(taskManager.themePalette.secondaryTextColor)
                            
                            Spacer()
                            
                            Button("Quit Taskr") {
                                NSApp.terminate(nil)
                            }
                            .keyboardShortcut("q", modifiers: [.command])
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    .padding(.vertical)
                }
                .background(taskManager.frostedBackgroundEnabled ? taskManager.themePalette.backgroundColor.opacity(taskManager.frostedBackgroundLevel.opacity - 0.05) : taskManager.themePalette.backgroundColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if configuresWindow {
                WindowConfigurator(
                    autosaveName: "TaskrSettingsWindow",
                    initialSize: NSSize(width: 400, height: 600),
                    palette: taskManager.themePalette,
                    frosted: taskManager.frostedBackgroundEnabled,
                    frostOpacity: taskManager.frostedBackgroundLevel.opacity,
                    usesSystemAppearance: taskManager.selectedTheme == .system,
                    allowBackgroundDrag: false
                )
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            globalHotkeyEnabled = UserDefaults.standard.bool(forKey: globalHotkeyEnabledPreferenceKey)
            hotkeyDescription = HotkeyPreferences.load().displayString
        }
        .alert("Taskr", isPresented: $showAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(alertMessage ?? "Unknown error")
        })
        .environment(\.taskrFontScale, taskManager.fontScale)
        .environment(\.font, TaskrTypography.scaledFont(for: .body, scale: taskManager.fontScale))
    }
    
    @State private var alertMessage: String?
    @State private var showAlert: Bool = false

    private func exportTasks() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "taskr_backup.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try taskManager.exportUserBackup(to: url)
            } catch {
                alertMessage = "Export failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func importTasks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try taskManager.importUserBackup(from: url)
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
