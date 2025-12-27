// taskr/taskr/Theme.swift
import SwiftUI
import AppKit

struct ThemePalette {
    let background: NSColor
    let headerBackground: NSColor
    let sectionBackground: NSColor
    let controlBackground: NSColor
    let inputBackground: NSColor
    let hoverBackground: NSColor
    let divider: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let accent: NSColor

    var backgroundColor: Color { Color(nsColor: background) }
    var headerBackgroundColor: Color { Color(nsColor: headerBackground) }
    var sectionBackgroundColor: Color { Color(nsColor: sectionBackground) }
    var controlBackgroundColor: Color { Color(nsColor: controlBackground) }
    var inputBackgroundColor: Color { Color(nsColor: inputBackground) }
    var hoverBackgroundColor: Color { Color(nsColor: hoverBackground) }
    var dividerColor: Color { Color(nsColor: divider) }
    var primaryTextColor: Color { Color(nsColor: primaryText) }
    var secondaryTextColor: Color { Color(nsColor: secondaryText) }
    var accentColor: Color { Color(nsColor: accent) }

    var isDark: Bool { headerBackground.isDarkColor }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case gruvboxDark
    case gruvboxLight
    case solarizedDark
    case solarizedLight
    case dracula
    case nord
    case oneDark
    case tokyoNight
    case tokyoNightStorm
    case tokyoNightLight
    case ayuDark
    case ayuLight
    case nightOwl
    case rosePine
    case horizon
    case catppuccinMocha
    case catppuccinLatte
    case everforestDark
    case everforestLight
    case matrixGreen
    case hazardOps
    case monokai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System Default"
        case .gruvboxDark:
            return "Gruvbox Dark"
        case .gruvboxLight:
            return "Gruvbox Light"
        case .solarizedDark:
            return "Solarized Dark"
        case .solarizedLight:
            return "Solarized Light"
        case .dracula:
            return "Dracula"
        case .nord:
            return "Nord"
        case .oneDark:
            return "One Dark"
        case .tokyoNight:
            return "Tokyo Night"
        case .tokyoNightStorm:
            return "Tokyo Night Storm"
        case .tokyoNightLight:
            return "Tokyo Night Light"
        case .ayuDark:
            return "Ayu Dark"
        case .ayuLight:
            return "Ayu Light"
        case .nightOwl:
            return "Night Owl"
        case .rosePine:
            return "Rose Pine"
        case .horizon:
            return "Horizon"
        case .catppuccinMocha:
            return "Catppuccin Mocha"
        case .catppuccinLatte:
            return "Catppuccin Latte"
        case .everforestDark:
            return "Everforest Dark"
        case .everforestLight:
            return "Everforest Light"
        case .matrixGreen:
            return "Matrix Green"
        case .hazardOps:
            return "Hazard Ops"
        case .monokai:
            return "Monokai"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .system:
            return ThemePalette(
                background: .windowBackgroundColor,
                headerBackground: .windowBackgroundColor,
                sectionBackground: .windowBackgroundColor,
                controlBackground: .controlBackgroundColor,
                inputBackground: .textBackgroundColor,
                hoverBackground: NSColor.secondaryLabelColor.withAlphaComponent(0.08),
                divider: .separatorColor,
                primaryText: .labelColor,
                secondaryText: .secondaryLabelColor,
                accent: .controlAccentColor
            )

        case .gruvboxDark:
            return ThemePalette(
                background: Self.nsColor(0x282828),
                headerBackground: Self.nsColor(0x3c3836),
                sectionBackground: Self.nsColor(0x32302f),
                controlBackground: Self.nsColor(0x3c3836),
                inputBackground: Self.nsColor(0x32302f),
                hoverBackground: Self.nsColor(0x504945),
                divider: Self.nsColor(0x665c54),
                primaryText: Self.nsColor(0xebdbb2),
                secondaryText: Self.nsColor(0xbdae93),
                accent: Self.nsColor(0xd79921)
            )

        case .gruvboxLight:
            return ThemePalette(
                background: Self.nsColor(0xfbf1c7),
                headerBackground: Self.nsColor(0xebe0b8),
                sectionBackground: Self.nsColor(0xf2e5bc),
                controlBackground: Self.nsColor(0xebe0b8),
                inputBackground: Self.nsColor(0xfbf1c7),
                hoverBackground: Self.nsColor(0xd5c4a1),
                divider: Self.nsColor(0xd5c4a1),
                primaryText: Self.nsColor(0x3c3836),
                secondaryText: Self.nsColor(0x7c6f64),
                accent: Self.nsColor(0xb57614)
            )

