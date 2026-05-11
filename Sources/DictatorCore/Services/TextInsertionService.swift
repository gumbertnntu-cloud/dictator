import AppKit
import ApplicationServices
import Foundation

public final class TextInsertionTarget {
    fileprivate let element: AXUIElement
    fileprivate let processIdentifier: pid_t
    public let screenRect: CGRect?

    fileprivate init(element: AXUIElement, processIdentifier: pid_t, screenRect: CGRect?) {
        self.element = element
        self.processIdentifier = processIdentifier
        self.screenRect = screenRect
    }
}

public final class TextInsertionService {
    public init() {}

    public func captureTarget() -> TextInsertionTarget? {
        guard AXIsProcessTrusted(), let focusedElement = focusedElement() else { return nil }
        guard !isSecureField(focusedElement) else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(focusedElement, &pid)

        return TextInsertionTarget(
            element: focusedElement,
            processIdentifier: pid,
            screenRect: rectForBubble(near: focusedElement)
        )
    }

    public func insert(text: String, target: TextInsertionTarget?) -> InsertionResult {
        guard AXIsProcessTrusted() else {
            return pasteIntoFocusedApp(text) ? .inserted : .failed
        }

        guard let focusedElement = target?.element ?? focusedElement() else { return .focusLost }
        if isSecureField(focusedElement) {
            return .secureField
        }
        focus(target: target, element: focusedElement)

        let selectedTextResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedTextResult == .success {
            return .inserted
        }

        if insertByAccessibilityValue(text, into: focusedElement) {
            return .inserted
        }

        return pasteIntoTargetApp(text, target: target) ? .inserted : .unsupportedTarget
    }

    public func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusError == .success, let focusedValue else { return nil }
        return (focusedValue as! AXUIElement)
    }

    private func isSecureField(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        guard roleError == .success, let role = roleValue as? String else {
            return false
        }
        return role == "AXSecureTextField"
    }

    private func pasteIntoTargetApp(_ text: String, target: TextInsertionTarget?) -> Bool {
        if let target {
            focus(target: target, element: target.element)
        }
        return pasteIntoFocusedApp(text)
    }

    private func focus(target: TextInsertionTarget?, element: AXUIElement) {
        if let target,
           let app = NSRunningApplication(processIdentifier: target.processIdentifier) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.08)
    }

    private func insertByAccessibilityValue(_ text: String, into element: AXUIElement) -> Bool {
        var currentValue: CFTypeRef?
        let valueError = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )
        guard valueError == .success, let existing = currentValue as? String else {
            return false
        }

        let selectedRange = selectedTextRange(for: element) ?? CFRange(location: (existing as NSString).length, length: 0)
        let nsRange = NSRange(location: max(selectedRange.location, 0), length: max(selectedRange.length, 0))
        let existingNSString = existing as NSString
        guard NSMaxRange(nsRange) <= existingNSString.length else {
            return false
        }

        let updated = existingNSString.replacingCharacters(in: nsRange, with: text)
        let setError = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updated as CFTypeRef
        )
        guard setError == .success else { return false }

        var newRange = CFRange(location: nsRange.location + (text as NSString).length, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &newRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
        }
        return true
    }

    private func pasteIntoFocusedApp(_ text: String) -> Bool {
        copyToPasteboard(text)

        guard
            let commandDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false)
        else {
            return false
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }

    private func rectForBubble(near element: AXUIElement) -> CGRect? {
        if let caretRect = selectedTextRangeRect(for: element) {
            return convertAccessibilityRect(caretRect)
        }
        if let elementRect = elementFrame(for: element) {
            return convertAccessibilityRect(elementRect)
        }
        return nil
    }

    private func selectedTextRangeRect(for element: AXUIElement) -> CGRect? {
        guard let selectedRange = selectedTextRange(for: element) else { return nil }
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

    private func selectedTextRange(for element: AXUIElement) -> CFRange? {
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
        return selectedRange
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

    private func convertAccessibilityRect(_ rect: CGRect) -> CGRect {
        let directRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(directRect) }) {
            return directRect
        }

        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(
            x: rect.origin.x,
            y: maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
