import AppKit
import ApplicationServices
import Foundation

public final class TextInsertionService {
    public init() {}

    public func insert(text: String) -> InsertionResult {
        guard AXIsProcessTrusted() else { return .failed }

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

        return .unsupportedTarget
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
}
