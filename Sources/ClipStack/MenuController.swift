import AppKit

/// Owns the status item and builds the clip menu: inline history items,
/// numbered folder submenus, snippet folders, actions, and app commands.
final class MenuController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let history: HistoryStore
    private let snippets: SnippetStore
    private let monitor: PasteboardMonitor

    private var statusItem: NSStatusItem?

    var onShowPreferences: (() -> Void)?
    var onShowSnippetEditor: (() -> Void)?

    init(settings: Settings, history: HistoryStore, snippets: SnippetStore, monitor: PasteboardMonitor) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.monitor = monitor
        super.init()
    }

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = StatusIcon.make()
            icon.accessibilityDescription = "ClipStack"
            button.image = icon
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu, includeAppCommands: true, historyOnly: false)
    }

    // MARK: Hotkey popups

    /// Pops the full menu up at the mouse cursor (history hotkey).
    func popUpHistoryMenu() {
        let menu = NSMenu()
        rebuild(menu, includeAppCommands: true, historyOnly: false)
        menu.popUp(positioning: menu.items.first, at: NSEvent.mouseLocation, in: nil)
    }

    /// Pops a snippets-only menu up at the mouse cursor (snippets hotkey).
    func popUpSnippetsMenu() {
        let menu = NSMenu()
        addSnippetItems(to: menu, inline: true)
        if menu.items.isEmpty {
            menu.addItem(disabledItem("No Snippets"))
        }
        menu.addItem(.separator())
        menu.addItem(makeItem("Edit Snippets…", action: #selector(editSnippets)))
        menu.popUp(positioning: menu.items.first, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Building

    private func rebuild(_ menu: NSMenu, includeAppCommands: Bool, historyOnly: Bool) {
        menu.removeAllItems()

        addHistoryItems(to: menu)

        if !historyOnly {
            let snippetSection = NSMenu()
            addSnippetItems(to: snippetSection, inline: false)
            if !snippetSection.items.isEmpty {
                menu.addItem(.separator())
                for item in snippetSection.items {
                    snippetSection.removeItem(item)
                    menu.addItem(item)
                }
            }

            menu.addItem(.separator())
            menu.addItem(makeSubmenuItem(title: "Actions", symbol: "wand.and.stars", submenu: buildActionsMenu()))
        }

        if includeAppCommands {
            menu.addItem(.separator())
            menu.addItem(makeItem("Clear History", action: #selector(clearHistory)))
            menu.addItem(makeItem("Edit Snippets…", action: #selector(editSnippets)))
            menu.addItem(makeItem("Import Snippets…", action: #selector(importSnippets)))
            menu.addItem(makeItem("Preferences…", action: #selector(showPreferences), key: ","))
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit ClipStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
        }
    }

    private func addHistoryItems(to menu: NSMenu) {
        let clips = history.clips
        guard !clips.isEmpty else {
            menu.addItem(disabledItem("No History"))
            return
        }

        let inlineCount = min(settings.inlineItemCount, clips.count)
        for index in 0..<inlineCount {
            menu.addItem(clipMenuItem(for: clips[index], numberInMenu: index, displayNumber: index + 1))
        }

        // Remaining items go in "n - m" folder submenus, like the original.
        var start = inlineCount
        let perFolder = max(1, settings.itemsPerFolder)
        while start < clips.count {
            let end = min(start + perFolder, clips.count)
            let folderItem = NSMenuItem(title: "\(start + 1) - \(end)", action: nil, keyEquivalent: "")
            folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let submenu = NSMenu(title: folderItem.title)
            for (offset, index) in (start..<end).enumerated() {
                // Titles show the absolute position (matching the "11 - 20"
                // folder label); shortcut keys stay positional within the menu.
                submenu.addItem(clipMenuItem(for: clips[index], numberInMenu: offset, displayNumber: index + 1))
            }
            folderItem.submenu = submenu
            menu.addItem(folderItem)
            start = end
        }
    }

    private func clipMenuItem(for clip: ClipItem, numberInMenu: Int, displayNumber: Int) -> NSMenuItem {
        var title = clip.menuTitle(maxLength: settings.maxTitleLength)
        if settings.showItemNumbers {
            title = "\(displayNumber). \(title)"
        }
        let item = NSMenuItem(title: title,
                              action: #selector(selectClip(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = clip.id

        // Numbered titles make the badge column redundant (type-select on the
        // "n. " prefix covers keyboard access), so badges only appear without it.
        if settings.numericKeyEquivalents && !settings.showItemNumbers && numberInMenu < 10 {
            item.keyEquivalent = String((numberInMenu + 1) % 10)
            item.keyEquivalentModifierMask = []
        }
        if settings.showToolTips {
            item.toolTip = clip.toolTip
        }
        if clip.kind == .image, settings.showImageThumbnails {
            item.image = clip.thumbnail(height: 36)
        } else if clip.kind == .files {
            item.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        }
        return item
    }

    private func addSnippetItems(to menu: NSMenu, inline: Bool) {
        for folder in snippets.folders where !folder.snippets.isEmpty {
            if inline && snippets.folders.count == 1 {
                // A single folder popped up via hotkey shows its snippets directly.
                for (index, snippet) in folder.snippets.enumerated() {
                    menu.addItem(snippetMenuItem(for: snippet, numberInMenu: index))
                }
            } else {
                let folderItem = NSMenuItem(title: folder.name, action: nil, keyEquivalent: "")
                folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                let submenu = NSMenu(title: folder.name)
                for (index, snippet) in folder.snippets.enumerated() {
                    submenu.addItem(snippetMenuItem(for: snippet, numberInMenu: index))
                }
                folderItem.submenu = submenu
                menu.addItem(folderItem)
            }
        }
    }

    private func snippetMenuItem(for snippet: Snippet, numberInMenu: Int) -> NSMenuItem {
        var title = String((snippet.title.isEmpty ? snippet.content : snippet.title)
            .prefix(settings.maxTitleLength))
        if settings.showItemNumbers {
            title = "\(numberInMenu + 1). \(title)"
        }
        let item = NSMenuItem(title: title,
                              action: #selector(selectSnippet(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = snippet.content
        if settings.numericKeyEquivalents && !settings.showItemNumbers && numberInMenu < 10 {
            item.keyEquivalent = String((numberInMenu + 1) % 10)
            item.keyEquivalentModifierMask = []
        }
        if settings.showToolTips {
            item.toolTip = snippet.content
        }
        return item
    }

    private func buildActionsMenu() -> NSMenu {
        actionRegistry.removeAll()
        nextActionTag = 1
        let menu = NSMenu(title: "Actions")
        var groups: [String?: [ClipAction]] = [:]
        var groupOrder: [String?] = []
        for action in ActionEngine.builtIns + ActionEngine.userActions() {
            if groups[action.group] == nil { groupOrder.append(action.group) }
            groups[action.group, default: []].append(action)
        }
        // Ungrouped actions first, then groups as submenus.
        for action in groups[nil] ?? [] {
            menu.addItem(actionMenuItem(for: action))
        }
        for group in groupOrder.compactMap({ $0 }) {
            let groupItem = NSMenuItem(title: group, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: group)
            for action in groups[group] ?? [] {
                submenu.addItem(actionMenuItem(for: action))
            }
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }
        return menu
    }

    private var actionRegistry: [Int: ClipAction] = [:]
    private var nextActionTag = 1

    private func actionMenuItem(for action: ClipAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.name, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        // Show the global hotkey next to the action, when one is set.
        if let combo = hotKeyCombo(forActionNamed: action.name), let key = combo.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.modifiers
        }
        actionRegistry[nextActionTag] = action
        item.tag = nextActionTag
        nextActionTag += 1
        return item
    }

    private func hotKeyCombo(forActionNamed name: String) -> KeyCombo? {
        switch name {
        case "Encode to Base64": return settings.encodeHotKey
        case "Decode from Base64": return settings.decodeHotKey
        default: return nil
        }
    }

    /// Runs a built-in or user action by name — used by the global hotkeys.
    func performAction(named name: String) {
        guard let action = (ActionEngine.builtIns + ActionEngine.userActions())
            .first(where: { $0.name == name }) else { return }
        execute(action)
    }

    // MARK: Item helpers

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeSubmenuItem(title: String, symbol: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Menu actions

    @objc private func selectClip(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = history.clips.first(where: { $0.id == id }) else { return }
        monitor.suppressNextChange = true
        clip.write(to: NSPasteboard.general)
        // Selecting an item promotes it to the top of the history.
        history.add(clip)
        if settings.pasteAutomatically {
            Paster.pasteToFrontmostApp()
        }
    }

    @objc private func selectSnippet(_ sender: NSMenuItem) {
        guard let content = sender.representedObject as? String else { return }
        monitor.suppressNextChange = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        if settings.pasteSnippetsAutomatically || settings.pasteAutomatically {
            if Paster.isTrusted {
                Paster.pasteToFrontmostApp()
            } else {
                // First use: surface the system Accessibility prompt so the
                // user can grant the permission auto-paste needs.
                Paster.requestPermission()
            }
        }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = actionRegistry[sender.tag] else { return }
        execute(action)
    }

    private func execute(_ action: ClipAction) {
        guard let input = clipboardText() else {
            actionFailed("There is no text on the clipboard to transform.")
            return
        }
        guard let output = action.transform(input) else {
            actionFailed("\"\(action.name)\" could not transform the clipboard text (for Base64 decoding, the text must be valid Base64).")
            return
        }
        // Write the result and record it in the history immediately, so it
        // shows as the newest item without waiting for the pasteboard poll.
        monitor.suppressNextChange = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        history.add(ClipItem(kind: .text, text: output))
    }

    /// Plain text from the clipboard, falling back to rich-text-only content
    /// (e.g. RTF or HTML flavors with no plain-string representation).
    private func clipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) { return text }
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            return attributed.string
        }
        if let htmlData = pasteboard.data(forType: .html),
           let attributed = NSAttributedString(html: htmlData, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }

    private func actionFailed(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Action failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This removes all \(history.clips.count) recorded items. This cannot be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            history.clear()
        }
    }

    @objc private func importSnippets() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml, .json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a snippet file to import (classic ClipMenu XML, ClipStack JSON, or Text Blaze JSON)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        do {
            let imported = try SnippetImporter.importFolders(from: url)
            snippets.folders.append(contentsOf: imported)
            let count = imported.reduce(0) { $0 + $1.snippets.count }
            alert.messageText = "Snippets imported"
            alert.informativeText = "Added \(imported.count) folder\(imported.count == 1 ? "" : "s") with \(count) snippet\(count == 1 ? "" : "s")."
        } catch {
            alert.messageText = "Import failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    @objc private func editSnippets() {
        onShowSnippetEditor?()
    }

    @objc private func showPreferences() {
        onShowPreferences?()
    }

}
