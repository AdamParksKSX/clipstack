import SwiftUI
import AppKit

// The Snippet Editor's folder tree and snippet list are AppKit views
// (NSOutlineView / NSTableView): SwiftUI's List drag and drop on macOS
// highlighted the wrong row and stopped starting drags after the first move.
// AppKit's native table dragging is the dependable mechanism.

extension NSPasteboard.PasteboardType {
    static let clipStackFolder = NSPasteboard.PasteboardType("com.adamparks.clipstack.folder")
    static let clipStackSnippet = NSPasteboard.PasteboardType("com.adamparks.clipstack.snippet")
}

/// A folder's full name for "Move to" menus, e.g. "Work › Salesforce".
struct SnippetFolderPath {
    let id: UUID
    let path: String

    static func all(in folders: [SnippetFolder], prefix: String = "") -> [SnippetFolderPath] {
        folders.flatMap { folder -> [SnippetFolderPath] in
            let name = folder.name.isEmpty ? "Untitled" : folder.name
            let path = prefix.isEmpty ? name : "\(prefix) › \(name)"
            return [SnippetFolderPath(id: folder.id, path: path)] + all(in: folder.subfolders, prefix: path)
        }
    }
}

/// Whether moving folder `id` into `parentID` (nil = top level) would do
/// anything and is allowed: never into itself or its own subfolders.
func canMoveSnippetFolder(_ id: UUID, into parentID: UUID?, in folders: [SnippetFolder]) -> Bool {
    guard id != parentID, let folder = folders.folder(withID: id) else { return false }
    guard let parentID else {
        return !folders.contains { $0.id == id }
    }
    guard let parent = folders.folder(withID: parentID),
          [folder].indexPath(ofFolder: parentID) == nil else { return false }
    return !parent.subfolders.contains { $0.id == id }
}

