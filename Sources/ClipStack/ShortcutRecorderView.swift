import SwiftUI
import AppKit

/// A minimal shortcut recorder: click, press a key combo, done.
struct ShortcutRecorderView: View {
    @Binding var combo: KeyCombo?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Press keys…" : (combo?.isNone == false ? combo!.displayString : "Click to record"))
                    .frame(minWidth: 130)
            }
            Button("Clear") {
                stopRecording()
                combo = KeyCombo.none
            }
            .disabled(combo == nil || combo!.isNone)
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 53 && flags.isEmpty { // Escape cancels
                stopRecording()
                return nil
            }
            // Require at least one modifier so plain typing can't become a hotkey.
            guard !flags.isEmpty else {
                NSSound.beep()
                return nil
            }
            combo = KeyCombo(keyCode: event.keyCode, modifierRawValue: flags.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
