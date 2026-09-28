import AppKit

/// ClipStack is a menu-bar (LSUIElement) app, so its main menu is never shown.
/// AppKit still routes ⌘-key equivalents through `NSApp.mainMenu`, though, and
/// text views only get Cut/Copy/Paste/Select All/Undo from an Edit menu —
/// without one those shortcuts silently do nothing in the app's own windows
/// (snippet editor, preferences, the edit-clip dialog).
enum MainMenu {
    static func install() {
        let mainMenu = NSMenu()

        // AppKit treats the first item as the application menu.
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "ClipStack")
        mainMenu.addItem(appItem)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu, to: mainMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, to: mainMenu)

        NSApp.mainMenu = mainMenu
        syncTextViewsAfterUndo()
    }

    private static func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    /// A TextKit 2 text view (SwiftUI's TextEditor/TextField) sends textDidChange
    /// for Undo/Redo only while it's the first responder. When ⌘Z reaches one
    /// that isn't — e.g. content typing undone from a title field — its binding
    /// keeps the pre-undo text and the snippet editor reports it as saved.
    /// Re-sending it for every text view on that undo manager keeps them in sync.
    private static func syncTextViewsAfterUndo() {
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                guard let undoManager = notification.object as? UndoManager,
                      let window = NSApp.keyWindow else { return }
                for textView in textViews(in: window) where textView.isEditable && textView.undoManager === undoManager {
                    textView.didChangeText()
                }
            }
        }
    }

    /// The window's text views, including an active field editor.
    private static func textViews(in window: NSWindow) -> [NSTextView] {
        var found: [NSTextView] = []
        func collect(_ view: NSView) {
            if let textView = view as? NSTextView { found.append(textView) }
            view.subviews.forEach(collect)
        }
        if let contentView = window.contentView { collect(contentView) }
        if let fieldEditor = window.firstResponder as? NSTextView,
           !found.contains(where: { $0 === fieldEditor }) {
            found.append(fieldEditor)
        }
        return found
    }
}
