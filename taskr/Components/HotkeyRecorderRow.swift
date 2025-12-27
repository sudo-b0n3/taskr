import SwiftUI
import AppKit

struct HotkeyRecorderRow: View {
    var currentDescription: String
    @Binding var isRecording: Bool
    let palette: ThemePalette
    var onCapture: (HotkeyConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shortcut")
                    .taskrFont(.body)
                    .foregroundColor(palette.primaryTextColor)
                Spacer()
                Text(currentDescription)
                    .taskrFont(.body)
                    .foregroundColor(palette.secondaryTextColor)
                Button(isRecording ? "Press keys..." : "Change") {
                    isRecording = true
                }
                .buttonStyle(.bordered)
            }
            Text("Pick the key combination used for the global hotkey.")
                .taskrFont(.caption)
                .foregroundColor(palette.secondaryTextColor)
        }
        .padding(.vertical, 8)
        .background(
            HotkeyCaptureRepresentable(isRecording: $isRecording) { keyCode, modifiers in
                let configuration = HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers)
                onCapture(configuration)
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        )
    }
}

private struct HotkeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (CGKeyCode, NSEvent.ModifierFlags) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, onCapture: onCapture)
    }

    func makeNSView(context: Context) -> HotkeyCaptureView {
        let view = HotkeyCaptureView()
        view.captureHandler = { keyCode, modifiers in
            context.coordinator.onCapture(keyCode, modifiers)
            context.coordinator.isRecording.wrappedValue = false
        }
        view.cancelHandler = {
            context.coordinator.isRecording.wrappedValue = false
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureView, context: Context) {
        nsView.captureHandler = { keyCode, modifiers in
            context.coordinator.onCapture(keyCode, modifiers)
            context.coordinator.isRecording.wrappedValue = false
        }
        nsView.cancelHandler = {
            context.coordinator.isRecording.wrappedValue = false
        }

        if isRecording {
            DispatchQueue.main.async {
                nsView.startRecording()
            }
        }
    }

    class Coordinator {
        var isRecording: Binding<Bool>
        let onCapture: (CGKeyCode, NSEvent.ModifierFlags) -> Void

        init(isRecording: Binding<Bool>, onCapture: @escaping (CGKeyCode, NSEvent.ModifierFlags) -> Void) {
            self.isRecording = isRecording
            self.onCapture = onCapture
        }
    }
}

private final class HotkeyCaptureView: NSView {
    var captureHandler: ((CGKeyCode, NSEvent.ModifierFlags) -> Void)?
    var cancelHandler: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.opacity = 0.01
    }

    func startRecording() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        guard modifiers.intersection(allowedModifiers).isEmpty == false else {
            NSSound.beep()
            return
        }
        captureHandler?(event.keyCode, modifiers)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }
}
