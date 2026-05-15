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

        Task { @MainActor [weak self] in
            self?.positionWindow()
        }
    }

    private func createWindow() {
        let hostingView = NSHostingView(
            rootView: StatusBubbleView(controller: controller, audioCapture: audioCapture)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        window = panel
    }

    private func positionWindow() {
        guard let window else { return }
        let size = contentSize(window.contentView?.fittingSize)

        var finalRect: NSRect? = nil

        if let caret = controller.caretBoundsOnScreen() {
            let origin = bubbleOrigin(for: size, caret: caret)
            let candidate = NSRect(origin: origin, size: size)
            if rectIsVisible(candidate) {
                finalRect = candidate
            }
        }

        if finalRect == nil, let fallback = defaultPosition(for: size) {
            finalRect = fallback
        }

        guard let rect = finalRect else { return }
        window.setFrame(rect, display: true)
    }

    private func contentSize(_ size: NSSize?) -> NSSize {
        guard let size, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return NSSize(width: 120, height: 40)
        }
        return size
    }

    private func defaultPosition(for size: NSSize) -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 28
        )
        return NSRect(origin: origin, size: size)
    }

    private func rectIsVisible(_ rect: NSRect) -> Bool {
        guard rect.size.width.isFinite, rect.size.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite else {
            return false
        }
        return NSScreen.screens.contains { screen in
            screen.frame.intersects(rect)
        }
    }

    private func bubbleOrigin(for size: NSSize, caret: CGRect) -> NSPoint {
        let gap: CGFloat = 10
        let screen = screen(containing: caret) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_600, height: 1_000)

        var origin = NSPoint(
            x: caret.midX - size.width / 2,
            y: caret.minY - size.height - gap
        )

        if origin.y < visible.minY + 8 {
            origin.y = caret.maxY + gap
        }
        if origin.y + size.height > visible.maxY - 8 {
            origin.y = max(visible.minY + 8, visible.maxY - 8 - size.height)
        }

        let minX = visible.minX + 8
        let maxX = visible.maxX - 8 - size.width
        if origin.x < minX { origin.x = minX }
        if origin.x > maxX { origin.x = maxX }

        return origin
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let probe = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(probe) }
    }
}
