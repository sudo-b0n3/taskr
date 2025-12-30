import SwiftUI
import AppKit

/// A text editor that expands vertically as the user types multiple lines.
/// Enter commits, Option+Enter inserts newline, Escape cancels.
struct ExpandingTextEditor: View {
    @Binding var text: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onCancel: () -> Void
    
    @State private var textHeight: CGFloat = 20
    
    var body: some View {
        ExpandingTextEditorRepresentable(
            text: $text,
            textHeight: $textHeight,
            isTextFieldFocused: isTextFieldFocused,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
        .frame(height: max(textHeight, 20))
    }
}

struct ExpandingTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    var isTextFieldFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onCancel: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = ExpandingNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        // Focus the text view and select all
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
            context.coordinator.updateHeight()
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Only update text if changed externally
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            context.coordinator.updateHeight()
        }
        
        // Update focus state
        if isTextFieldFocused.wrappedValue {
            DispatchQueue.main.async {
                if textView.window?.firstResponder != textView {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExpandingTextEditorRepresentable
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        
        init(_ parent: ExpandingTextEditorRepresentable) {
            self.parent = parent
        }
        
        func updateHeight() {
            guard let textView = textView else { return }
            
            // Calculate required height based on text content
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(ceil(usedRect.height) + 4, 20) // +4 for some padding
            
            if abs(parent.textHeight - newHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.textHeight = newHeight
                }
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight()
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Option key is pressed - allow newline
                if NSEvent.modifierFlags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Otherwise, submit
                parent.onSubmit()
                return true
            }
            
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            
            // Arrow keys just navigate within the text - don't exit the field
            return false
        }
        

        
        func textDidEndEditing(_ notification: Notification) {
            DispatchQueue.main.async {
                self.parent.isTextFieldFocused.wrappedValue = false
            }
        }
    }
}

/// Custom NSTextView subclass to support proper expanding behavior
class ExpandingNSTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
    }
    
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
