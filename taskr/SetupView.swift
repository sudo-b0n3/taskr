import SwiftUI
import ServiceManagement

struct SetupView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var appDelegate: AppDelegate
    @Binding var isPresented: Bool
    
    @State private var launchAtLogin: Bool = false
    @AppStorage(globalHotkeyEnabledPreferenceKey) private var globalHotkeyEnabled: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    private var palette: ThemePalette { taskManager.themePalette }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                if taskManager.frostedBackgroundEnabled {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                        .ignoresSafeArea()
                        .overlay(
                            palette.backgroundColor.opacity(taskManager.frostedBackgroundLevel.opacity)
                                .ignoresSafeArea()
                        )
                } else {
                    palette.backgroundColor
                        .ignoresSafeArea()
                }
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 30) {
                            // Welcome Section
                            welcomeSection
                            
                            Divider().background(palette.dividerColor)
                            
                            // Tutorial Section
                            tutorialSection
                            
                            Divider().background(palette.dividerColor)
                            
                            // Appearance Section
                            appearanceSection
                            
                            Divider().background(palette.dividerColor)
                            
                            // Behavior Section
                            behaviorSection
                            
                            Divider().background(palette.dividerColor)
                            
                            // Templates Section
                            templatesSection
                            
                            Spacer(minLength: 20)
                        }
                        .padding(40)
                    }
                    
                    // Footer
                    HStack {
                        Spacer()
                        
                        Button("Get Started") {
                            completeSetup()
                        }
                        .buttonStyle(PrimaryButtonStyle(palette: palette))
                        .accessibilityLabel("Complete setup and start using Taskr")
                    }
                    .padding(20)
                    .background(palette.headerBackgroundColor.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func completeSetup() {
        withAnimation {
            isPresented = false
        }
    }
    
    // MARK: - Sections
    
    private var welcomeSection: some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
                .foregroundColor(palette.accentColor)
            
            Text("Welcome to Taskr")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(palette.primaryTextColor)
            
            Text("Let's get you set up.")
                .font(.title3)
                .foregroundColor(palette.secondaryTextColor)
        }
        .padding(.top, 20)
    }
    
    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", palette: palette) {
            SettingsPicker(title: "Theme", selection: Binding(
                get: { taskManager.selectedTheme },
                set: { taskManager.setTheme($0) }
            ), palette: palette) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue.capitalized).tag(theme)
                }
            }
            .accessibilityLabel("Theme Picker")
            .accessibilityValue(taskManager.selectedTheme.rawValue.capitalized)
            
            SettingsPicker(title: "Menu Bar Icon", selection: Binding(
                get: {
                    let name = UserDefaults.standard.string(forKey: menuBarIconPreferenceKey) ?? ""
                    return MenuBarIcon(rawValue: name) ?? .defaultIcon
                },
                set: { icon in
                    UserDefaults.standard.set(icon.rawValue, forKey: menuBarIconPreferenceKey)
                    appDelegate.updateStatusItemIcon(systemSymbolName: icon.systemName)
                }
            ), palette: palette) {
                ForEach(MenuBarIcon.allCases) { icon in
                    Text(icon.displayName).tag(icon)
                }
            }
            .accessibilityLabel("Menu Bar Icon Picker")
            
            SettingsToggle(
                title: "Frosted Background",
                isOn: Binding(
                    get: { taskManager.frostedBackgroundEnabled },
                    set: { taskManager.setFrostedBackgroundEnabled($0) }
                ),
                helpText: "Enable a translucent background effect.",
                palette: palette
            )
            .accessibilityLabel("Frosted Background")
            .accessibilityHint("Enable a translucent background effect")
            
            SettingsToggle(
                title: "Enable Animations",
                isOn: Binding(
                    get: { taskManager.animationsMasterEnabled },
                    set: { taskManager.setAnimationsMasterEnabled($0) }
                ),
                palette: palette
            )
            .accessibilityLabel("Enable Animations")
            .accessibilityHint("Toggle animations throughout the app")
        }
    }
    
    private var behaviorSection: some View {
        SettingsSection(title: "Behavior", palette: palette) {
            SettingsToggle(
                title: "Launch at Login",
                isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                                launchAtLogin = true
                            } else {
                                try SMAppService.mainApp.unregister()
                                launchAtLogin = false
                            }
                        } catch {
                            errorMessage = "Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                            showErrorAlert = true
                            // Revert to actual state
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                ),
                helpText: "Automatically start Taskr when you log in.",
                palette: palette
            )
            .accessibilityLabel("Launch at Login")
            .accessibilityHint("Automatically start Taskr when you log in")
            
            SettingsToggle(
                title: "Show in Dock",
                isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: showDockIconPreferenceKey) },
                    set: { show in
                        UserDefaults.standard.set(show, forKey: showDockIconPreferenceKey)
                        appDelegate.setDockIconVisibility(show: show)
                        if show {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                ),
                helpText: "Keep Taskr in your Dock for easy access.",
                palette: palette
            )
            .accessibilityLabel("Show in Dock")
            .accessibilityHint("Keep Taskr visible in your Dock for easy access")
            
            SettingsToggle(
                title: "Global Hotkey (⌃⌥N)",
                isOn: Binding(
                    get: { globalHotkeyEnabled },
                    set: { enable in
                        let success = appDelegate.enableGlobalHotkey(enable, showAlertIfNotGranted: true)
                        // Only update if successful or if disabling
                        if success || !enable {
                            globalHotkeyEnabled = enable
                        }
                    }
                ),
                helpText: "Toggle the task list from anywhere.",
                palette: palette
            )
            .accessibilityLabel("Global Hotkey")
            .accessibilityHint("Press Control Option N to toggle the task list from anywhere")
            
            SettingsPicker(title: "New Task Position", selection: Binding(
                get: { UserDefaults.standard.bool(forKey: addRootTasksToTopPreferenceKey) ? NewTaskPosition.top : .bottom },
                set: { UserDefaults.standard.set($0 == .top, forKey: addRootTasksToTopPreferenceKey) }
            ), palette: palette) {
                ForEach(NewTaskPosition.allCases) { position in
                    Text(position.displayName).tag(position)
                }
            }
            .accessibilityLabel("New Task Position Picker")
        }
    }
    
    private var templatesSection: some View {
        SettingsSection(title: "Templates", palette: palette) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 24))
                    .foregroundColor(palette.accentColor)
                
                Text("Templates allow you to create reusable lists for recurring workflows. You can manage them in the Templates tab.")
                    .font(.body)
                    .foregroundColor(palette.secondaryTextColor)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var tutorialSection: some View {
        SettingsSection(title: "Quick Start", palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                TutorialRow(icon: "text.cursor", title: "Create Tasks", description: "Just type and press Enter.", palette: palette)
                TutorialRow(icon: "arrow.turn.down.right", title: "Subtasks", description: "Use slash syntax: Parent/Child/Subtask", palette: palette)
                TutorialRow(icon: "keyboard", title: "Navigation", description: "Use ↑ ↓ to select, Tab to complete.", palette: palette)
            }
            .padding(.vertical, 4)
        }
    }
}

struct TutorialRow: View {
    let icon: String
    let title: String
    let description: String
    let palette: ThemePalette
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(palette.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(palette.primaryTextColor)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(palette.secondaryTextColor)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let palette: ThemePalette
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(palette.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
