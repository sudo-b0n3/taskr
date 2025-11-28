import Foundation
import AppKit
import Carbon

struct HotkeyConfiguration: Equatable {
    var keyCode: CGKeyCode
    var modifiers: NSEvent.ModifierFlags

    static let `default` = HotkeyConfiguration(
        keyCode: CGKeyCode(defaultHotkeyKeyCode),
        modifiers: defaultHotkeyModifiers
    )

    var displayString: String {
        HotkeyFormatter.displayString(for: self)
    }
}

enum HotkeyPreferences {
    static func load(defaults: UserDefaults = .standard) -> HotkeyConfiguration {
        let storedKeyCode = defaults.object(forKey: globalHotkeyKeyCodePreferenceKey) as? Int
        let storedModifiers = defaults.object(forKey: globalHotkeyModifiersPreferenceKey) as? Int

        let keyCode = CGKeyCode(storedKeyCode ?? Int(defaultHotkeyKeyCode))
        let modifiers = NSEvent.ModifierFlags(
            rawValue: UInt(storedModifiers ?? Int(defaultHotkeyModifiers.rawValue))
        ).intersection(.deviceIndependentFlagsMask)

        return HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers)
    }

    static func save(_ configuration: HotkeyConfiguration, defaults: UserDefaults = .standard) {
        defaults.set(Int(configuration.keyCode), forKey: globalHotkeyKeyCodePreferenceKey)
        defaults.set(
            Int(configuration.modifiers.intersection(.deviceIndependentFlagsMask).rawValue),
            forKey: globalHotkeyModifiersPreferenceKey
        )
    }
}

enum HotkeyFormatter {
    static func displayString(for configuration: HotkeyConfiguration) -> String {
        let modifiers = configuration.modifiers.intersection(.deviceIndependentFlagsMask)
        let modifierSymbols = modifierSymbolsString(from: modifiers)
        let keyName = keyNameForKeyCode(configuration.keyCode)
        return "\(modifierSymbols)\(keyName)"
    }

    private static func modifierSymbolsString(from modifiers: NSEvent.ModifierFlags) -> String {
        var components: [String] = []
        if modifiers.contains(.control) { components.append("⌃") }
        if modifiers.contains(.option) { components.append("⌥") }
        if modifiers.contains(.shift) { components.append("⇧") }
        if modifiers.contains(.command) { components.append("⌘") }
        return components.joined()
    }

    private static func keyNameForKeyCode(_ keyCode: CGKeyCode) -> String {
        // Letters and numbers
        let mapping: [CGKeyCode: String] = [
            CGKeyCode(kVK_ANSI_A): "A", CGKeyCode(kVK_ANSI_B): "B", CGKeyCode(kVK_ANSI_C): "C",
            CGKeyCode(kVK_ANSI_D): "D", CGKeyCode(kVK_ANSI_E): "E", CGKeyCode(kVK_ANSI_F): "F",
            CGKeyCode(kVK_ANSI_G): "G", CGKeyCode(kVK_ANSI_H): "H", CGKeyCode(kVK_ANSI_I): "I",
            CGKeyCode(kVK_ANSI_J): "J", CGKeyCode(kVK_ANSI_K): "K", CGKeyCode(kVK_ANSI_L): "L",
            CGKeyCode(kVK_ANSI_M): "M", CGKeyCode(kVK_ANSI_N): "N", CGKeyCode(kVK_ANSI_O): "O",
            CGKeyCode(kVK_ANSI_P): "P", CGKeyCode(kVK_ANSI_Q): "Q", CGKeyCode(kVK_ANSI_R): "R",
            CGKeyCode(kVK_ANSI_S): "S", CGKeyCode(kVK_ANSI_T): "T", CGKeyCode(kVK_ANSI_U): "U",
            CGKeyCode(kVK_ANSI_V): "V", CGKeyCode(kVK_ANSI_W): "W", CGKeyCode(kVK_ANSI_X): "X",
            CGKeyCode(kVK_ANSI_Y): "Y", CGKeyCode(kVK_ANSI_Z): "Z",
            CGKeyCode(kVK_ANSI_0): "0", CGKeyCode(kVK_ANSI_1): "1", CGKeyCode(kVK_ANSI_2): "2",
            CGKeyCode(kVK_ANSI_3): "3", CGKeyCode(kVK_ANSI_4): "4", CGKeyCode(kVK_ANSI_5): "5",
            CGKeyCode(kVK_ANSI_6): "6", CGKeyCode(kVK_ANSI_7): "7", CGKeyCode(kVK_ANSI_8): "8",
            CGKeyCode(kVK_ANSI_9): "9",
            CGKeyCode(kVK_Space): "Space", CGKeyCode(kVK_Return): "Return",
            CGKeyCode(kVK_Escape): "Escape", CGKeyCode(kVK_Delete): "Delete",
            CGKeyCode(kVK_ForwardDelete): "Forward Delete",
            CGKeyCode(kVK_Tab): "Tab",
            CGKeyCode(kVK_LeftArrow): "←", CGKeyCode(kVK_RightArrow): "→",
            CGKeyCode(kVK_UpArrow): "↑", CGKeyCode(kVK_DownArrow): "↓",
            CGKeyCode(kVK_Home): "Home", CGKeyCode(kVK_End): "End",
            CGKeyCode(kVK_PageUp): "Page Up", CGKeyCode(kVK_PageDown): "Page Down",
            CGKeyCode(kVK_Help): "Help"
        ]

        if let name = mapping[keyCode] {
            return name
        }

        let functionKeys: [CGKeyCode: String] = [
            CGKeyCode(kVK_F1): "F1", CGKeyCode(kVK_F2): "F2", CGKeyCode(kVK_F3): "F3",
            CGKeyCode(kVK_F4): "F4", CGKeyCode(kVK_F5): "F5", CGKeyCode(kVK_F6): "F6",
            CGKeyCode(kVK_F7): "F7", CGKeyCode(kVK_F8): "F8", CGKeyCode(kVK_F9): "F9",
            CGKeyCode(kVK_F10): "F10", CGKeyCode(kVK_F11): "F11", CGKeyCode(kVK_F12): "F12",
            CGKeyCode(kVK_F13): "F13", CGKeyCode(kVK_F14): "F14", CGKeyCode(kVK_F15): "F15",
            CGKeyCode(kVK_F16): "F16", CGKeyCode(kVK_F17): "F17", CGKeyCode(kVK_F18): "F18",
            CGKeyCode(kVK_F19): "F19", CGKeyCode(kVK_F20): "F20"
        ]

        if let functionName = functionKeys[keyCode] {
            return functionName
        }

        return "#\(Int(keyCode))"
    }
}
