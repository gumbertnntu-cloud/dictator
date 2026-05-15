import AppKit
import Carbon
import Foundation

public enum HotkeyPhase {
    case pressed
    case released
}

public final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localModifierMonitor: Any?
    private var globalModifierMonitor: Any?
    private var isModifierHotkeyActive = false
    private var onEvent: ((HotkeyPhase) -> Void)?
    private let hotKeyID = EventHotKeyID(signature: FourCharCode("DCTR"), id: 1)

    public init() {}

    deinit {
        unregister()
    }

    @discardableResult
    public func register(_ hotkey: Hotkey, onEvent: @escaping (HotkeyPhase) -> Void) -> Bool {
        unregister()
        self.onEvent = onEvent

        if hotkey.isModifierOnly {
            registerModifierOnlyHotkey(hotkey)
            return true
        }

        var newHotKeyRef: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )
        guard registrationStatus == noErr else {
            return false
        }
        hotKeyRef = newHotKeyRef

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            eventTypes.count,
            &eventTypes,
            selfPointer,
            &eventHandlerRef
        )

        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if let localModifierMonitor {
            NSEvent.removeMonitor(localModifierMonitor)
            self.localModifierMonitor = nil
        }
        if let globalModifierMonitor {
            NSEvent.removeMonitor(globalModifierMonitor)
            self.globalModifierMonitor = nil
        }
        isModifierHotkeyActive = false
    }

    fileprivate func handle(event: EventRef?) -> OSStatus {
        guard let event else { return noErr }
        let kind = GetEventKind(event)
        switch kind {
        case UInt32(kEventHotKeyPressed):
            onEvent?(.pressed)
        case UInt32(kEventHotKeyReleased):
            onEvent?(.released)
        default:
            break
        }
        return noErr
    }

    private func registerModifierOnlyHotkey(_ hotkey: Hotkey) {
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlags(event.modifierFlags, hotkey: hotkey)
            return event
        }

        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlags(event.modifierFlags, hotkey: hotkey)
        }
    }

    private func handleModifierFlags(_ flags: NSEvent.ModifierFlags, hotkey: Hotkey) {
        let isActive = carbonModifiers(from: flags) == hotkey.modifiers
        guard isActive != isModifierHotkeyActive else { return }

        isModifierHotkeyActive = isActive
        onEvent?(isActive ? .pressed : .released)
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
}

private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    return service.handle(event: event)
}

private func FourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
