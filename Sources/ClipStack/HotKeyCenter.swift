import AppKit
import Carbon.HIToolbox

/// Registers global hotkeys via the Carbon hotkey API (still the supported
/// mechanism for system-wide shortcuts; works fine on Apple Silicon and
/// does not require the Accessibility permission).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    fileprivate var handlers: [UInt32: () -> Void] = [:]
    /// IDs whose key combo is currently held down. Holding a Carbon hotkey
    /// delivers repeated kEventHotKeyPressed events (key auto-repeat); only
    /// the first one per physical press should run the handler.
    fileprivate var pressedIDs: Set<UInt32> = []
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        guard !combo.isNone else { return nil }
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4D32) /* 'CLM2' */, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers,
                                         hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Failed to register hotkey \(combo.displayString) (status \(status))")
            return nil
        }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        handlers.removeAll()
        pressedIDs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                        eventKind: UInt32(kEventHotKeyPressed)),
                          EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                        eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, let event else { return status }
            let center = HotKeyCenter.shared
            switch GetEventKind(event) {
            case UInt32(kEventHotKeyPressed):
                // Auto-repeat arrives as additional pressed events while the
                // combo is held; run the handler only for the initial press.
                guard !center.pressedIDs.contains(hotKeyID.id) else { break }
                center.pressedIDs.insert(hotKeyID.id)
                if let handler = center.handlers[hotKeyID.id] {
                    DispatchQueue.main.async(execute: handler)
                }
            case UInt32(kEventHotKeyReleased):
                center.pressedIDs.remove(hotKeyID.id)
            default:
                break
            }
            return noErr
        }, eventTypes.count, &eventTypes, nil, nil)
        handlerInstalled = true
    }
}
