import SwiftUI

struct AnimatedCheckCircle: View {
    var isOn: Bool
    var enabled: Bool
    var baseColor: Color
    var accentColor: Color

    private let targetScale: CGFloat = 0.55
    private let animation: Animation = .spring(response: 0.25, dampingFraction: 0.7)

    var body: some View {
        ZStack {
            Image(systemName: "circle")
                .foregroundColor(baseColor)
            Circle()
                .fill(accentColor)
                .scaleEffect(isOn ? targetScale : 0.0001)
                .animation(enabled ? animation : .none, value: isOn)
        }
    }
}
