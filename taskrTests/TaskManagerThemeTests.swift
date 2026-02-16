import XCTest
import SwiftData
import SwiftUI
@testable import taskr

@MainActor
final class TaskManagerThemeTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "taskrThemeTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create UserDefaults suite for testing")
        }
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults

        let schema = Schema([Task.self, TaskTemplate.self, TaskTag.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        container = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func makeManager() -> TaskManager {
        TaskManager(modelContext: container.mainContext, defaults: defaults)
    }

    func testDefaultThemeIsSystemWhenUnset() throws {
        let manager = makeManager()
        XCTAssertEqual(manager.selectedTheme, .system)
        XCTAssertEqual(manager.themePalette.background, AppTheme.system.palette.background)
        XCTAssertNil(manager.selectedTheme.preferredColorScheme)
    }

    func testSetThemePersistsToDefaults() throws {
        var manager: TaskManager? = makeManager()
        manager?.setTheme(.catppuccinMocha)
        XCTAssertEqual(manager?.selectedTheme, .catppuccinMocha)
        XCTAssertEqual(defaults.string(forKey: selectedThemePreferenceKey), AppTheme.catppuccinMocha.rawValue)
        manager = nil

        let restoredManager = makeManager()
        XCTAssertEqual(restoredManager.selectedTheme, .catppuccinMocha)
        XCTAssertEqual(restoredManager.themePalette.accent, AppTheme.catppuccinMocha.palette.accent)
    }

    func testAllThemesAreEnumerated() throws {
        let expectedOrder: [AppTheme] = [
            .system,
            .gruvboxDark,
            .gruvboxLight,
            .solarizedDark,
            .solarizedLight,
            .dracula,
            .nord,
            .oneDark,
            .tokyoNight,
            .tokyoNightStorm,
            .tokyoNightLight,
            .ayuDark,
            .ayuLight,
            .nightOwl,
            .rosePine,
            .horizon,
            .catppuccinMocha,
            .catppuccinLatte,
            .everforestDark,
            .everforestLight,
            .matrixGreen,
            .hazardOps,
            .monokai
        ]
        XCTAssertEqual(AppTheme.allCases, expectedOrder)
    }

    func testPreferredColorSchemeMatchesTheme() throws {
        let manager = makeManager()

        let darkThemes: Set<AppTheme> = [
            .gruvboxDark,
            .solarizedDark,
            .dracula,
            .nord,
            .oneDark,
            .tokyoNight,
            .tokyoNightStorm,
            .ayuDark,
            .nightOwl,
            .rosePine,
            .horizon,
            .catppuccinMocha,
            .matrixGreen,
            .hazardOps,
            .everforestDark,
            .monokai
        ]
        let lightThemes: Set<AppTheme> = [
            .gruvboxLight,
            .solarizedLight,
            .tokyoNightLight,
            .ayuLight,
            .catppuccinLatte,
            .everforestLight
        ]

        for theme in AppTheme.allCases {
            manager.setTheme(theme)
            let actual = manager.selectedTheme.preferredColorScheme
            let expected: ColorScheme?
            if theme == .system {
                expected = nil
            } else if darkThemes.contains(theme) {
                expected = .dark
            } else if lightThemes.contains(theme) {
                expected = .light
            } else {
                XCTFail("Theme \(theme) missing classification for preferred color scheme")
                continue
            }
            XCTAssertEqual(actual, expected, "Theme \(theme.displayName) expected \(String(describing: expected)) scheme")
        }
    }

    func testPalettesProvideReadableContrast() throws {
        for theme in AppTheme.allCases {
            let palette = theme.palette
            XCTAssertFalse(palette.background.isEqual(palette.primaryText), "Theme \(theme.displayName) has identical background and primary text colors")
            XCTAssertFalse(palette.background.isEqual(palette.accent), "Theme \(theme.displayName) has identical background and accent colors")
            XCTAssertFalse(palette.primaryText.isEqual(palette.secondaryText), "Theme \(theme.displayName) should differentiate primary and secondary text")
        }
    }

    func testFrostedBackgroundPreferencePersists() throws {
        let manager = makeManager()
        XCTAssertFalse(manager.frostedBackgroundEnabled)

        manager.setFrostedBackgroundEnabled(true)
        XCTAssertTrue(manager.frostedBackgroundEnabled)
        XCTAssertTrue(defaults.bool(forKey: frostedBackgroundPreferenceKey))

        manager.setFrostedBackgroundEnabled(false)
        XCTAssertFalse(manager.frostedBackgroundEnabled)
        XCTAssertFalse(defaults.bool(forKey: frostedBackgroundPreferenceKey))
    }
}
