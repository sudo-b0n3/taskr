import SwiftUI

private struct IsWindowKeyKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct IsLiveScrollingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isWindowKey: Bool {
        get { self[IsWindowKeyKey.self] }
        set { self[IsWindowKeyKey.self] = newValue }
    }

    var isLiveScrolling: Bool {
        get { self[IsLiveScrollingKey.self] }
        set { self[IsLiveScrollingKey.self] = newValue }
    }
}
