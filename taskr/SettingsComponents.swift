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
                    .font(.body)
                    .foregroundColor(palette.primaryTextColor)
                
                if let help = helpText {
                    Text(help)
                        .font(.caption)
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
                    .font(.headline)
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
                .font(.body)
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
