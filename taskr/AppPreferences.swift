// taskr/taskr/AppPreferences.swift
import Foundation
import Combine
import AppKit
import Carbon

// --- Keys ---
let menuBarIconPreferenceKey = "menuBarIconPreference"
let showDockIconPreferenceKey = "showDockIconPreference"
let globalHotkeyEnabledPreferenceKey = "globalHotkeyEnabledPreference"
let globalHotkeyKeyCodePreferenceKey = "globalHotkeyKeyCodePreference"
let globalHotkeyModifiersPreferenceKey = "globalHotkeyModifiersPreference"
// Deprecated: replaced by separate toggles for root vs subtasks
let newTaskPositionPreferenceKey = "newTaskPositionPreference"
// New keys for insertion preferences
let addRootTasksToTopPreferenceKey = "addRootTasksToTopPreference"
let addSubtasksToTopPreferenceKey = "addSubtasksToTopPreference"
let collapsedTaskIDsPreferenceKey = "collapsedTaskIDsPreference" // Persist collapsed state
let completionAnimationsEnabledPreferenceKey = "completionAnimationsEnabledPreference" // Toggle subtle completion animations
let allowClearingStruckDescendantsPreferenceKey = "allowClearingStruckDescendantsPreference" // Allow clearing children under completed parents
let skipClearingHiddenDescendantsPreferenceKey = "skipClearingHiddenDescendantsPreference" // Avoid clearing completed descendants hidden under collapsed incomplete parents
let normalizedDisplayOrderMigrationDoneKey = "normalizedDisplayOrderMigrationDone"
let checkboxTopAlignedPreferenceKey = "checkboxTopAlignedPreference" // Align checkbox with first line
let moveCompletedTasksToBottomPreferenceKey = "moveCompletedTasksToBottomPreference" // Move completed tasks to end of their sibling list
let selectedThemePreferenceKey = "selectedThemePreference" // Active visual theme
let frostedBackgroundPreferenceKey = "frostedBackgroundPreference" // Enable frosted glass background
let frostedBackgroundLevelPreferenceKey = "frostedBackgroundLevelPreference" // Frost intensity level
let listAnimationsEnabledPreferenceKey = "listAnimationsEnabledPreference" // Toggle task list insert/delete animations
let animationsMasterEnabledPreferenceKey = "animationsMasterEnabledPreference" // Global animation master switch
let collapseAnimationsEnabledPreferenceKey = "collapseAnimationsEnabledPreference" // Toggle expand/collapse transitions
let fontScalePreferenceKey = "fontScalePreference" // Adjust overall text scale

// Defaults
let defaultHotkeyKeyCode: UInt16 = UInt16(kVK_ANSI_N)
let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.control, .option]

// Screenshot automation coordination artifacts
let screenshotAutomationConfigFilename = "taskr_screenshot_config.json"

// --- Enums ---

// Icon Choices
enum MenuBarIcon: String, CaseIterable, Identifiable {
    // ... (cases remain the same) ...
    case emptySet = "slash.circle"
    case listBullet = "list.bullet"
    case checkmarkCircle = "checkmark.circle"
    case checkmarkCircleFill = "checkmark.circle.fill"
    case circle = "circle"
    case appWindow = "app.badge.checkmark"
    case circleGrid = "circle.grid.2x2"

    var id: String { self.rawValue }
    var systemName: String { self.rawValue }
    var displayName: String {
        switch self {
        case .emptySet: return "Empty Set (∅)"
        case .listBullet: return "List Icon"
        case .checkmarkCircle: return "Checkmark Circle"
        case .checkmarkCircleFill: return "Checkmark Circle (Filled)"
        case .circle: return "Empty Circle"
        case .appWindow: return "App Window Icon"
        case .circleGrid: return "Grid Icon"
        }
    }
    static var defaultIcon: MenuBarIcon = .emptySet
}

// Legacy enum kept for backward compatibility in case any preview/tests reference it
enum NewTaskPosition: String, CaseIterable, Identifiable {
    case top = "top"
    case bottom = "bottom"

    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .top: return "Top of List"
        case .bottom: return "Bottom of List"
        }
    }
    static var defaultPosition: NewTaskPosition = .top
}

