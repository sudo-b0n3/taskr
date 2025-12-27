// taskr/taskr/CustomTextField.swift
import SwiftUI
import AppKit

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void = {}
    var onTextChange: (String) -> Void = { _ in } // To update suggestions
    var onTab: () -> Void = {}
    var onShiftTab: () -> Void = {}
    var onArrowDown: () -> Bool = { false }
    var onArrowUp: () -> Bool = { false }
    var fieldTextColor: NSColor? = nil
    var placeholderTextColor: NSColor? = nil

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.font = TaskrTypography.scaledNSFont(for: .body, scale: context.environment.taskrFontScale)
        textField.delegate = context.coordinator
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.cell?.lineBreakMode = .byWordWrapping
        textField.cell?.usesSingleLineMode = false
        applyPlaceholder(to: textField)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.textColor = fieldTextColor ?? NSColor.labelColor
        textField.focusRingType = .none
        textField.bezelStyle = .roundedBezel // This might not matter if bordered is false, but keeping it clean
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Update NSTextField when SwiftUI state changes, but be careful about cursor position
        if nsView.stringValue != text { // Avoid resetting if text is same
            // Mark that we're doing a programmatic update to prevent delegate feedback loop
            context.coordinator.isProgrammaticUpdate = true
            nsView.stringValue = text
            context.coordinator.isProgrammaticUpdate = false
        }

        if let fg = fieldTextColor, nsView.textColor != fg {
            nsView.textColor = fg
        }
        nsView.font = TaskrTypography.scaledNSFont(for: .body, scale: context.environment.taskrFontScale)
        applyPlaceholder(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyPlaceholder(to textField: NSTextField) {
        let placeholderColor = placeholderTextColor ?? NSColor.placeholderTextColor
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTextField
        var isProgrammaticUpdate: Bool = false

        init(_ textField: CustomTextField) {
            self.parent = textField
        }

        func controlTextDidChange(_ obj: Notification) {
            // Skip if this is a programmatic update to avoid feedback loops
            guard !isProgrammaticUpdate else { return }
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
            parent.onTextChange(textField.stringValue) // Notify for suggestions
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            // This is called when focus is lost, not necessarily on commit.
            // parent.onCommit() // We handle commit via doCommandBy selector
        }
        
        // This is crucial for handling special keys like Enter, Tab, Arrows
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                parent.onCommit()
                return true // Command was handled
            } else if commandSelector == #selector(NSTextView.insertTab(_:)) {
                parent.onTab()
                return true // Command was handled
            } else if commandSelector == #selector(NSTextView.insertBacktab(_:)) {
                // Shift-Tab is often insertBacktab
                parent.onShiftTab()
                return true
            } else if commandSelector == #selector(NSTextView.moveDown(_:)) {
                return parent.onArrowDown()
            } else if commandSelector == #selector(NSTextView.moveUp(_:)) {
                return parent.onArrowUp()
            }
            return false // Command was not handled by us, let default behavior proceed
        }
    }
}