        case .solarizedDark:
            return ThemePalette(
                background: Self.nsColor(0x002b36),
                headerBackground: Self.nsColor(0x073642),
                sectionBackground: Self.nsColor(0x073642),
                controlBackground: Self.nsColor(0x0d3c4c),
                inputBackground: Self.nsColor(0x002b36),
                hoverBackground: Self.nsColor(0x0e3a47),
                divider: Self.nsColor(0x0e4a59),
                primaryText: Self.nsColor(0x93a1a1),
                secondaryText: Self.nsColor(0x586e75),
                accent: Self.nsColor(0x268bd2)
            )

        case .solarizedLight:
            return ThemePalette(
                background: Self.nsColor(0xfdf6e3),
                headerBackground: Self.nsColor(0xeee8d5),
                sectionBackground: Self.nsColor(0xf3e7cf),
                controlBackground: Self.nsColor(0xeee8d5),
                inputBackground: Self.nsColor(0xfdf6e3),
                hoverBackground: Self.nsColor(0xe6dcbf),
                divider: Self.nsColor(0xd6c9ad),
                primaryText: Self.nsColor(0x657b83),
                secondaryText: Self.nsColor(0x93a1a1),
                accent: Self.nsColor(0x268bd2)
            )

        case .dracula:
            return ThemePalette(
                background: Self.nsColor(0x282a36),
                headerBackground: Self.nsColor(0x343746),
                sectionBackground: Self.nsColor(0x343746),
                controlBackground: Self.nsColor(0x3d4052),
                inputBackground: Self.nsColor(0x44475a),
                hoverBackground: Self.nsColor(0x4c5166),
                divider: Self.nsColor(0x5a5f7a),
                primaryText: Self.nsColor(0xf8f8f2),
                secondaryText: Self.nsColor(0x8be9fd),
                accent: Self.nsColor(0xff79c6)
            )

        case .nord:
            return ThemePalette(
                background: Self.nsColor(0x2e3440),
                headerBackground: Self.nsColor(0x3b4252),
                sectionBackground: Self.nsColor(0x3b4252),
                controlBackground: Self.nsColor(0x434c5e),
                inputBackground: Self.nsColor(0x3b4252),
                hoverBackground: Self.nsColor(0x4c566a),
                divider: Self.nsColor(0x4c566a),
                primaryText: Self.nsColor(0xeceff4),
                secondaryText: Self.nsColor(0xd8dee9),
                accent: Self.nsColor(0x88c0d0)
            )

        case .oneDark:
            return ThemePalette(
                background: Self.nsColor(0x282c34),
                headerBackground: Self.nsColor(0x30343f),
                sectionBackground: Self.nsColor(0x30343f),
                controlBackground: Self.nsColor(0x353b45),
                inputBackground: Self.nsColor(0x353b45),
                hoverBackground: Self.nsColor(0x3e4451),
                divider: Self.nsColor(0x545862),
                primaryText: Self.nsColor(0xabb2bf),
                secondaryText: Self.nsColor(0x828997),
                accent: Self.nsColor(0x61afef)
            )

        case .tokyoNight:
            return ThemePalette(
                background: Self.nsColor(0x1a1b26),
                headerBackground: Self.nsColor(0x16161e),
                sectionBackground: Self.nsColor(0x1f2335),
                controlBackground: Self.nsColor(0x1b1e2e),
                inputBackground: Self.nsColor(0x14141b),
                hoverBackground: Self.nsColor(0x24283b),
                divider: Self.nsColor(0x2f334d),
                primaryText: Self.nsColor(0xc0caf5),
                secondaryText: Self.nsColor(0x565f89),
                accent: Self.nsColor(0x7aa2f7)
            )

        case .tokyoNightStorm:
            return ThemePalette(
                background: Self.nsColor(0x24283b),
                headerBackground: Self.nsColor(0x1f2335),
                sectionBackground: Self.nsColor(0x292e42),
                controlBackground: Self.nsColor(0x1b1e2e),
                inputBackground: Self.nsColor(0x1b1e2e),
                hoverBackground: Self.nsColor(0x343a55),
                divider: Self.nsColor(0x3b4261),
                primaryText: Self.nsColor(0xc0caf5),
                secondaryText: Self.nsColor(0x8089b3),
                accent: Self.nsColor(0x7aa2f7)
            )

