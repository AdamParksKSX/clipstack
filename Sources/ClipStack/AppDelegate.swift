import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var history: HistoryStore!
    private var snippets: SnippetStore!
    private var monitor: PasteboardMonitor!
    private var menuController: MenuController!

    private var preferencesWindow: NSWindow?
    private var snippetEditorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        history = HistoryStore(settings: settings)
        snippets = SnippetStore()
        monitor = PasteboardMonitor(history: history, settings: settings)
        menuController = MenuController(settings: settings, history: history,
                                        snippets: snippets, monitor: monitor)

        menuController.onShowPreferences = { [weak self] in self?.showPreferences() }
        menuController.onShowSnippetEditor = { [weak self] in self?.showSnippetEditor() }

        menuController.installStatusItem()
        monitor.start()
        registerHotKeys()

        BackupManager.shared.configure(settings: settings, history: history, snippets: snippets)
        BackupManager.shared.start()

        UpdateChecker.shared.configure(settings: settings)
        UpdateChecker.shared.start()

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: Settings.changedNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.saveNow()
        snippets.saveNow()
        HotKeyCenter.shared.unregisterAll()
    }

    @objc private func settingsChanged() {
        history.trim()
        registerHotKeys()
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        if let combo = settings.historyHotKey, !combo.isNone {
            HotKeyCenter.shared.register(combo) { [weak self] in
                self?.menuController.popUpHistoryMenu()
            }
        }
        if let combo = settings.snippetsHotKey, !combo.isNone {
            HotKeyCenter.shared.register(combo) { [weak self] in
                self?.menuController.popUpSnippetsMenu()
            }
        }
        if let combo = settings.encodeHotKey, !combo.isNone {
            HotKeyCenter.shared.register(combo) { [weak self] in
                self?.menuController.performAction(named: "Encode to Base64")
            }
        }
        if let combo = settings.decodeHotKey, !combo.isNone {
            HotKeyCenter.shared.register(combo) { [weak self] in
                self?.menuController.performAction(named: "Decode from Base64")
            }
        }
    }

    // MARK: Windows

    private func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: PreferencesView(settings: settings)))
            window.title = "ClipStack Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSnippetEditor() {
        if snippetEditorWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SnippetEditorView(store: snippets)))
            window.title = "Snippet Editor"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 700, height: 420))
            window.center()
            snippetEditorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        snippetEditorWindow?.makeKeyAndOrderFront(nil)
    }
}
