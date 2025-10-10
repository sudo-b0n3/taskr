// taskr/taskr/AppPreferences.swift
import Foundation
import Combine

// --- Keys ---
let menuBarIconPreferenceKey = "menuBarIconPreference"
let showDockIconPreferenceKey = "showDockIconPreference"
let globalHotkeyEnabledPreferenceKey = "globalHotkeyEnabledPreference"
// Deprecated: replaced by separate toggles for root vs subtasks
let newTaskPositionPreferenceKey = "newTaskPositionPreference"
// New keys for insertion preferences
let addRootTasksToTopPreferenceKey = "addRootTasksToTopPreference"
let addSubtasksToTopPreferenceKey = "addSubtasksToTopPreference"
let collapsedTaskIDsPreferenceKey = "collapsedTaskIDsPreference" // Persist collapsed state
let completionAnimationsEnabledPreferenceKey = "completionAnimationsEnabledPreference" // Toggle subtle completion animations
let allowClearingStruckDescendantsPreferenceKey = "allowClearingStruckDescendantsPreference" // Allow clearing children under completed parents
let normalizedDisplayOrderMigrationDoneKey = "normalizedDisplayOrderMigrationDone"
let checkboxTopAlignedPreferenceKey = "checkboxTopAlignedPreference" // Align checkbox with first line
let selectedThemePreferenceKey = "selectedThemePreference" // Active visual theme
let frostedBackgroundPreferenceKey = "frostedBackgroundPreference" // Enable frosted glass background

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
        checkboxTopAligned = defaults.object(forKey: checkboxTopAlignedPreferenceKey) as? Bool ?? true
        enableFrostedBackground = defaults.bool(forKey: frostedBackgroundPreferenceKey)
    }

    private static func seedDefaultsIfNeeded(in defaults: UserDefaults) {
        if defaults.object(forKey: addRootTasksToTopPreferenceKey) == nil {
            defaults.set(true, forKey: addRootTasksToTopPreferenceKey)
        }
        if defaults.object(forKey: addSubtasksToTopPreferenceKey) == nil {
            defaults.set(false, forKey: addSubtasksToTopPreferenceKey)
        }
        if defaults.object(forKey: completionAnimationsEnabledPreferenceKey) == nil {
            defaults.set(true, forKey: completionAnimationsEnabledPreferenceKey)
        }
        if defaults.object(forKey: checkboxTopAlignedPreferenceKey) == nil {
            defaults.set(true, forKey: checkboxTopAlignedPreferenceKey)
        }
        if defaults.object(forKey: frostedBackgroundPreferenceKey) == nil {
            defaults.set(false, forKey: frostedBackgroundPreferenceKey)
        }
    }

    func resetMenuBarIconToDefault() {
        selectedIcon = .defaultIcon
    }
}
