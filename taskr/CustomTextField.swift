// taskr/taskr/CustomTextField.swift
import SwiftUI
import AppKit

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onTextChange: (String) -> Void // To update suggestions
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.backgroundColor = NSColor.textBackgroundColor // Standard background
        textField.focusRingType = .default // Show focus ring
        textField.bezelStyle = .roundedBezel // Standard rounded text field style
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
