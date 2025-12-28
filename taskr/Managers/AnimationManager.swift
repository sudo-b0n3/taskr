import SwiftUI
import Combine

@MainActor
class AnimationManager: ObservableObject {
    // Master toggle
    @Published private(set) var animationsMasterEnabled: Bool
    
    // Group toggles
    @Published private(set) var taskListAnimationsGroupEnabled: Bool
    @Published private(set) var expandCollapseAnimationsGroupEnabled: Bool
    @Published private(set) var uiMicroAnimationsEnabled: Bool
    
    // Task List granular settings
    @Published private(set) var listAnimationsEnabled: Bool
    @Published private(set) var itemTransitionsEnabled: Bool
    @Published private(set) var rowHeightAnimationEnabled: Bool
    
    // Expand/Collapse granular settings
    @Published private(set) var collapseAnimationsEnabled: Bool
    @Published private(set) var chevronAnimationEnabled: Bool
    
    // UI Micro-interactions granular settings
    @Published private(set) var hoverHighlightsEnabled: Bool
    @Published private(set) var pinRotationEnabled: Bool
    @Published private(set) var suggestionBoxAnimationEnabled: Bool
    @Published private(set) var completionAnimationsEnabled: Bool
    
    // Animation style
    @Published private(set) var animationStyle: AnimationStyle
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        // Master
        self.animationsMasterEnabled = defaults.object(forKey: animationsMasterEnabledPreferenceKey) as? Bool ?? true
        
        // Group toggles
        self.taskListAnimationsGroupEnabled = defaults.object(forKey: taskListAnimationsGroupEnabledPreferenceKey) as? Bool ?? true
        self.expandCollapseAnimationsGroupEnabled = defaults.object(forKey: expandCollapseAnimationsGroupEnabledPreferenceKey) as? Bool ?? true
        self.uiMicroAnimationsEnabled = defaults.object(forKey: uiMicroAnimationsEnabledPreferenceKey) as? Bool ?? true
        
        // Task List granular
        self.listAnimationsEnabled = defaults.object(forKey: listAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.itemTransitionsEnabled = defaults.object(forKey: itemTransitionsEnabledPreferenceKey) as? Bool ?? true
        self.rowHeightAnimationEnabled = defaults.object(forKey: rowHeightAnimationEnabledPreferenceKey) as? Bool ?? true
        
        // Expand/Collapse granular
        self.collapseAnimationsEnabled = defaults.object(forKey: collapseAnimationsEnabledPreferenceKey) as? Bool ?? true
        self.chevronAnimationEnabled = defaults.object(forKey: chevronAnimationEnabledPreferenceKey) as? Bool ?? true
        
        // UI Micro-interactions granular
        self.hoverHighlightsEnabled = defaults.object(forKey: hoverHighlightsAnimationEnabledPreferenceKey) as? Bool ?? true
        self.pinRotationEnabled = defaults.object(forKey: pinRotationAnimationEnabledPreferenceKey) as? Bool ?? true
        self.suggestionBoxAnimationEnabled = defaults.object(forKey: suggestionBoxAnimationEnabledPreferenceKey) as? Bool ?? true
        self.completionAnimationsEnabled = defaults.object(forKey: completionAnimationsEnabledPreferenceKey) as? Bool ?? true
        
        // Style
        self.animationStyle = AnimationStyle(rawValue: defaults.string(forKey: animationStylePreferenceKey) ?? "") ?? .defaultStyle
    }
    
    // MARK: - Master Toggle
    
    func setAnimationsMasterEnabled(_ enabled: Bool) {
        guard animationsMasterEnabled != enabled else { return }
        animationsMasterEnabled = enabled
        defaults.set(enabled, forKey: animationsMasterEnabledPreferenceKey)
    }
    
    // MARK: - Group Toggle Setters
    
    func setTaskListAnimationsGroupEnabled(_ enabled: Bool) {
        guard taskListAnimationsGroupEnabled != enabled else { return }
        taskListAnimationsGroupEnabled = enabled
        defaults.set(enabled, forKey: taskListAnimationsGroupEnabledPreferenceKey)
    }
    
    func setExpandCollapseAnimationsGroupEnabled(_ enabled: Bool) {
        guard expandCollapseAnimationsGroupEnabled != enabled else { return }
        expandCollapseAnimationsGroupEnabled = enabled
        defaults.set(enabled, forKey: expandCollapseAnimationsGroupEnabledPreferenceKey)
    }
    
    func setUiMicroAnimationsEnabled(_ enabled: Bool) {
        guard uiMicroAnimationsEnabled != enabled else { return }
        uiMicroAnimationsEnabled = enabled
        defaults.set(enabled, forKey: uiMicroAnimationsEnabledPreferenceKey)
    }
    
    // MARK: - Task List Granular Setters
    
