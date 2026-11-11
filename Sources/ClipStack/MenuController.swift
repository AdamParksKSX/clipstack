import AppKit

/// Owns the status item and builds the clip menu: inline history items,
/// numbered folder submenus, snippet folders, actions, and app commands.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let history: HistoryStore
    private let snippets: SnippetStore
    private let monitor: PasteboardMonitor

    private var statusItem: NSStatusItem?

    /// The hotkey history popup while it's shown. Folder submenus share this
    /// delegate, so root-menu callbacks are told apart from theirs by identity.
    private weak var historyPopupMenu: NSMenu?

    private let previewPanel = ClipPreviewPanel()
    /// Source-app badges by bundle ID (nil = app not found), per menu build.
    private var appIconCache: [String: NSImage?] = [:]

    var onShowPreferences: (() -> Void)?
    var onShowSnippetEditor: (() -> Void)?

    init(settings: Settings, history: HistoryStore, snippets: SnippetStore, monitor: PasteboardMonitor) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.monitor = monitor
        super.init()
        ClipRowView.activeRowDidChange = { [weak self] row in
            self?.highlightedRowChanged(row)
        }
    }

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A stable autosave name plus forced visibility clears any persisted
        // "hidden" state macOS may have saved for this item in a past run.
        item.autosaveName = "ClipStackStatusItem"
        item.behavior = []
        item.isVisible = true
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
        // Folder submenus and popup menus share this delegate for highlight
        // tracking; only the status-item menu rebuilds here.
        guard menu === statusItem?.menu else { return }
        rebuild(menu, includeAppCommands: true, historyOnly: false)
    }

    /// Mirrors menu highlight state to custom-view rows (for keyboard navigation
    /// or when hovering over a standard non-custom item).
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        ClipRowView.setActive(item?.view as? ClipRowView)
    }

    func menuDidClose(_ menu: NSMenu) {
        ClipRowView.setActive(nil)
        // Only the whole menu closing ends the preview, not a folder submenu.
        guard menu === statusItem?.menu || menu === historyPopupMenu else { return }
        previewPanel.dismiss()
    }

    // MARK: Hotkey popups

    /// Pops a history-only menu up at the mouse cursor (history hotkey):
    /// every clip inline, without folder submenus, snippets, actions, or app
    /// commands. The full menu stays on the status item.
    func popUpHistoryMenu() {
        let menu = NSMenu()
        menu.delegate = self
        historyPopupMenu = menu
        rebuild(menu, includeAppCommands: false, historyOnly: true, inlineAllHistory: true)
        popUpAtCursor(menu)
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
        popUpAtCursor(menu)
    }

    /// Shows the menu at the cursor, shifting the anchor so the whole menu
    /// fits on screen (a menu opened near the bottom edge would otherwise be
    /// compressed into a scrolling list).
    private func popUpAtCursor(_ menu: NSMenu) {
        var point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = menu.size
            // The menu opens downward and rightward from the anchor point.
            point.x = min(max(point.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            point.y = min(max(point.y, visible.minY + size.height), visible.maxY)
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    // MARK: Building

    private func rebuild(_ menu: NSMenu, includeAppCommands: Bool, historyOnly: Bool,
                         inlineAllHistory: Bool = false) {
        menu.removeAllItems()
        appIconCache.removeAll()

        makeHistoryItems(inlineAll: inlineAllHistory).forEach(menu.addItem)

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

    /// The history section: favourites, inline clips, and folder submenus.
    private func makeHistoryItems(inlineAll: Bool) -> [NSMenuItem] {
        guard !history.clips.isEmpty else {
            return [disabledItem("No History")]
        }

        var items: [NSMenuItem] = []
        // Favourites stay pinned at the top, outside the numbered history.
        let favorites = history.favorites
        let clips = history.clips.filter { !$0.isFavorite }
        for clip in favorites {
            items.append(clipMenuItem(for: clip, numberInMenu: -1, displayNumber: nil))
        }
        if !favorites.isEmpty && !clips.isEmpty {
            items.append(.separator())
        }

        let inlineCount = inlineAll ? clips.count : min(settings.inlineItemCount, clips.count)
        for index in 0..<inlineCount {
            items.append(clipMenuItem(for: clips[index], numberInMenu: index, displayNumber: index + 1))
        }

        // Remaining items go in "n - m" folder submenus, like the original.
        var start = inlineCount
        let perFolder = max(1, settings.itemsPerFolder)
        while start < clips.count {
            let end = min(start + perFolder, clips.count)
            let folderItem = NSMenuItem(title: "\(start + 1) - \(end)", action: nil, keyEquivalent: "")
            folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let submenu = NSMenu(title: folderItem.title)
            submenu.delegate = self
            for (offset, index) in (start..<end).enumerated() {
                // Titles show the absolute position (matching the "11 - 20"
                // folder label); shortcut keys stay positional within the menu.
                submenu.addItem(clipMenuItem(for: clips[index], numberInMenu: offset, displayNumber: index + 1))
            }
            unifyClipRowWidths(submenu.items)
            folderItem.submenu = submenu
            items.append(folderItem)
            start = end
        }
        unifyClipRowWidths(items)
        return items
    }

    /// Custom-view rows size themselves; giving every row in a menu the width
    /// of the widest keeps the buttons in one column.
    private func unifyClipRowWidths(_ items: [NSMenuItem]) {
        let rows = items.compactMap { $0.view as? ClipRowView }
        guard !rows.isEmpty else { return }
        let sizes = rows.map(\.fittingSize)
        let width = min(max(300, sizes.map(\.width).max() ?? 0), 560)
        for (row, size) in zip(rows, sizes) {
            row.frame = NSRect(x: 0, y: 0, width: width, height: max(size.height, 22))
            row.autoresizingMask = [.width]
        }
    }

    private func clipMenuItem(for clip: ClipItem, numberInMenu: Int, displayNumber: Int?) -> NSMenuItem {
        var title = clip.menuTitle(maxLength: settings.maxTitleLength)
        if settings.showItemNumbers, let displayNumber {
            title = "\(displayNumber). \(title)"
        }
        // The action/keyEquivalent still drive keyboard selection (number keys,
        // Return); mouse handling is done by the row view.
        let item = NSMenuItem(title: title,
                              action: #selector(selectClip(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = clip.id
        if settings.numericKeyEquivalents && !settings.showItemNumbers && (0..<10).contains(numberInMenu) {
            item.keyEquivalent = String((numberInMenu + 1) % 10)
            item.keyEquivalentModifierMask = []
        }

        var icon: NSImage?
        if clip.kind == .image, settings.showImageThumbnails {
            icon = clip.thumbnail(height: 36)
        } else if clip.kind == .files {
            icon = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        }

        let row = ClipRowView(title: title, icon: icon,
                              sourceIcon: sourceAppIcon(bundleID: clip.sourceBundleID),
                              sourceName: clip.sourceAppName,
                              isFavorite: clip.isFavorite,
                              canEdit: clip.kind == .text,
                              toolTip: settings.showToolTips ? clip.toolTip : nil)
        row.clipID = clip.id
        let id = clip.id
        row.onSelect = { [weak self] in self?.pasteClip(id: id) }
        row.onToggleFavorite = { [weak self] in self?.history.toggleFavorite(id: id) }
        row.onEdit = { [weak self] in self?.presentEditDialog(id: id) }
        row.onPreview = { [weak self, weak row] in
            if let row { self?.togglePreview(for: row) }
        }
        row.onDelete = { [weak self, weak item] in
            self?.history.remove(id: id)
            if self?.previewPanel.clipID == id {
                self?.previewPanel.dismiss()
            }
            if let item, let menu = item.menu {
                menu.removeItem(item)
            }
        }
        item.view = row
        return item
    }

    /// 16 × 16 icon of the app with `bundleID`, or nil if it isn't installed.
    private func sourceAppIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIconCache[bundleID] {
            return cached
        }
        var icon: NSImage?
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let image = NSWorkspace.shared.icon(forFile: appURL.path)
            image.size = NSSize(width: 16, height: 16)
            icon = image
        }
        appIconCache[bundleID] = icon
        return icon
    }

    /// Snippet folders as submenus (nested for subfolders). Folders with no
    /// snippets anywhere inside them are left out.
    private func addSnippetItems(to menu: NSMenu, inline: Bool) {
        let folders = snippets.folders.filter(\.containsSnippets)
        if inline && folders.count == 1 {
            // A single folder popped up via hotkey shows its contents directly.
            addContents(of: folders[0], to: menu)
            return
        }
        for folder in folders {
            menu.addItem(snippetFolderItem(for: folder))
        }
    }

    private func snippetFolderItem(for folder: SnippetFolder) -> NSMenuItem {
        let folderItem = NSMenuItem(title: folder.name, action: nil, keyEquivalent: "")
        folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let submenu = NSMenu(title: folder.name)
        addContents(of: folder, to: submenu)
        folderItem.submenu = submenu
        return folderItem
    }

    /// A folder's subfolders first, then its own snippets (numbered from 1
    /// within this menu), like files in Finder.
    private func addContents(of folder: SnippetFolder, to menu: NSMenu) {
        let subfolders = folder.subfolders.filter(\.containsSnippets)
        for subfolder in subfolders {
            menu.addItem(snippetFolderItem(for: subfolder))
        }
        if !subfolders.isEmpty && !folder.snippets.isEmpty {
            menu.addItem(.separator())
        }
        for (index, snippet) in folder.snippets.enumerated() {
            menu.addItem(snippetMenuItem(for: snippet, numberInMenu: index))
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
        guard let id = sender.representedObject as? UUID else { return }
        pasteClip(id: id)
    }

    private func pasteClip(id: UUID) {
        guard let clip = history.clips.first(where: { $0.id == id }) else { return }
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

    private func presentEditDialog(id: UUID) {
        guard let clip = history.clips.first(where: { $0.id == id }),
              clip.kind == .text else { return }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Edit Clip"
        alert.informativeText = "Changes replace the clip's text. Rich-text formatting is removed."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = clip.text ?? ""
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView

        if alert.runModal() == .alertFirstButtonReturn {
            history.updateText(id: id, text: textView.string)
        }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = actionRegistry[sender.tag] else { return }
        execute(action)
    }

    /// The last action run and its result, so re-running the same action
    /// while the clipboard still holds that result keeps it stable instead
    /// of nesting another transform (e.g. base64-encoding an encode's own
    /// output). Copying anything else resets the behavior.
    private var lastActionName: String?
    private var lastActionOutput: String?

    private func execute(_ action: ClipAction) {
        guard let input = clipboardText() else {
            actionFailed("There is no text on the clipboard to transform.")
            return
        }
        if action.name == lastActionName, input == lastActionOutput {
            flashStatusIcon()
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
        lastActionName = action.name
        lastActionOutput = output
        flashStatusIcon()
    }

    /// Actions run silently from a global hotkey, so give a visible cue that
    /// the transform succeeded: swap the status icon for a checkmark briefly.
    private var flashGeneration = 0
    private func flashStatusIcon() {
        guard let button = statusItem?.button else { return }
        flashGeneration += 1
        let generation = flashGeneration
        let checkmark = NSImage(systemSymbolName: "checkmark.circle.fill",
                                accessibilityDescription: "Action completed")
        button.image = checkmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.flashGeneration == generation,
                  let button = self.statusItem?.button else { return }
            let icon = StatusIcon.make()
            icon.accessibilityDescription = "ClipStack"
            button.image = icon
        }
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
        let favoriteCount = history.favorites.count
        let removableCount = history.clips.count - favoriteCount
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        var message = "This removes all \(removableCount) recorded item\(removableCount == 1 ? "" : "s")."
        if favoriteCount > 0 {
            message += " Your \(favoriteCount) favourite\(favoriteCount == 1 ? "" : "s") will be kept."
        }
        alert.informativeText = message + " This cannot be undone."
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
        panel.message = "Choose a snippet file to import (classic ClipMenu XML, ClipStack JSON, Text Blaze JSON, or Realfire saved scripts JSON)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        do {
            let imported = try SnippetImporter.importFolders(from: url)
            snippets.folders.append(contentsOf: imported)
            let count = imported.reduce(0) { $0 + $1.totalSnippetCount }
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

    // MARK: Preview

    private func togglePreview(for row: ClipRowView) {
        if previewPanel.isVisible, previewPanel.clipID == row.clipID {
            previewPanel.dismiss()
        } else if let clip = history.clips.first(where: { $0.id == row.clipID }) {
            previewPanel.show(clip, beside: row)
        }
    }

    /// While the preview is open it follows the highlight, like Quick Look.
    private func highlightedRowChanged(_ row: ClipRowView?) {
        guard let row else { return }
        if previewPanel.isVisible, previewPanel.clipID != row.clipID,
           let clip = history.clips.first(where: { $0.id == row.clipID }) {
            previewPanel.show(clip, beside: row)
        }
    }
}