// Centralized bridge for UserDefaults-backed preferences so views bind consistently.
final class PreferencesStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var selectedIcon: MenuBarIcon {
        didSet {
            guard oldValue != selectedIcon else { return }
            defaults.set(selectedIcon.rawValue, forKey: menuBarIconPreferenceKey)
        }
    }

    @Published var showDockIcon: Bool {
        didSet {
            guard oldValue != showDockIcon else { return }
            defaults.set(showDockIcon, forKey: showDockIconPreferenceKey)
        }
    }

    @Published var globalHotkeyEnabled: Bool {
        didSet {
            guard oldValue != globalHotkeyEnabled else { return }
            defaults.set(globalHotkeyEnabled, forKey: globalHotkeyEnabledPreferenceKey)
        }
    }

    @Published var addRootTasksToTop: Bool {
        didSet {
            guard oldValue != addRootTasksToTop else { return }
            defaults.set(addRootTasksToTop, forKey: addRootTasksToTopPreferenceKey)
        }
    }

    @Published var addSubtasksToTop: Bool {
        didSet {
            guard oldValue != addSubtasksToTop else { return }
            defaults.set(addSubtasksToTop, forKey: addSubtasksToTopPreferenceKey)
        }
    }

    @Published var completionAnimationsEnabled: Bool {
        didSet {
            guard oldValue != completionAnimationsEnabled else { return }
            defaults.set(completionAnimationsEnabled, forKey: completionAnimationsEnabledPreferenceKey)
        }
    }

    @Published var allowClearingStruckDescendants: Bool {
        didSet {
            guard oldValue != allowClearingStruckDescendants else { return }
            defaults.set(allowClearingStruckDescendants, forKey: allowClearingStruckDescendantsPreferenceKey)
        }
    }

    @Published var skipClearingHiddenDescendants: Bool {
        didSet {
            guard oldValue != skipClearingHiddenDescendants else { return }
            defaults.set(skipClearingHiddenDescendants, forKey: skipClearingHiddenDescendantsPreferenceKey)
        }
    }

    @Published var checkboxTopAligned: Bool {
        didSet {
            guard oldValue != checkboxTopAligned else { return }
            defaults.set(checkboxTopAligned, forKey: checkboxTopAlignedPreferenceKey)
        }
    }

    @Published var enableFrostedBackground: Bool {
        didSet {
            guard oldValue != enableFrostedBackground else { return }
            defaults.set(enableFrostedBackground, forKey: frostedBackgroundPreferenceKey)
        }
    }

    @Published var listAnimationsEnabled: Bool {
        didSet {
            guard oldValue != listAnimationsEnabled else { return }
            defaults.set(listAnimationsEnabled, forKey: listAnimationsEnabledPreferenceKey)
        }
    }

    @Published var animationsMasterEnabled: Bool {
        didSet {
            guard oldValue != animationsMasterEnabled else { return }
            defaults.set(animationsMasterEnabled, forKey: animationsMasterEnabledPreferenceKey)
        }
    }

    @Published var collapseAnimationsEnabled: Bool {
        didSet {
            guard oldValue != collapseAnimationsEnabled else { return }
            defaults.set(collapseAnimationsEnabled, forKey: collapseAnimationsEnabledPreferenceKey)
        }
    }

    @Published var moveCompletedTasksToBottom: Bool {
        didSet {
            guard oldValue != moveCompletedTasksToBottom else { return }
            defaults.set(moveCompletedTasksToBottom, forKey: moveCompletedTasksToBottomPreferenceKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.seedDefaultsIfNeeded(in: defaults)

        selectedIcon = MenuBarIcon(
            rawValue: defaults.string(forKey: menuBarIconPreferenceKey) ?? ""
        ) ?? MenuBarIcon.defaultIcon
        showDockIcon = defaults.bool(forKey: showDockIconPreferenceKey)
        globalHotkeyEnabled = defaults.bool(forKey: globalHotkeyEnabledPreferenceKey)
        addRootTasksToTop = defaults.bool(forKey: addRootTasksToTopPreferenceKey)
        addSubtasksToTop = defaults.bool(forKey: addSubtasksToTopPreferenceKey)
        completionAnimationsEnabled = defaults.object(forKey: completionAnimationsEnabledPreferenceKey) as? Bool ?? true
        allowClearingStruckDescendants = defaults.bool(forKey: allowClearingStruckDescendantsPreferenceKey)
        skipClearingHiddenDescendants = defaults.object(forKey: skipClearingHiddenDescendantsPreferenceKey) as? Bool ?? true
        checkboxTopAligned = defaults.object(forKey: checkboxTopAlignedPreferenceKey) as? Bool ?? true
        enableFrostedBackground = defaults.bool(forKey: frostedBackgroundPreferenceKey)
        listAnimationsEnabled = defaults.object(forKey: listAnimationsEnabledPreferenceKey) as? Bool ?? true
        animationsMasterEnabled = defaults.object(forKey: animationsMasterEnabledPreferenceKey) as? Bool ?? true
        collapseAnimationsEnabled = defaults.object(forKey: collapseAnimationsEnabledPreferenceKey) as? Bool ?? true
        moveCompletedTasksToBottom = defaults.object(forKey: moveCompletedTasksToBottomPreferenceKey) as? Bool ?? false
    }

    private static func seedDefaultsIfNeeded(in defaults: UserDefaults) {
        if defaults.object(forKey: addRootTasksToTopPreferenceKey) == nil {
            defaults.set(true, forKey: addRootTasksToTopPreferenceKey)
        }
        if defaults.object(forKey: addSubtasksToTopPreferenceKey) == nil {
            defaults.set(false, forKey: addSubtasksToTopPreferenceKey)
        }
        if defaults.object(forKey: globalHotkeyKeyCodePreferenceKey) == nil {
            defaults.set(Int(defaultHotkeyKeyCode), forKey: globalHotkeyKeyCodePreferenceKey)
        }
        if defaults.object(forKey: globalHotkeyModifiersPreferenceKey) == nil {
            defaults.set(Int(defaultHotkeyModifiers.rawValue), forKey: globalHotkeyModifiersPreferenceKey)
        }
        if defaults.object(forKey: completionAnimationsEnabledPreferenceKey) == nil {
            defaults.set(true, forKey: completionAnimationsEnabledPreferenceKey)
        }
        if defaults.object(forKey: skipClearingHiddenDescendantsPreferenceKey) == nil {
            defaults.set(true, forKey: skipClearingHiddenDescendantsPreferenceKey)
        }
        if defaults.object(forKey: checkboxTopAlignedPreferenceKey) == nil {
            defaults.set(true, forKey: checkboxTopAlignedPreferenceKey)
        }
        if defaults.object(forKey: frostedBackgroundPreferenceKey) == nil {
            defaults.set(false, forKey: frostedBackgroundPreferenceKey)
        }
        if defaults.object(forKey: listAnimationsEnabledPreferenceKey) == nil {
            defaults.set(true, forKey: listAnimationsEnabledPreferenceKey)
        }
        if defaults.object(forKey: animationsMasterEnabledPreferenceKey) == nil {
            defaults.set(true, forKey: animationsMasterEnabledPreferenceKey)
        }
        if defaults.object(forKey: collapseAnimationsEnabledPreferenceKey) == nil {
            defaults.set(true, forKey: collapseAnimationsEnabledPreferenceKey)
        }
        if defaults.object(forKey: fontScalePreferenceKey) == nil {
            defaults.set(1.0, forKey: fontScalePreferenceKey)
        }
        if defaults.object(forKey: moveCompletedTasksToBottomPreferenceKey) == nil {
            defaults.set(false, forKey: moveCompletedTasksToBottomPreferenceKey)
        }
    }

    func resetMenuBarIconToDefault() {
        selectedIcon = .defaultIcon
    }
}
