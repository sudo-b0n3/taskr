import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {
    let palette: ThemePalette
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                configuration.isOn.toggle()
            } label: {
                AnimatedCheckCircle(
                    isOn: configuration.isOn,
                    enabled: true,
                    baseColor: palette.secondaryTextColor,
                    accentColor: palette.accentColor
                )
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let isOn: Binding<Bool>
    var helpText: String? = nil
    let palette: ThemePalette
    
    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .taskrFont(.body)
                    .foregroundColor(palette.primaryTextColor)
                
                if let help = helpText {
                    Text(help)
                        .taskrFont(.caption)
                        .foregroundColor(palette.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(CheckboxToggleStyle(palette: palette))
        .padding(.vertical, 4)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String?
    let palette: ThemePalette
    let content: Content
    
    init(title: String? = nil, palette: ThemePalette, @ViewBuilder content: () -> Content) {
        self.title = title
        self.palette = palette
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .taskrFont(.headline)
                    .foregroundColor(palette.accentColor)
                    .padding(.bottom, 4)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct SettingsPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let palette: ThemePalette
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack {
            Text(title)
                .taskrFont(.body)
                .foregroundColor(palette.primaryTextColor)
            Spacer()
            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .fixedSize()
            .accentColor(palette.accentColor)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let palette: ThemePalette
    let defaultValue: Double?
    var valueLabel: String {
        "\(Int((value * 100).rounded()))%"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .taskrFont(.body)
                    .foregroundColor(palette.primaryTextColor)
                Spacer()
                Text(valueLabel)
                    .taskrFont(.caption)
                    .foregroundColor(palette.secondaryTextColor)
            }
            HStack(spacing: 8) {
                Text("A")
                    .taskrFont(.caption)
                    .foregroundColor(palette.secondaryTextColor)
                Slider(value: $value, in: range, step: step)
                    .overlay(alignment: .topLeading) {
                        if let defaultValue {
                            GeometryReader { proxy in
                                let normalized = max(0, min(1, (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)))
                                let knobRadius = min(max(proxy.size.height / 2, 6), 10)
                                let effectiveWidth = max(proxy.size.width - (knobRadius * 2), 0)
                                let xPos = knobRadius + normalized * effectiveWidth
                                VStack(spacing: 3) {
                                    Text("Default")
                                        .taskrFont(.caption2)
                                        .foregroundColor(palette.secondaryTextColor.opacity(0.75))
                                    Capsule()
                                        .fill(palette.secondaryTextColor.opacity(0.55))
                                        .frame(width: 2, height: 10)
                                }
                                .position(x: xPos, y: -8)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                Text("A")
                    .taskrFont(.title3)
                    .foregroundColor(palette.primaryTextColor)
            }
        }
        .padding(.vertical, 4)
    }
}
