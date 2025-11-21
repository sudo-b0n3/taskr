import SwiftUI

struct AnimatedStrikeText: View {
    let text: String
    let isStruck: Bool
    let enabled: Bool
    let strikeColor: Color
    private let animation: Animation = .easeInOut(duration: 0.18)

    var body: some View {
        let progress: CGFloat = isStruck ? 1.0 : 0.0
        ZStack(alignment: .leading) {
            Text(text)

            Text(text)
                .foregroundStyle(Color.clear)
                .strikethrough(true, color: strikeColor)
                .mask(
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * progress, height: proxy.size.height, alignment: .leading)
                    }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(enabled ? animation : .none, value: isStruck)
    }
}
