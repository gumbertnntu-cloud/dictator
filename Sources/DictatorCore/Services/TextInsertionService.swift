import AppKit
import ApplicationServices
import Foundation

public final class TextInsertionService {
    public init() {}

    public func insert(text: String) -> InsertionResult {
        guard AXIsProcessTrusted() else {
            return pasteIntoFocusedApp(text) ? .inserted : .failed
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusError == .success, let focusedValue else { return .focusLost }

        let focusedElement = focusedValue as! AXUIElement
        if isSecureField(focusedElement) {
            return .secureField
        }

        let selectedTextResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedTextResult == .success {
            return .inserted
        }

        var currentValue: CFTypeRef?
        let valueError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )
        if valueError == .success, let existing = currentValue as? String {
            let setError = AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                (existing + text) as CFTypeRef
            )
            return setError == .success ? .inserted : .unsupportedTarget
        }

        return pasteIntoFocusedApp(text) ? .inserted : .unsupportedTarget
    }

    public func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
}
