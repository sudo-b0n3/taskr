import SwiftUI

private struct IsWindowFocusedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct IsLiveScrollingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isWindowFocused: Bool {
        get { self[IsWindowFocusedKey.self] }
        set { self[IsWindowFocusedKey.self] = newValue }
    }

    var isLiveScrolling: Bool {
        get { self[IsLiveScrollingKey.self] }
        set { self[IsLiveScrollingKey.self] = newValue }
    }
}
