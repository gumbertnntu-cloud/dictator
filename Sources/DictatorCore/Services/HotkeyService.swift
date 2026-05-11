import Carbon
import Foundation

public enum HotkeyPhase {
    case pressed
    case released
}

public final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
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
