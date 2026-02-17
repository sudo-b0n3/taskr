// taskr/taskr/ContentView.swift
import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @EnvironmentObject var taskManager: TaskManager
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var controlActiveState
    
    @AppStorage("hasCompletedSetup") var hasCompletedSetup: Bool = false

    // When true, this view is hosted in a standalone window (not popover)
    var isStandalone: Bool = false

    enum DisplayedView {
        case tasks, templates, tags, settings
    }
    @State private var currentView: DisplayedView = .tasks

    private var palette: ThemePalette { taskManager.themePalette }
    private var headerBackground: Color {
        let base = palette.headerBackgroundColor
        return taskManager.frostedBackgroundEnabled ? base.opacity(taskManager.frostedBackgroundLevel.opacity) : base
    }
    private var headerLeadingPadding: CGFloat { isStandalone ? 72 : 8 }
    private var headerTopPadding: CGFloat { isStandalone ? 16 : 8 }
    private var titlebarFillHeight: CGFloat { isStandalone ? 54 : 0 }
    private var contentBackground: Color {
        let base = palette.backgroundColor
        return taskManager.frostedBackgroundEnabled ? base.opacity(taskManager.frostedBackgroundLevel.opacity - 0.05) : base
    }

    var body: some View {
        ZStack {
            Group {
                if isStandalone {
                    // Standalone window: let the header share space with the window controls
                    VStack(spacing: 0) {
                        headerBar
                            .background(headerBackground)
                        Divider()
                            .background(palette.dividerColor)
                        contentArea
                    }
                } else {
                    // Popover: keep inline header and divider
                    VStack(spacing: 0) {
                        headerBar
                            .background(headerBackground)
                        Divider()
                            .background(palette.dividerColor)
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
            .background(rootBackground)
            .background(alignment: .top) {
                if isStandalone {
                    headerBackground
                        .frame(height: titlebarFillHeight)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .preferredColorScheme(taskManager.selectedTheme.preferredColorScheme)
            .tint(palette.accentColor)
            .ignoresSafeArea(.container, edges: isStandalone ? .top : [])
            
            if !hasCompletedSetup {
                SetupView(isPresented: Binding(
                    get: { !hasCompletedSetup },
                    set: { if !$0 { hasCompletedSetup = true } }
                ))
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onChange(of: hasCompletedSetup) { _, newValue in
            if newValue {
                currentView = .tasks
            }
        }
        .onChange(of: currentView) { _, _ in
            endActiveEditingSession()
            taskManager.setTaskInputFocused(false)
        }
        .environment(\.taskrFontScale, taskManager.fontScale)
        .environment(\.font, TaskrTypography.scaledFont(for: .body, scale: taskManager.fontScale))
    }

    private var headerBar: some View {
        let hoverAnimEnabled = taskManager.animationManager.effectiveHoverHighlightsEnabled
        let pinAnimEnabled = taskManager.animationManager.effectivePinRotationEnabled
        return HStack(spacing: 0) {
            // Pin button for always-on-top
            Button(action: { appDelegate.isWindowPinned.toggle() }) {
                Image(systemName: appDelegate.isWindowPinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundColor(appDelegate.isWindowPinned ? palette.accentColor : palette.primaryTextColor)
                    .rotationEffect(.degrees(appDelegate.isWindowPinned ? -45 : 0))
                    .animation(pinAnimEnabled ? .easeInOut(duration: 0.2) : .none, value: appDelegate.isWindowPinned)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HeaderButtonStyle(palette: palette, animationsEnabled: hoverAnimEnabled))
            .accessibilityIdentifier("HeaderPinButton")
            .frame(width: 40)
            .help(appDelegate.isWindowPinned ? "Unpin Window" : "Pin Window on Top")
            Divider().frame(height: 20).background(palette.dividerColor)
            Button(action: handleTasksButton) {
                Text("Tasks").padding(.vertical, 8).padding(.horizontal, 12).frame(maxWidth: .infinity).contentShape(Rectangle())
                    .foregroundColor(currentView == .tasks ? palette.accentColor : palette.primaryTextColor)
            }
            .buttonStyle(HeaderButtonStyle(palette: palette, animationsEnabled: hoverAnimEnabled))
            .accessibilityIdentifier("HeaderTasksButton")
            Divider().frame(height: 20).background(palette.dividerColor)
            Button(action: { currentView = .templates }) {
                Image(systemName: "list.bullet")
                    .foregroundColor(currentView == .templates ? palette.accentColor : palette.primaryTextColor)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HeaderButtonStyle(palette: palette, animationsEnabled: hoverAnimEnabled))
            .accessibilityIdentifier("HeaderTemplatesButton")
            .help("Templates")
            .frame(width: 40)
            Divider().frame(height: 20).background(palette.dividerColor)
            Button(action: { currentView = .tags }) {
                Image(systemName: "tag.fill")
                    .foregroundColor(currentView == .tags ? palette.accentColor : palette.primaryTextColor)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HeaderButtonStyle(palette: palette, animationsEnabled: hoverAnimEnabled))
            .accessibilityIdentifier("HeaderTagsButton")
            .help("Tags")
            .frame(width: 40)
            Divider().frame(height: 20).background(palette.dividerColor)
            Button(action: { currentView = .settings }) {
                Image(systemName: "gearshape.fill").foregroundColor(currentView == .settings ? palette.accentColor : palette.primaryTextColor)
                    .padding(.vertical, 8).frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(HeaderButtonStyle(palette: palette, animationsEnabled: hoverAnimEnabled))
            .accessibilityIdentifier("HeaderSettingsButton")
            .frame(width: 40)

            // Subtle expand button to open full window (shown only in popover mode)
            if !isStandalone {
                Divider().frame(height: 20).background(palette.dividerColor)
                Button(action: {
                    appDelegate.resetMenuBarPresentation()  // Close popover/panel
                    appDelegate.showMainWindow {
                        openWindow(id: "MainWindow")
                    }
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .help("Open Window")
                        .foregroundColor(palette.primaryTextColor)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HeaderButtonStyle(palette: palette, animationsEnabled: hoverAnimEnabled))
                .frame(width: 28)
            }
        }
        .padding(.leading, headerLeadingPadding)
        .padding(.trailing, 8)
        .padding(.top, headerTopPadding)
        .background(headerBackground)
    }

    private var contentArea: some View {
        ZStack {
            TaskView(isActive: currentView == .tasks)
                .opacity(currentView == .tasks ? 1 : 0)
                .allowsHitTesting(currentView == .tasks)
                .accessibilityHidden(currentView != .tasks)

            TemplateView(isActive: currentView == .templates)
                .opacity(currentView == .templates ? 1 : 0)
                .allowsHitTesting(currentView == .templates)
                .accessibilityHidden(currentView != .templates)

            TagView()
                .opacity(currentView == .tags ? 1 : 0)
                .allowsHitTesting(currentView == .tags)
                .accessibilityHidden(currentView != .tags)

            SettingsView(configuresWindow: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .opacity(currentView == .settings ? 1 : 0)
                .allowsHitTesting(currentView == .settings)
                .accessibilityHidden(currentView != .settings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func handleTasksButton() {
        #if DEBUG
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.option) {
            taskManager.toggleScreenshotDemoMode()
        }
        #endif
        currentView = .tasks
    }

    private var rootBackground: some View {
        Group {
            if taskManager.frostedBackgroundEnabled {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .overlay(contentBackground)
            } else {
                palette.backgroundColor
            }
        }
    }

    private func endActiveEditingSession() {
        if let keyWindow = NSApp.keyWindow {
            keyWindow.makeFirstResponder(nil)
            keyWindow.endEditing(for: nil)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, TaskTag.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)
        let appDelegate = AppDelegate()

        let task1 = Task(name: "Preview Task in Content", isTemplateComponent: false)
        container.mainContext.insert(task1)

        return ContentView()
            .environmentObject(taskManager)
            .environmentObject(taskManager.inputState)
            .environmentObject(taskManager.selectionManager)
            .modelContainer(container)
            .environmentObject(appDelegate)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct HeaderButtonStyle: ButtonStyle {
    let palette: ThemePalette
    var animationsEnabled: Bool = true
    @State private var isHovering: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering || configuration.isPressed ? palette.hoverBackgroundColor.opacity(0.5) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(animationsEnabled ? .easeOut(duration: 0.1) : .none, value: isHovering)
            .animation(animationsEnabled ? .easeOut(duration: 0.1) : .none, value: configuration.isPressed)
    }
}
