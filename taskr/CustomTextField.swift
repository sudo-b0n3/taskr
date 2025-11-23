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
    var onArrowDown: () -> Void = {}
    var onArrowUp: () -> Void = {}
    var fieldTextColor: NSColor? = nil
    var placeholderTextColor: NSColor? = nil

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        applyPlaceholder(to: textField)
        textField.isBordered = true
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.textColor = fieldTextColor ?? NSColor.labelColor
        textField.focusRingType = .none
        textField.bezelStyle = .roundedBezel
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Update NSTextField when SwiftUI state changes, but be careful about cursor position
        if nsView.stringValue != text { // Avoid resetting if text is same
            nsView.stringValue = text

            // Attempt to restore cursor position (can be tricky)
            // This is a simplified approach; more robust solutions might be needed
            // if text is being manipulated programmatically frequently while user is typing.
            // For autocomplete selection, 'text' binding is updated, so this helps.
            // let currentSelectedRange = nsView.currentEditor()?.selectedRange
            // nsView.stringValue = text
            // if let range = currentSelectedRange {
            //    nsView.currentEditor()?.selectedRange = NSRange(location: min(text.count, range.location), length: 0)
            // }
        }

        if let fg = fieldTextColor, nsView.textColor != fg {
            nsView.textColor = fg
        }
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

        init(_ textField: CustomTextField) {
            self.parent = textField
        }

        func controlTextDidChange(_ obj: Notification) {
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
                parent.onArrowDown()
                return true // Command was handled
            } else if commandSelector == #selector(NSTextView.moveUp(_:)) {
                parent.onArrowUp()
                return true // Command was handled
            }
            return false // Command was not handled by us, let default behavior proceed
        }
    }
}