    func setListAnimationsEnabled(_ enabled: Bool) {
        guard listAnimationsEnabled != enabled else { return }
        listAnimationsEnabled = enabled
        defaults.set(enabled, forKey: listAnimationsEnabledPreferenceKey)
    }
    
    func setItemTransitionsEnabled(_ enabled: Bool) {
        guard itemTransitionsEnabled != enabled else { return }
        itemTransitionsEnabled = enabled
        defaults.set(enabled, forKey: itemTransitionsEnabledPreferenceKey)
    }
    
    func setRowHeightAnimationEnabled(_ enabled: Bool) {
        guard rowHeightAnimationEnabled != enabled else { return }
        rowHeightAnimationEnabled = enabled
        defaults.set(enabled, forKey: rowHeightAnimationEnabledPreferenceKey)
    }
    
    // MARK: - Expand/Collapse Granular Setters
    
    func setCollapseAnimationsEnabled(_ enabled: Bool) {
        guard collapseAnimationsEnabled != enabled else { return }
        collapseAnimationsEnabled = enabled
        defaults.set(enabled, forKey: collapseAnimationsEnabledPreferenceKey)
    }
    
    func setChevronAnimationEnabled(_ enabled: Bool) {
        guard chevronAnimationEnabled != enabled else { return }
        chevronAnimationEnabled = enabled
        defaults.set(enabled, forKey: chevronAnimationEnabledPreferenceKey)
    }
    
    // MARK: - UI Micro-interactions Granular Setters
    
    func setHoverHighlightsEnabled(_ enabled: Bool) {
        guard hoverHighlightsEnabled != enabled else { return }
        hoverHighlightsEnabled = enabled
        defaults.set(enabled, forKey: hoverHighlightsAnimationEnabledPreferenceKey)
    }
    
    func setPinRotationEnabled(_ enabled: Bool) {
        guard pinRotationEnabled != enabled else { return }
        pinRotationEnabled = enabled
        defaults.set(enabled, forKey: pinRotationAnimationEnabledPreferenceKey)
    }
    
    func setSuggestionBoxAnimationEnabled(_ enabled: Bool) {
        guard suggestionBoxAnimationEnabled != enabled else { return }
        suggestionBoxAnimationEnabled = enabled
        defaults.set(enabled, forKey: suggestionBoxAnimationEnabledPreferenceKey)
    }
    
    func setCompletionAnimationsEnabled(_ enabled: Bool) {
        guard completionAnimationsEnabled != enabled else { return }
        completionAnimationsEnabled = enabled
        defaults.set(enabled, forKey: completionAnimationsEnabledPreferenceKey)
    }
    
    // MARK: - Animation Style
    
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
    
    // MARK: - Effective Checks (respects master + group + individual)
    
    var effectiveListAnimationsEnabled: Bool {
        animationsMasterEnabled && taskListAnimationsGroupEnabled && listAnimationsEnabled
    }
    
    var effectiveItemTransitionsEnabled: Bool {
        animationsMasterEnabled && taskListAnimationsGroupEnabled && itemTransitionsEnabled
    }
    
    var effectiveRowHeightAnimationEnabled: Bool {
        animationsMasterEnabled && taskListAnimationsGroupEnabled && rowHeightAnimationEnabled
    }
    
    var effectiveCollapseAnimationsEnabled: Bool {
        animationsMasterEnabled && expandCollapseAnimationsGroupEnabled && collapseAnimationsEnabled
    }
    
    var effectiveChevronAnimationEnabled: Bool {
        animationsMasterEnabled && expandCollapseAnimationsGroupEnabled && chevronAnimationEnabled
    }
    
    var effectiveHoverHighlightsEnabled: Bool {
        animationsMasterEnabled && uiMicroAnimationsEnabled && hoverHighlightsEnabled
    }
    
    var effectivePinRotationEnabled: Bool {
        animationsMasterEnabled && uiMicroAnimationsEnabled && pinRotationEnabled
    }
    
    var effectiveSuggestionBoxAnimationEnabled: Bool {
        animationsMasterEnabled && uiMicroAnimationsEnabled && suggestionBoxAnimationEnabled
    }
    
    var effectiveCompletionAnimationsEnabled: Bool {
        animationsMasterEnabled && uiMicroAnimationsEnabled && completionAnimationsEnabled
    }
    
    // MARK: - Animation Helpers
    
    @discardableResult
    func performListMutation<Result>(_ body: () -> Result) -> Result {
        performAnimation(isEnabled: effectiveListAnimationsEnabled, body)
    }
    
    @discardableResult
    func performCollapseTransition<Result>(_ body: () -> Result) -> Result {
        performAnimation(isEnabled: effectiveCollapseAnimationsEnabled, body)
    }
    
    @discardableResult
    private func performAnimation<Result>(isEnabled: Bool, _ body: () -> Result) -> Result {
        guard isEnabled else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            return withTransaction(transaction) { body() }
        }
        return withAnimation(selectedAnimation) { body() }
    }
}