        case .tokyoNightLight:
            return ThemePalette(
                background: Self.nsColor(0xe6e7ed),
                headerBackground: Self.nsColor(0xd6d8df),
                sectionBackground: Self.nsColor(0xdfe2eb),
                controlBackground: Self.nsColor(0xe1e2e8),
                inputBackground: Self.nsColor(0xe6e7ed),
                hoverBackground: Self.nsColor(0xe1e2e8),
                divider: Self.nsColor(0xc5c8d8),
                primaryText: Self.nsColor(0x343b59),
                secondaryText: Self.nsColor(0x58608a),
                accent: Self.nsColor(0x2959aa)
            )

        case .ayuDark:
            return ThemePalette(
                background: Self.nsColor(0x0b0e14),
                headerBackground: Self.nsColor(0x10141d),
                sectionBackground: Self.nsColor(0x141822),
                controlBackground: Self.nsColor(0x0d1017),
                inputBackground: Self.nsColor(0x0d1017),
                hoverBackground: Self.nsColor(0x1a2029),
                divider: Self.nsColor(0x1f2730),
                primaryText: Self.nsColor(0xbfbdb6),
                secondaryText: Self.nsColor(0x565b66),
                accent: Self.nsColor(0x53bdfa)
            )

        case .ayuLight:
            return ThemePalette(
                background: Self.nsColor(0xf8f9fa),
                headerBackground: Self.nsColor(0xeff2f6),
                sectionBackground: Self.nsColor(0xf1f3f6),
                controlBackground: Self.nsColor(0xfcfcfc),
                inputBackground: Self.nsColor(0xfcfcfc),
                hoverBackground: Self.nsColor(0xe6eaef),
                divider: Self.nsColor(0xd0d4da),
                primaryText: Self.nsColor(0x5c6166),
                secondaryText: Self.nsColor(0x8a9199),
                accent: Self.nsColor(0x3199e1)
            )

        case .nightOwl:
            return ThemePalette(
                background: Self.nsColor(0x011627),
                headerBackground: Self.nsColor(0x031d34),
                sectionBackground: Self.nsColor(0x052038),
                controlBackground: Self.nsColor(0x0b253a),
                inputBackground: Self.nsColor(0x0b253a),
                hoverBackground: Self.nsColor(0x112b45),
                divider: Self.nsColor(0x1d3b53),
                primaryText: Self.nsColor(0xd6deeb),
                secondaryText: Self.nsColor(0x4b6479),
                accent: Self.nsColor(0x82aaff)
            )

        case .rosePine:
            return ThemePalette(
                background: Self.nsColor(0x191724),
                headerBackground: Self.nsColor(0x191724),
                sectionBackground: Self.nsColor(0x1f1d2e),
                controlBackground: Self.nsColor(0x26233a),
                inputBackground: Self.nsColor(0x26233a),
                hoverBackground: Self.nsColor(0x2a2736),
                divider: Self.nsColor(0x312f44),
                primaryText: Self.nsColor(0xe0def4),
                secondaryText: Self.nsColor(0x908caa),
                accent: Self.nsColor(0xeb6f92)
            )

        case .horizon:
            return ThemePalette(
                background: Self.nsColor(0x1c1e26),
                headerBackground: Self.nsColor(0x1c1e26),
                sectionBackground: Self.nsColor(0x232530),
                controlBackground: Self.nsColor(0x2e303e),
                inputBackground: Self.nsColor(0x2e303e),
                hoverBackground: Self.nsColor(0x343647),
                divider: Self.nsColor(0x2e303e),
                primaryText: Self.nsColor(0xd5d8da),
                secondaryText: Self.nsColor(0x6c6f93),
                accent: Self.nsColor(0xe95378)
            )

        case .catppuccinMocha:
            return ThemePalette(
                background: Self.nsColor(0x1e1e2e),
                headerBackground: Self.nsColor(0x181825),
                sectionBackground: Self.nsColor(0x202232),
                controlBackground: Self.nsColor(0x302d41),
                inputBackground: Self.nsColor(0x313244),
                hoverBackground: Self.nsColor(0x51576d),
                divider: Self.nsColor(0x45475a),
                primaryText: Self.nsColor(0xcdd6f4),
                secondaryText: Self.nsColor(0xbac2de),
                accent: Self.nsColor(0x89b4fa)
            )

