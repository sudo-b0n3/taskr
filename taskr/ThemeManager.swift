import SwiftUI
import Combine

@MainActor
class ThemeManager: ObservableObject {
    @Published private(set) var selectedTheme: AppTheme
    
    var themePalette: ThemePalette { selectedTheme.palette }
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTheme = defaults.string(forKey: selectedThemePreferenceKey) ?? ""
        self.selectedTheme = AppTheme(rawValue: storedTheme) ?? .system
    }
    
    func setTheme(_ theme: AppTheme) {
        guard theme != selectedTheme else { return }
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: selectedThemePreferenceKey)
    }
}
