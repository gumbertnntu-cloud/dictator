import AppKit
import ApplicationServices
import Foundation

public final class TextInsertionTarget {
    fileprivate let element: AXUIElement
    fileprivate let processIdentifier: pid_t
    fileprivate let applicationElement: AXUIElement

    fileprivate init(element: AXUIElement, processIdentifier: pid_t) {
        self.element = element
        self.processIdentifier = processIdentifier
        self.applicationElement = AXUIElementCreateApplication(processIdentifier)
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
        DictatorLog.insertion.info(
            "Insertion target captured pid=\(pid, privacy: .public) role=\(self.role(of: focusedElement) ?? "unknown", privacy: .public)"
        )

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

        if pasteIntoTargetApp(text, target: target) {
            DictatorLog.insertion.info("Insertion succeeded method=paste-chain")
            return .inserted
        }

        let selectedTextResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedTextResult == .success {
            DictatorLog.insertion.info("Insertion succeeded method=AXSelectedText")
            return .inserted
        }

        if insertByAccessibilityValue(text, into: focusedElement) {
            DictatorLog.insertion.info("Insertion succeeded method=AXValue")
            return .inserted
        }

        DictatorLog.insertion.error("Insertion failed: all methods rejected target")
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
        return pasteIntoFocusedApp(text, target: target)
    }

    private func focus(target: TextInsertionTarget?, element: AXUIElement) {
        if let target,
           let app = NSRunningApplication(processIdentifier: target.processIdentifier) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        _ = AXUIElementSetAttributeValue(target?.applicationElement ?? element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.18)
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

    private func pasteIntoFocusedApp(_ text: String, target: TextInsertionTarget? = nil) -> Bool {
        copyToPasteboard(text)
        focus(target: target, element: target?.element ?? focusedElement() ?? AXUIElementCreateSystemWide())

        if pressPasteMenuItem(in: target?.applicationElement) {
            DictatorLog.insertion.info("Paste chain succeeded method=menuPaste")
            return true
        }

        if postCommandVWithHIDEvents() {
            DictatorLog.insertion.info("Paste chain posted method=globalCommandV")
            return true
        }

        let pidResult = postCommandVToProcessIdentifier(target?.processIdentifier)
        if pidResult {
            DictatorLog.insertion.info("Paste chain posted method=pidCommandV")
        } else {
            DictatorLog.insertion.error("Paste chain failed to post Command-V")
        }
        return pidResult
    }

    private func postCommandVWithHIDEvents() -> Bool {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        source.localEventsSuppressionInterval = 0
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.03)
        vUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)
        return true
    }

    private func postCommandVToProcessIdentifier(_ processIdentifier: pid_t?) -> Bool {
        guard
            let processIdentifier,
            processIdentifier > 0,
            let source = CGEventSource(stateID: .combinedSessionState),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        source.localEventsSuppressionInterval = 0
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.postToPid(processIdentifier)
        Thread.sleep(forTimeInterval: 0.03)
        vUp.postToPid(processIdentifier)
        Thread.sleep(forTimeInterval: 0.12)
        return true
    }

    private func pressPasteMenuItem(in applicationElement: AXUIElement?) -> Bool {
        guard let applicationElement else { return false }

        var menuBarValue: CFTypeRef?
        let menuBarError = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXMenuBarAttribute as CFString,
            &menuBarValue
        )
        guard menuBarError == .success, let menuBarValue else {
            DictatorLog.insertion.debug("Menu paste unavailable error=\(String(describing: menuBarError), privacy: .public)")
            return false
        }

        let menuBar = menuBarValue as! AXUIElement
        return pressPasteMenuItem(in: menuBar, depth: 0)
    }

    private func pressPasteMenuItem(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 8 else { return false }

        if isPasteMenuItem(element), isEnabled(element) {
            let actionError = AXUIElementPerformAction(element, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.12)
            return actionError == .success
        }

        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )
        guard childrenError == .success, let children = childrenValue as? [AXUIElement] else {
            return false
        }

        for child in children where pressPasteMenuItem(in: child, depth: depth + 1) {
            return true
        }

        return false
    }

    private func isPasteMenuItem(_ element: AXUIElement) -> Bool {
        guard role(of: element) == "AXMenuItem", let title = title(of: element) else {
            return false
        }

        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "paste" || normalized == "вставить"
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        var enabledValue: CFTypeRef?
        let enabledError = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &enabledValue
        )
        guard enabledError == .success, let enabled = enabledValue as? Bool else {
            return true
        }
        return enabled
    }

    private func role(of element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        guard roleError == .success else { return nil }
        return roleValue as? String
    }

    private func title(of element: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        let titleError = AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        guard titleError == .success else { return nil }
        return titleValue as? String
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