        case .catppuccinLatte:
            return ThemePalette(
                background: Self.nsColor(0xeff1f5),
                headerBackground: Self.nsColor(0xe6e9ef),
                sectionBackground: Self.nsColor(0xdce0e8),
                controlBackground: Self.nsColor(0xccd0da),
                inputBackground: Self.nsColor(0xdce0e8),
                hoverBackground: Self.nsColor(0xbcc0cc),
                divider: Self.nsColor(0xacb0be),
                primaryText: Self.nsColor(0x4c4f69),
                secondaryText: Self.nsColor(0x6c6f85),
                accent: Self.nsColor(0x1e66f5)
            )

        case .everforestDark:
            return ThemePalette(
                background: Self.nsColor(0x2d353b),
                headerBackground: Self.nsColor(0x343f44),
                sectionBackground: Self.nsColor(0x3a454a),
                controlBackground: Self.nsColor(0x343f44),
                inputBackground: Self.nsColor(0x343f44),
                hoverBackground: Self.nsColor(0x415054),
                divider: Self.nsColor(0x4c555b),
                primaryText: Self.nsColor(0xd3c6aa),
                secondaryText: Self.nsColor(0x859289),
                accent: Self.nsColor(0x7fbbb3)
            )

        case .everforestLight:
            return ThemePalette(
                background: Self.nsColor(0xf7f1df),
                headerBackground: Self.nsColor(0xf1ebd6),
                sectionBackground: Self.nsColor(0xf4eed9),
                controlBackground: Self.nsColor(0xfdf6e3),
                inputBackground: Self.nsColor(0xfdf6e3),
                hoverBackground: Self.nsColor(0xede4cc),
                divider: Self.nsColor(0xd3c6aa),
                primaryText: Self.nsColor(0x5c6a72),
                secondaryText: Self.nsColor(0x8d9a9f),
                accent: Self.nsColor(0x3a94c5)
            )

        case .matrixGreen:
            return ThemePalette(
                background: Self.nsColor(0x000f06),
                headerBackground: Self.nsColor(0x00190b),
                sectionBackground: Self.nsColor(0x002211),
                controlBackground: Self.nsColor(0x002b17),
                inputBackground: Self.nsColor(0x00351d),
                hoverBackground: Self.nsColor(0x1aff5f16),
                divider: Self.nsColor(0x005f2a),
                primaryText: Self.nsColor(0x54ff9f),
                secondaryText: Self.nsColor(0x29d37a),
                accent: Self.nsColor(0x39ff14)
            )

        case .hazardOps:
            return ThemePalette(
                background: Self.nsColor(0x1e2719),
                headerBackground: Self.nsColor(0x1c2317),
                sectionBackground: Self.nsColor(0x242d1f),
                controlBackground: Self.nsColor(0x2b3626),
                inputBackground: Self.nsColor(0x2f3b2b),
                hoverBackground: Self.nsColor(0x35422f),
                divider: Self.nsColor(0x3f4d39),
                primaryText: Self.nsColor(0xffead1),
                secondaryText: Self.nsColor(0xdce4b8),
                accent: Self.nsColor(0xfd6f2f)
            )

        case .monokai:
            return ThemePalette(
                background: Self.nsColor(0x272822),
                headerBackground: Self.nsColor(0x32332b),
                sectionBackground: Self.nsColor(0x2e2f26),
                controlBackground: Self.nsColor(0x38392f),
                inputBackground: Self.nsColor(0x32332b),
                hoverBackground: Self.nsColor(0x3e3f33),
                divider: Self.nsColor(0x48493d),
                primaryText: Self.nsColor(0xf8f8f2),
                secondaryText: Self.nsColor(0xa6a896),
                accent: Self.nsColor(0xf92672)
            )
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .gruvboxDark, .solarizedDark, .dracula, .nord, .oneDark, .tokyoNight, .tokyoNightStorm, .ayuDark, .nightOwl, .rosePine, .horizon, .catppuccinMocha, .everforestDark, .matrixGreen, .hazardOps, .monokai:
            return .dark
        case .gruvboxLight, .solarizedLight, .tokyoNightLight, .ayuLight, .catppuccinLatte, .everforestLight:
            return .light
        }
    }

    private static func nsColor(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0x0000FF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension NSColor {
    var isDarkColor: Bool {
        guard let converted = usingColorSpace(.deviceRGB) else { return false }
        let luminance = (0.299 * converted.redComponent) + (0.587 * converted.greenComponent) + (0.114 * converted.blueComponent)
        return luminance < 0.5
    }
}
