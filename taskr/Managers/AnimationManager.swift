import SwiftUI
import Combine

@MainActor
class AnimationManager: ObservableObject {
    @Published private(set) var animationsMasterEnabled: Bool
    @Published private(set) var listAnimationsEnabled: Bool
    @Published private(set) var collapseAnimationsEnabled: Bool
    @Published private(set) var completionAnimationsEnabled: Bool
    @Published private(set) var chevronAnimationEnabled: Bool
    @Published private(set) var itemTransitionsEnabled: Bool
    @Published private(set) var uiMicroAnimationsEnabled: Bool
    @Published private(set) var rowHeightAnimationEnabled: Bool
    @Published private(set) var animationStyle: AnimationStyle
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.animationsMasterEnabled = defaults.object(forKey: animationsMasterEnabledPreferenceKey) as? Bool ?? true
        self.listAnimationsEnabled = defaults.object(forKey: listAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.collapseAnimationsEnabled = defaults.object(forKey: collapseAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.completionAnimationsEnabled = defaults.object(forKey: completionAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.chevronAnimationEnabled = defaults.object(forKey: chevronAnimationEnabledPreferenceKey) as? Bool ?? true
        self.itemTransitionsEnabled = defaults.object(forKey: itemTransitionsEnabledPreferenceKey) as? Bool ?? true
        self.uiMicroAnimationsEnabled = defaults.object(forKey: uiMicroAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.rowHeightAnimationEnabled = defaults.object(forKey: rowHeightAnimationEnabledPreferenceKey) as? Bool ?? true
        self.animationStyle = AnimationStyle(rawValue: defaults.string(forKey: animationStylePreferenceKey) ?? "") ?? .defaultStyle
    }
    
    func setAnimationsMasterEnabled(_ enabled: Bool) {
        guard animationsMasterEnabled != enabled else { return }
        animationsMasterEnabled = enabled
        defaults.set(enabled, forKey: animationsMasterEnabledPreferenceKey)
    }
    
    func setListAnimationsEnabled(_ enabled: Bool) {
        guard listAnimationsEnabled != enabled else { return }
        listAnimationsEnabled = enabled
        defaults.set(enabled, forKey: listAnimationsEnabledPreferenceKey)
    }
    
    func setCollapseAnimationsEnabled(_ enabled: Bool) {
        guard collapseAnimationsEnabled != enabled else { return }
        collapseAnimationsEnabled = enabled
        defaults.set(enabled, forKey: collapseAnimationsEnabledPreferenceKey)
    }
    
    func setCompletionAnimationsEnabled(_ enabled: Bool) {
        guard completionAnimationsEnabled != enabled else { return }
        completionAnimationsEnabled = enabled
        defaults.set(enabled, forKey: completionAnimationsEnabledPreferenceKey)
    }
    
    func setChevronAnimationEnabled(_ enabled: Bool) {
        guard chevronAnimationEnabled != enabled else { return }
        chevronAnimationEnabled = enabled
        defaults.set(enabled, forKey: chevronAnimationEnabledPreferenceKey)
    }
    
    func setItemTransitionsEnabled(_ enabled: Bool) {
        guard itemTransitionsEnabled != enabled else { return }
        itemTransitionsEnabled = enabled
        defaults.set(enabled, forKey: itemTransitionsEnabledPreferenceKey)
    }
    
    func setUiMicroAnimationsEnabled(_ enabled: Bool) {
        guard uiMicroAnimationsEnabled != enabled else { return }
        uiMicroAnimationsEnabled = enabled
        defaults.set(enabled, forKey: uiMicroAnimationsEnabledPreferenceKey)
    }
    
    func setRowHeightAnimationEnabled(_ enabled: Bool) {
        guard rowHeightAnimationEnabled != enabled else { return }
        rowHeightAnimationEnabled = enabled
        defaults.set(enabled, forKey: rowHeightAnimationEnabledPreferenceKey)
    }
    
    func setAnimationStyle(_ style: AnimationStyle) {
        guard animationStyle != style else { return }
        animationStyle = style
        defaults.set(style.rawValue, forKey: animationStylePreferenceKey)
    }
    
    var selectedAnimation: Animation {
        switch animationStyle {
        case .easeInOut: return .easeInOut(duration: 0.2)
        case .spring: return .spring(response: 0.35, dampingFraction: 0.7)
        case .snappy: return .spring(response: 0.25, dampingFraction: 0.85)
        case .linear: return .linear(duration: 0.15)
        }
    }
    
    @discardableResult
    func performListMutation<Result>(_ body: () -> Result) -> Result {
        performAnimation(isEnabled: listAnimationsEnabled, body)
    }
    
    @discardableResult
    func performCollapseTransition<Result>(_ body: () -> Result) -> Result {
        performAnimation(isEnabled: collapseAnimationsEnabled, body)
    }
    
    @discardableResult
    private func performAnimation<Result>(isEnabled: Bool, _ body: () -> Result) -> Result {
        guard animationsMasterEnabled && isEnabled else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            return withTransaction(transaction) { body() }
        }
        return withAnimation(selectedAnimation) { body() }
    }
}
