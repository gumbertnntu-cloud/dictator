import AppKit
import Combine
import DictatorCore
import SwiftUI

@MainActor
final class StatusBubbleWindowController {
    private let controller: DictationController
    private let audioCapture: AudioCaptureService
    private var window: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(controller: DictationController, audioCapture: AudioCaptureService) {
        self.controller = controller
        self.audioCapture = audioCapture
        controller.$state
            .sink { [weak self] state in
                self?.syncWindow(for: state)
            }
            .store(in: &cancellables)
    }

    private func syncWindow(for state: DictationState) {
        guard state.isVisibleInBubble else {
            window?.orderOut(nil)
            return
        }

        if window == nil {
            createWindow()
        }
        positionWindow()
        window?.orderFrontRegardless()
    }

    private func createWindow() {
        let hostingView = NSHostingView(
            rootView: StatusBubbleView(controller: controller, audioCapture: audioCapture)
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        window = panel
    }

    private func positionWindow() {
        guard let window, let screen = NSScreen.main else { return }
        let size = window.contentView?.fittingSize ?? NSSize(width: 360, height: 84)

        if let caretRect = controller.capturedTargetRect {
            let origin = originNearCaret(caretRect: caretRect, windowSize: size)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            return
        }

        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 28
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func originNearCaret(caretRect: NSRect, windowSize: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(caretRect.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let spacing: CGFloat = 10

        var x = caretRect.minX
        var y = caretRect.minY - windowSize.height - spacing

        if y < visible.minY {
            y = caretRect.maxY + spacing
        }

        x = min(max(x, visible.minX + 8), visible.maxX - windowSize.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - windowSize.height - 8)

        return NSPoint(x: x, y: y)
    }
}
