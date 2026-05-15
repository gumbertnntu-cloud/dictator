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
        guard AXIsProcessTrusted() else { return nil }

        if let focusedElement = focusedElement() {
            if isSecureField(focusedElement) { return nil }
            var pid: pid_t = 0
            AXUIElementGetPid(focusedElement, &pid)
            DictatorLog.insertion.info(
                "Insertion target captured (focused) pid=\(pid, privacy: .public) role=\(self.role(of: focusedElement) ?? "unknown", privacy: .public)"
            )
            return TextInsertionTarget(element: focusedElement, processIdentifier: pid)
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let pid = frontApp.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            DictatorLog.insertion.info(
                "Insertion target captured (frontmost-app fallback) pid=\(pid, privacy: .public) bundle=\(frontApp.bundleIdentifier ?? "?", privacy: .public)"
            )
            return TextInsertionTarget(element: appElement, processIdentifier: pid)
        }

        DictatorLog.insertion.error("Insertion target unavailable: no focused element, no frontmost app")
        return nil
    }

    public func caretBounds(target: TextInsertionTarget?) -> CGRect? {
        guard AXIsProcessTrusted(), let target else { return nil }
        let element = target.element

        if let rect = caretBoundsViaSelectionRange(element: element) {
            let converted = Self.convertAXRectToScreen(rect)
            DictatorLog.insertion.debug(
                "Caret bounds (range) ax=\(String(describing: rect), privacy: .public) screen=\(String(describing: converted), privacy: .public)"
            )
            if Self.rectIsVisibleOnAnyScreen(converted) {
                return converted
            }
        }
        if let rect = elementBounds(element: element) {
            let converted = Self.convertAXRectToScreen(rect)
            DictatorLog.insertion.debug(
                "Caret bounds (element) ax=\(String(describing: rect), privacy: .public) screen=\(String(describing: converted), privacy: .public)"
            )
            if Self.rectIsVisibleOnAnyScreen(converted) {
                return converted
            }
        }
        DictatorLog.insertion.info("Caret bounds unavailable: AX returned no usable rect")
        return nil
    }

    private static func rectIsVisibleOnAnyScreen(_ rect: CGRect) -> Bool {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite else {
            return false
        }
        return NSScreen.screens.contains { $0.frame.intersects(rect) }
    }

    private func caretBoundsViaSelectionRange(element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeStatus == .success, let rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard boundsStatus == .success, let boundsValue else { return nil }

        var rect = CGRect.zero
        let axRect = boundsValue as! AXValue
        guard AXValueGetValue(axRect, .cgRect, &rect) else { return nil }
        if rect.width.isFinite, rect.height.isFinite, rect.width >= 0, rect.height >= 0 {
            let normalizedWidth = max(rect.width, 2)
            let normalizedHeight = max(rect.height, 16)
            return CGRect(x: rect.origin.x, y: rect.origin.y, width: normalizedWidth, height: normalizedHeight)
        }
        return nil
    }

    private func elementBounds(element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let positionValue else { return nil }
        var origin = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin) else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sizeValue else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: origin, size: size)
    }

    private static func convertAXRectToScreen(_ axRect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return axRect }
        let primaryHeight = primary.frame.height
        let flippedY = primaryHeight - axRect.origin.y - axRect.size.height
        return CGRect(x: axRect.origin.x, y: flippedY, width: axRect.size.width, height: axRect.size.height)
    }

    public func insert(text: String, target: TextInsertionTarget?) async -> InsertionResult {
        guard AXIsProcessTrusted() else {
            return .failed
        }

        guard let target else { return .focusLost }
        let focusedElement = target.element
        if isSecureField(focusedElement) {
            return .secureField
        }
        await focus(target: target, element: focusedElement)

        if await pasteIntoTargetApp(text, target: target) {
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

    private func snapshotPasteboard() -> [NSPasteboardItem] {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let copy = NSPasteboardItem()
            var copiedAny = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    copiedAny = true
                }
            }
            return copiedAny ? copy : nil
        }
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
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

    private func pasteIntoTargetApp(_ text: String, target: TextInsertionTarget?) async -> Bool {
        if let target {
            await focus(target: target, element: target.element)
        }
        return await pasteIntoFocusedApp(text, target: target)
    }

    private func focus(target: TextInsertionTarget?, element: AXUIElement) async {
        if let target,
           let app = NSRunningApplication(processIdentifier: target.processIdentifier) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        _ = AXUIElementSetAttributeValue(target?.applicationElement ?? element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: 180_000_000)
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

    private func pasteIntoFocusedApp(_ text: String, target: TextInsertionTarget? = nil) async -> Bool {
        let savedItems = snapshotPasteboard()
        copyToPasteboard(text)
        defer {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                self?.restorePasteboard(savedItems)
                DictatorLog.insertion.info("Pasteboard restored items=\(savedItems.count, privacy: .public)")
            }
        }

        await focus(target: target, element: target?.element ?? focusedElement() ?? AXUIElementCreateSystemWide())

        if await pressPasteMenuItem(in: target?.applicationElement) {
            DictatorLog.insertion.info("Paste chain succeeded method=menuPaste")
            return true
        }

        if await postCommandVWithHIDEvents() {
            DictatorLog.insertion.info("Paste chain posted method=globalCommandV")
            return true
        }

        let pidResult = await postCommandVToProcessIdentifier(target?.processIdentifier)
        if pidResult {
            DictatorLog.insertion.info("Paste chain posted method=pidCommandV")
        } else {
            DictatorLog.insertion.error("Paste chain failed to post Command-V")
        }
        return pidResult
    }

    private func postCommandVWithHIDEvents() async -> Bool {
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
        try? await Task.sleep(nanoseconds: 30_000_000)
        vUp.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 120_000_000)
        return true
    }

    private func postCommandVToProcessIdentifier(_ processIdentifier: pid_t?) async -> Bool {
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
        try? await Task.sleep(nanoseconds: 30_000_000)
        vUp.postToPid(processIdentifier)
        try? await Task.sleep(nanoseconds: 120_000_000)
        return true
    }

    private func pressPasteMenuItem(in applicationElement: AXUIElement?) async -> Bool {
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
        return await pressPasteMenuItem(in: menuBar, depth: 0)
    }

    private func pressPasteMenuItem(in element: AXUIElement, depth: Int) async -> Bool {
        guard depth < 8 else { return false }

        if isPasteMenuItem(element), isEnabled(element) {
            let actionError = AXUIElementPerformAction(element, kAXPressAction as CFString)
            try? await Task.sleep(nanoseconds: 120_000_000)
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

        for child in children {
            if await pressPasteMenuItem(in: child, depth: depth + 1) {
                return true
            }
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
