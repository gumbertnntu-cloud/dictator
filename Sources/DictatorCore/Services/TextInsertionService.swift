import AppKit
import ApplicationServices
import Foundation

public final class TextInsertionTarget {
    fileprivate let element: AXUIElement
    fileprivate let processIdentifier: pid_t

    fileprivate init(element: AXUIElement, processIdentifier: pid_t) {
        self.element = element
        self.processIdentifier = processIdentifier
    }
}

public final class TextInsertionService {
    public init() {}

    public func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func captureTarget() -> TextInsertionTarget? {
        guard AXIsProcessTrusted(), let focusedElement = focusedElement() else { return nil }
        guard !isSecureField(focusedElement) else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(focusedElement, &pid)

        return TextInsertionTarget(
            element: focusedElement,
            processIdentifier: pid
        )
    }

    public func insert(text: String, target: TextInsertionTarget?) -> InsertionResult {
        guard AXIsProcessTrusted() else {
            return .failed
        }

        guard let target else { return .focusLost }
        let focusedElement = target.element
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

        _ = pasteIntoTargetApp(text, target: target)
        return .unsupportedTarget
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
        return pasteIntoFocusedApp(text, targetProcessIdentifier: target?.processIdentifier)
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

    private func pasteIntoFocusedApp(_ text: String, targetProcessIdentifier: pid_t? = nil) -> Bool {
        copyToPasteboard(text)

        guard
            let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        if let targetProcessIdentifier, targetProcessIdentifier > 0 {
            vDown.postToPid(targetProcessIdentifier)
            vUp.postToPid(targetProcessIdentifier)
        } else {
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
        }
        return true
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
}
