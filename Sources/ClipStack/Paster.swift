import AppKit
import Carbon.HIToolbox

/// Sends ⌘V to the frontmost application so a selected clip pastes in place.
/// Requires the Accessibility permission (System Settings → Privacy & Security).
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts the user for the Accessibility permission if not yet granted.
    @discardableResult
    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func pasteToFrontmostApp() {
        guard isTrusted else { return }
        // Small delay lets the menu fully dismiss and focus return to the
        // previous app before the synthetic keystroke arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
