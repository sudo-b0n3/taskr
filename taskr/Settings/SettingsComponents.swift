import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {
    let palette: ThemePalette
    private let checkboxSize: CGFloat = 18
    private let checkboxTapExpansion: CGFloat = 6
    
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
                .frame(width: checkboxSize, height: checkboxSize)
                .contentShape(Rectangle().inset(by: -checkboxTapExpansion))
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
    let contentBuilder: () -> Content
    private let storageKey: String
    
    @EnvironmentObject private var taskManager: TaskManager
    @State private var isExpanded: Bool?
    @State private var isHovering: Bool = false
    
    init(title: String? = nil, palette: ThemePalette, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.palette = palette
        self.contentBuilder = content
        self.storageKey = "settings.section.\(title ?? "default").expanded"
    }
    
    private var effectiveExpanded: Bool {
        isExpanded ?? (UserDefaults.standard.object(forKey: storageKey) == nil ? true : UserDefaults.standard.bool(forKey: storageKey))
    }
    
    private var chevronAnimationEnabled: Bool {
        taskManager.animationsMasterEnabled && taskManager.animationManager.chevronAnimationEnabled
    }
    
    private var collapseAnimationEnabled: Bool {
        taskManager.animationsMasterEnabled && taskManager.collapseAnimationsEnabled
    }
    
    private var uiAnimationsEnabled: Bool {
        taskManager.animationManager.effectiveHoverHighlightsEnabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Button {
                    let newValue = !effectiveExpanded
                    UserDefaults.standard.set(newValue, forKey: storageKey)
                    if collapseAnimationEnabled {
                        withAnimation(taskManager.animationManager.selectedAnimation) {
                            isExpanded = newValue
                        }
                    } else {
                        isExpanded = newValue
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title)
                            .taskrFont(.headline)
                            .foregroundColor(palette.accentColor)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(palette.secondaryTextColor)
                            .rotationEffect(.degrees(effectiveExpanded ? 90 : 0))
                            .animation(chevronAnimationEnabled ? taskManager.animationManager.selectedAnimation : nil, value: effectiveExpanded)
                            .frame(width: 20, height: 20)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovering ? palette.hoverBackgroundColor.opacity(0.5) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovering = hovering
                }
                .animation(uiAnimationsEnabled ? .easeOut(duration: 0.1) : nil, value: isHovering)
            }
            
            if effectiveExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    contentBuilder()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .clipped()
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
