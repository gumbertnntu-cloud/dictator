import AppKit
import DictatorCore
import SwiftUI

struct HotkeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (Hotkey) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class CaptureView: NSView {
        var isRecording = false
        var onCapture: ((Hotkey) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return }
            let hotkey = Hotkey(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                displayName: displayName(for: event)
            )
            onCapture?(hotkey)
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording else {
                super.flagsChanged(with: event)
                return
            }

            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers == Hotkey.functionModifier else { return }
            onCapture?(
                Hotkey(
                    keyCode: Hotkey.modifierOnlyKeyCode,
                    modifiers: modifiers,
                    displayName: "Fn"
                )
            )
        }

        private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
            var result: UInt32 = 0
            if flags.contains(.command) { result += 256 }
            if flags.contains(.shift) { result += 512 }
            if flags.contains(.option) { result += 2_048 }
            if flags.contains(.control) { result += 4_096 }
            if flags.contains(.function) { result += Hotkey.functionModifier }
            return result
        }

        private func displayName(for event: NSEvent) -> String {
            var parts: [String] = []
            if event.modifierFlags.contains(.function) { parts.append("Fn") }
            if event.modifierFlags.contains(.control) { parts.append("⌃") }
            if event.modifierFlags.contains(.option) { parts.append("⌥") }
            if event.modifierFlags.contains(.shift) { parts.append("⇧") }
            if event.modifierFlags.contains(.command) { parts.append("⌘") }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? "Key"
            if event.keyCode == 49 {
                parts.append("Space")
            } else {
                parts.append(key)
            }
            return parts.joined()
        }
    }
}
