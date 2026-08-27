import AppKit
import Carbon.HIToolbox

/// A recordable global keyboard shortcut (key code + modifier flags).
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierRawValue) }

    /// Sentinel for "no shortcut assigned".
    static let none = KeyCombo(keyCode: UInt16.max, modifierRawValue: 0)
    var isNone: Bool { keyCode == UInt16.max }

    static let defaultHistory = KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let defaultSnippets = KeyCombo(keyCode: UInt16(kVK_ANSI_B), modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let defaultEncode = KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let defaultDecode = KeyCombo(keyCode: UInt16(kVK_ANSI_D), modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)

    /// Lowercase character for NSMenuItem.keyEquivalent, when representable.
    var menuKeyEquivalent: String? {
        guard !isNone else { return nil }
        let name = KeyCombo.keyName(for: keyCode)
        guard name.count == 1 else { return nil }
        return name.lowercased()
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    var displayString: String {
        if isNone { return "None" }
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        return parts + KeyCombo.keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(keyCode)] { return name }

        // Translate the key code through the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        var deadKeyState: UInt32 = 0
        let status = layoutData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