/// A one-column table cell: icon plus an editable name.
private func makeNameCell(identifier: NSUserInterfaceItemIdentifier, delegate: NSTextFieldDelegate) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let image = NSImageView()
    image.translatesAutoresizingMaskIntoConstraints = false
    image.contentTintColor = .secondaryLabelColor
    let field = NSTextField()
    field.translatesAutoresizingMaskIntoConstraints = false
    field.isBordered = false
    field.drawsBackground = false
    field.isEditable = true
    field.lineBreakMode = .byTruncatingTail
    field.cell?.usesSingleLineMode = true
    field.delegate = delegate
    cell.addSubview(image)
    cell.addSubview(field)
    cell.imageView = image
    cell.textField = field
    NSLayoutConstraint.activate([
        image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
        image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        image.widthAnchor.constraint(equalToConstant: 16),
        image.heightAnchor.constraint(equalToConstant: 16),
        field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
        field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
}

private func makeScrollingTable(_ table: NSTableView) -> NSScrollView {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.style = .inset
    table.rowHeight = 24
    table.allowsMultipleSelection = false
    table.allowsEmptySelection = true
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.setDraggingSourceOperationMask(.move, forLocal: true)
    table.setDraggingSourceOperationMask([], forLocal: false)
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    return scroll
}

// MARK: - Folder tree

/// Folder outline: select, rename (double-click or right-click → Rename),
/// drag folders onto folders (or between top-level rows for the top level),
/// and accept snippets dragged from the snippet list.
struct SnippetFolderTree: NSViewRepresentable {
    let folders: [SnippetFolder]
    @Binding var selection: UUID?
    /// Set to a folder ID to start renaming it (cleared once started).
    @Binding var renameRequest: UUID?
    let onRename: (UUID, String) -> Void
    let onMoveFolder: (UUID, UUID?) -> Void
    let onMoveSnippet: (UUID, UUID) -> Void
    let onNewSubfolder: (UUID) -> Void
    let onDelete: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let scroll = makeScrollingTable(outline)
        outline.outlineTableColumn = outline.tableColumns.first
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.registerForDraggedTypes([.clipStackFolder, .clipStackSnippet])
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu
        context.coordinator.outline = outline
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let outline = coordinator.outline else { return }
        if coordinator.folders != folders {
            coordinator.folders = folders
            outline.reloadData()
            if !coordinator.didExpandInitially {
                outline.expandItem(nil, expandChildren: true)
                coordinator.didExpandInitially = true
            }
        }
        if let id = coordinator.pendingReveal {
            // Show what was just moved into this folder.
            coordinator.pendingReveal = nil
            outline.expandItem(coordinator.node(id))
        }
        coordinator.syncSelection()
        if let id = renameRequest {
            coordinator.beginRenaming(id)
            DispatchQueue.main.async { renameRequest = nil }
        }
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate,
                             NSTextFieldDelegate, NSMenuDelegate {
        var parent: SnippetFolderTree
        var folders: [SnippetFolder] = []
        var didExpandInitially = false
        /// A folder to expand once the outline has reloaded after a move into it.
        var pendingReveal: UUID?
        weak var outline: NSOutlineView?
        private var isSyncingSelection = false
        /// Stable item objects, so the outline keeps expansion across reloads.
        private var nodes: [UUID: Node] = [:]
        private let cellID = NSUserInterfaceItemIdentifier("folderCell")

        final class Node: NSObject {
            let id: UUID
            init(_ id: UUID) { self.id = id }
            override func isEqual(_ object: Any?) -> Bool { (object as? Node)?.id == id }
            override var hash: Int { id.hashValue }
        }

        init(_ parent: SnippetFolderTree) { self.parent = parent }

        func node(_ id: UUID) -> Node {
            if let node = nodes[id] { return node }
            let node = Node(id)
            nodes[id] = node
            return node
        }

        private func children(of item: Any?) -> [SnippetFolder] {
            guard let node = item as? Node else { return folders }
            return folders.folder(withID: node.id)?.subfolders ?? []
        }

        /// Selects `parent.selection` in the outline, expanding its ancestors.
        func syncSelection() {
            guard let outline else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            guard let id = parent.selection, let path = folders.indexPath(ofFolder: id) else {
                if outline.selectedRow >= 0 { outline.deselectAll(nil) }
                return
            }
            for depth in 1..<max(path.count, 1) {
                outline.expandItem(node(folders[path: Array(path.prefix(depth))].id))
            }
            let row = outline.row(forItem: node(id))
            if row >= 0, outline.selectedRow != row {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }

        func beginRenaming(_ id: UUID) {
            guard let outline else { return }
            syncSelection()
            let row = outline.row(forItem: node(id))
            guard row >= 0 else { return }
            outline.editColumn(0, row: row, with: nil, select: true)
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            node(children(of: item)[index].id)
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            !children(of: item).isEmpty
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node, let folder = folders.folder(withID: node.id) else { return nil }
            let cell = (outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView)
                ?? makeNameCell(identifier: cellID, delegate: self)
            cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            cell.textField?.stringValue = folder.name
            cell.textField?.placeholderString = "Folder name"
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let outline else { return }
            let row = outline.selectedRow
            let id = row >= 0 ? (outline.item(atRow: row) as? Node)?.id : nil
            if parent.selection != id { parent.selection = id }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let outline else { return }
            let row = outline.row(for: field)
            guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
            parent.onRename(node.id, field.stringValue)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let outline, outline.clickedRow >= 0 else { return }
            outline.editColumn(0, row: outline.clickedRow, with: nil, select: true)
        }

        // MARK: Dragging

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? Node else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(node.id.uuidString, forType: .clipStackFolder)
            return pasteboardItem
        }

        private enum Dragged {
            case folder(UUID)
            case snippet(UUID)
        }

        private func dragged(_ info: NSDraggingInfo) -> Dragged? {
            let pasteboard = info.draggingPasteboard
            if let string = pasteboard.string(forType: .clipStackFolder), let id = UUID(uuidString: string) {
                return .folder(id)
            }
            if let string = pasteboard.string(forType: .clipStackSnippet), let id = UUID(uuidString: string) {
                return .snippet(id)
            }
            return nil
        }

        /// Drops land *on* a folder. A drop between rows counts as a drop on
        /// that gap's parent folder (the top level, for folders only).
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let dragged = dragged(info) else { return [] }
            let target = (item as? Node)?.id
            if index != NSOutlineViewDropOnItemIndex {
                outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            }
            switch dragged {
            case .folder(let id):
                return canMoveSnippetFolder(id, into: target, in: folders) ? .move : []
            case .snippet(let id):
                guard let target, folders.folderID(containingSnippet: id) != target else { return [] }
                return .move
            }
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let dragged = dragged(info) else { return false }
            let target = (item as? Node)?.id
            switch dragged {
            case .folder(let id):
                guard canMoveSnippetFolder(id, into: target, in: folders) else { return false }
                // Applied after AppKit finishes the drop, not in the middle of it.
                DispatchQueue.main.async { self.moveFolder(id, into: target) }
            case .snippet(let id):
                guard let target else { return false }
                DispatchQueue.main.async { self.parent.onMoveSnippet(id, target) }
            }
            return true
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, outline.clickedRow >= 0,
                  let node = outline.item(atRow: outline.clickedRow) as? Node,
                  let folder = folders.folder(withID: node.id) else { return }
            menu.addItem(item("Rename", #selector(renameClicked(_:)), node.id))
            menu.addItem(item("New Subfolder", #selector(newSubfolderClicked(_:)), node.id))

            let moveMenu = NSMenu()
            let topLevel = item("Top Level", #selector(moveClicked(_:)), [node.id, nil] as [UUID?])
            topLevel.isEnabled = canMoveSnippetFolder(node.id, into: nil, in: folders)
            moveMenu.addItem(topLevel)
            moveMenu.addItem(.separator())
            let ownTree = Set([folder].flattened().map { $0.folder.id })
            for target in SnippetFolderPath.all(in: folders) where !ownTree.contains(target.id) {
                let entry = item(target.path, #selector(moveClicked(_:)), [node.id, target.id] as [UUID?])
                entry.isEnabled = canMoveSnippetFolder(node.id, into: target.id, in: folders)
                moveMenu.addItem(entry)
            }
            let move = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            move.submenu = moveMenu
            menu.addItem(move)

            menu.addItem(.separator())
            menu.addItem(item("Delete Folder…", #selector(deleteClicked(_:)), node.id))
        }

        private func item(_ title: String, _ action: Selector, _ object: Any) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
            return item
        }

        @objc private func renameClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            beginRenaming(id)
        }

        @objc private func newSubfolderClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.onNewSubfolder(id)
        }

        @objc private func moveClicked(_ sender: NSMenuItem) {
            guard let pair = sender.representedObject as? [UUID?], pair.count == 2, let id = pair[0] else { return }
            moveFolder(id, into: pair[1])
        }

        private func moveFolder(_ id: UUID, into target: UUID?) {
            pendingReveal = target
            parent.onMoveFolder(id, target)
        }

        @objc private func deleteClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.onDelete(id)
        }
    }
}

// MARK: - Snippet list

/// The selected folder's snippets: select, rename, drag onto a folder in the
/// tree, or right-click → Move to / Rename / Delete.
struct SnippetList: NSViewRepresentable {
    let snippets: [Snippet]
    let folderID: UUID
    let folders: [SnippetFolder]
    @Binding var selection: UUID?
    @Binding var renameRequest: UUID?
    let onRename: (UUID, String) -> Void
    let onMoveSnippet: (UUID, UUID) -> Void
    let onDelete: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let scroll = makeScrollingTable(table)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        if coordinator.snippets != snippets {
            coordinator.snippets = snippets
            table.reloadData()
        }
        coordinator.syncSelection()
        if let id = renameRequest, snippets.contains(where: { $0.id == id }) {
            coordinator.beginRenaming(id)
            DispatchQueue.main.async { renameRequest = nil }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                             NSTextFieldDelegate, NSMenuDelegate {
        var parent: SnippetList
        var snippets: [Snippet] = []
        weak var table: NSTableView?
        private var isSyncingSelection = false
        private let cellID = NSUserInterfaceItemIdentifier("snippetCell")

        init(_ parent: SnippetList) { self.parent = parent }

        func syncSelection() {
            guard let table else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if let id = parent.selection, let row = snippets.firstIndex(where: { $0.id == id }) {
                if table.selectedRow != row {
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    table.scrollRowToVisible(row)
                }
            } else if table.selectedRow >= 0 {
                table.deselectAll(nil)
            }
        }

        func beginRenaming(_ id: UUID) {
            guard let table, let row = snippets.firstIndex(where: { $0.id == id }) else { return }
            syncSelection()
            table.editColumn(0, row: row, with: nil, select: true)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { snippets.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView)
                ?? makeNameCell(identifier: cellID, delegate: self)
            cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            cell.textField?.stringValue = snippets[row].title
            cell.textField?.placeholderString = "Title"
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table else { return }
            let row = table.selectedRow
            let id = row >= 0 && row < snippets.count ? snippets[row].id : nil
            if parent.selection != id { parent.selection = id }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let table else { return }
            let row = table.row(for: field)
            guard row >= 0, row < snippets.count else { return }
            parent.onRename(snippets[row].id, field.stringValue)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table, table.clickedRow >= 0 else { return }
            table.editColumn(0, row: table.clickedRow, with: nil, select: true)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < snippets.count else { return nil }
            let item = NSPasteboardItem()
            item.setString(snippets[row].id.uuidString, forType: .clipStackSnippet)
            return item
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, table.clickedRow >= 0, table.clickedRow < snippets.count else { return }
            let id = snippets[table.clickedRow].id
            menu.addItem(item("Rename", #selector(renameClicked(_:)), id))
            let moveMenu = NSMenu()
            for target in SnippetFolderPath.all(in: parent.folders) {
                let entry = item(target.path, #selector(moveClicked(_:)), [id, target.id])
                entry.isEnabled = target.id != parent.folderID
                moveMenu.addItem(entry)
            }
            let move = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            move.submenu = moveMenu
            menu.addItem(move)
            menu.addItem(.separator())
            menu.addItem(item("Delete Snippet", #selector(deleteClicked(_:)), id))
        }

        private func item(_ title: String, _ action: Selector, _ object: Any) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
            return item
        }

        @objc private func renameClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            beginRenaming(id)
        }

        @objc private func moveClicked(_ sender: NSMenuItem) {
            guard let pair = sender.representedObject as? [UUID], pair.count == 2 else { return }
            parent.onMoveSnippet(pair[0], pair[1])
        }

        @objc private func deleteClicked(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.onDelete(id)
        }
    }
}
