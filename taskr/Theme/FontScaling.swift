import SwiftUI
import AppKit

private struct TaskrFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var taskrFontScale: Double {
        get { self[TaskrFontScaleKey.self] }
        set { self[TaskrFontScaleKey.self] = newValue }
    }
}

private struct TaskrFontModifier: ViewModifier {
    @Environment(\.taskrFontScale) private var scale
    let style: Font.TextStyle

    func body(content: Content) -> some View {
        content.font(TaskrTypography.scaledFont(for: style, scale: scale))
    }
}

extension View {
    func taskrFont(_ style: Font.TextStyle) -> some View {
        modifier(TaskrFontModifier(style: style))
    }
}

enum TaskrTypography {
    static func scaledFont(for style: Font.TextStyle, scale: Double) -> Font {
        Font(scaledNSFont(for: style, scale: scale))
    }

    static func scaledNSFont(for style: Font.TextStyle, scale: Double) -> NSFont {
        let nsStyle = nsTextStyle(for: style)
        let baseFont = NSFont.preferredFont(forTextStyle: nsStyle)
        let targetSize = max(baseFont.pointSize * scale, 8)
        return NSFont(descriptor: baseFont.fontDescriptor, size: targetSize) ?? baseFont
    }
    
    /// Returns the line height for a given text style at a particular scale.
    /// This can be used to calculate standardized row heights.
    static func lineHeight(for style: Font.TextStyle, scale: Double) -> CGFloat {
        let nsFont = scaledNSFont(for: style, scale: scale)
        // Use ascender + abs(descender) for reliable line height
        return ceil(nsFont.ascender + abs(nsFont.descender) + nsFont.leading)
    }

    private static func nsTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption2: return .caption2
        case .caption: return .caption1
        default: return .body
        }
    }
}
