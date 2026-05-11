import AppKit
import ApplicationServices
import Foundation

struct CaretPositionService {
    func focusedTextRect() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusError == .success, let focusedValue else { return nil }

        let focusedElement = focusedValue as! AXUIElement
        if let caretRect = selectedTextRangeRect(for: focusedElement) {
            return convertAccessibilityRect(caretRect)
        }

        if let elementRect = elementFrame(for: focusedElement) {
            return convertAccessibilityRect(elementRect)
        }

        return nil
    }

    private func selectedTextRangeRect(for element: AXUIElement) -> CGRect? {
        var selectedRangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )
        guard rangeError == .success, let selectedRangeValue else { return nil }

        let rangeAXValue = selectedRangeValue as! AXValue
        var selectedRange = CFRange()
        guard AXValueGetValue(rangeAXValue, .cfRange, &selectedRange) else { return nil }

        var range = selectedRange
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }

        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            parameter,
            &boundsValue
        )
        guard boundsError == .success, let boundsValue else { return nil }

        let boundsAXValue = boundsValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(boundsAXValue, .cgRect, &rect), rect != .zero else { return nil }
        return rect
    }

    private func elementFrame(for element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard
            positionError == .success,
            sizeError == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionAXValue, .cgPoint, &point),
            AXValueGetValue(sizeAXValue, .cgSize, &size),
            size != .zero
        else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }

    private func convertAccessibilityRect(_ rect: CGRect) -> NSRect {
        let directRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(directRect) }) {
            return directRect
        }

        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return NSRect(
            x: rect.origin.x,
            y: maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
