import AppKit

if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-prefs"),
   CommandLine.arguments.count > flagIndex + 1 {
    _ = NSApplication.shared
    PrefsRenderer.render(toDirectory: CommandLine.arguments[flagIndex + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
