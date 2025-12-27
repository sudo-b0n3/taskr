import SwiftUI
import Combine

@MainActor
class AnimationManager: ObservableObject {
    @Published private(set) var animationsMasterEnabled: Bool
    @Published private(set) var listAnimationsEnabled: Bool
    @Published private(set) var collapseAnimationsEnabled: Bool
    @Published private(set) var completionAnimationsEnabled: Bool
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.animationsMasterEnabled = defaults.object(forKey: animationsMasterEnabledPreferenceKey) as? Bool ?? true
        self.listAnimationsEnabled = defaults.object(forKey: listAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.collapseAnimationsEnabled = defaults.object(forKey: collapseAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.completionAnimationsEnabled = defaults.object(forKey: completionAnimationsEnabledPreferenceKey) as? Bool ?? true
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
        return withAnimation(.default) { body() }
    }
}
