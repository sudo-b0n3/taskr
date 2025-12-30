import SwiftUI
import AppKit

/// An expanding text input for task creation that grows up to 3 lines.
/// Enter commits, Option+Enter inserts newline, Escape clears.
struct ExpandingTaskInput: View {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onTextChange: (String) -> Void
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onArrowDown: () -> Bool
    var onArrowUp: () -> Bool
    var fieldTextColor: NSColor?
    var placeholderTextColor: NSColor?
    
    @State private var textHeight: CGFloat = 20
    @Environment(\.taskrFontScale) private var fontScale
    
    /// Maximum height for 3 lines of text
    private var maxHeight: CGFloat {
        let lineHeight = TaskrTypography.lineHeight(for: .body, scale: fontScale)
        return lineHeight * 3 + 8 // 3 lines + some padding
    }
    
    var body: some View {
        ExpandingTaskInputRepresentable(
            text: $text,
            textHeight: $textHeight,
            placeholder: placeholder,
            onCommit: onCommit,
            onTextChange: onTextChange,
            onTab: onTab,
            onShiftTab: onShiftTab,
            onArrowDown: onArrowDown,
            onArrowUp: onArrowUp,
            fieldTextColor: fieldTextColor,
            placeholderTextColor: placeholderTextColor
        )
        .frame(height: min(max(textHeight, 20), maxHeight))
    }
}

struct ExpandingTaskInputRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    var placeholder: String
    var onCommit: () -> Void
    var onTextChange: (String) -> Void
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onArrowDown: () -> Bool
    var onArrowUp: () -> Bool
    var fieldTextColor: NSColor?
    var placeholderTextColor: NSColor?
    
    @Environment(\.taskrFontScale) private var fontScale
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = PlaceholderTextView()
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
        textView.font = TaskrTypography.scaledNSFont(for: .body, scale: fontScale)
        textView.textColor = fieldTextColor ?? .labelColor
        textView.insertionPointColor = fieldTextColor ?? .labelColor
        
        // Configure placeholder
        textView.placeholderString = placeholder
        textView.placeholderColor = placeholderTextColor ?? .placeholderTextColor
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        
        // Update text if changed externally
        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.updateHeight()
            textView.needsDisplay = true // Refresh placeholder visibility
        }
        
        // Update font
        let newFont = TaskrTypography.scaledNSFont(for: .body, scale: fontScale)
        if textView.font != newFont {
            textView.font = newFont
            context.coordinator.updateHeight()
        }
        
        // Update colors
        if let color = fieldTextColor, textView.textColor != color {
            textView.textColor = color
            textView.insertionPointColor = color
        }
        
        if let placeholderColor = placeholderTextColor, textView.placeholderColor != placeholderColor {
            textView.placeholderColor = placeholderColor
            textView.needsDisplay = true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExpandingTaskInputRepresentable
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isProgrammaticUpdate: Bool = false
        
        init(_ parent: ExpandingTaskInputRepresentable) {
            self.parent = parent
        }
        
        func updateHeight() {
            guard let textView = textView else { return }
            
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(ceil(usedRect.height) + 6, 20) // +6 for inset padding
            
            if abs(parent.textHeight - newHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.textHeight = newHeight
                }
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange(textView.string)
            updateHeight()
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Option key is pressed - allow newline
                if NSEvent.modifierFlags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Otherwise, commit
                parent.onCommit()
                return true
            }
            
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onShiftTab()
                return true
            }
            
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                // Only consume if arrow handler returns true (e.g., for autocomplete navigation)
                return parent.onArrowDown()
            }
            
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return parent.onArrowUp()
            }
            
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape - clear the text
                textView.string = ""
                parent.text = ""
                parent.onTextChange("")
                updateHeight()
                return true
            }
            
            return false
        }
        
        func textDidEndEditing(_ notification: Notification) {
            // Focus lost - nothing special needed
        }
    }
}

/// NSTextView subclass that displays a placeholder when empty
class PlaceholderTextView: NSTextView {
    var placeholderString: String = ""
    var placeholderColor: NSColor = .placeholderTextColor
    
    override var string: String {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw placeholder if empty and not first responder with selection
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: placeholderColor,
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            let inset = textContainerInset
            let placeholderRect = NSRect(
                x: inset.width + (textContainer?.lineFragmentPadding ?? 0),
                y: inset.height,
                width: bounds.width - inset.width * 2,
                height: bounds.height - inset.height * 2
            )
            placeholderString.draw(in: placeholderRect, withAttributes: attrs)
        }
    }
    
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
