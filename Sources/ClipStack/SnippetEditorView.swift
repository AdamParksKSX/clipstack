import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Three-pane snippet editor: a folder tree (folders can hold subfolders),
/// the selected folder's snippets, and the selected snippet's content.
/// Snippets and folders move by dragging them onto a folder in the tree, or
/// with their right-click "Move to" menu.
struct SnippetEditorView: View {
    @ObservedObject var store: SnippetStore
    @Environment(\.undoManager) private var undoManager
    @State private var selectedFolderID: UUID?
    @State private var selectedSnippetID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    /// The folder row a drag is hovering over, highlighted as the drop target.
    @State private var dropTargetFolderID: UUID?
    @State private var folderPendingDeletion: SnippetFolder?
    /// True briefly after an explicit Save, to flash a confirmation.
    @State private var showSavedConfirmation = false
    @State private var savedConfirmationCount = 0
    @State private var showSaveError = false

    /// Shared by all three bottom bars so their dividers line up.
    private let bottomBarHeight: CGFloat = 30

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedFolderID) {
                    Section("Folders") {
                        ForEach(visibleFolderRows) { row in
                            folderRow(row.folder, depth: row.depth)
                                .tag(row.folder.id)
                        }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Button(action: addFolder) { barIcon("plus") }
                        .help("New folder")
                    Button(action: addSubfolder) { barIcon("folder.badge.plus") }
                        .disabled(selectedFolderID == nil)
                        .help("New subfolder inside the selected folder")
                    Button(action: removeSelectedFolder) { barIcon("minus") }
                        .disabled(selectedFolderID == nil)
                        .help("Delete the selected folder")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .frame(height: bottomBarHeight)
            }
            .frame(minWidth: 170, idealWidth: 210)

            VStack(spacing: 0) {
                List(selection: $selectedSnippetID) {
                    if let folderID = selectedFolderID, store.folders.folder(withID: folderID) != nil {
                        Section("Snippets") {
                            ForEach(snippetsBinding(inFolder: folderID)) { $snippet in
                                snippetRow($snippet, inFolder: folderID)
                                    .tag(snippet.id)
                            }
                        }
                    } else {
                        Text("Select a folder").foregroundColor(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Button(action: addSnippet) { barIcon("plus") }
                        .disabled(selectedFolderID == nil)
                    Button(action: removeSnippet) { barIcon("minus") }
                        .disabled(selectedSnippetID == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .frame(height: bottomBarHeight)
            }
            .frame(minWidth: 170, idealWidth: 200)

            VStack(spacing: 0) {
                VStack(alignment: .leading) {
                    if let binding = selectedSnippetContentBinding {
                        Text("Content").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: binding)
                            .font(.body.monospaced())
                            .id(selectedSnippetID)
                    } else {
                        Spacer()
                        Text("Select a snippet to edit its content")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .padding(8)
                Divider()
                saveBar
            }
            .frame(minWidth: 260)
        }
        .frame(minWidth: 660, minHeight: 380)
        // Start with the whole tree open so nested folders are visible.
        .onAppear { expandedFolderIDs = Set(store.folders.flattened().map { $0.folder.id }) }
        .onChange(of: store.saveStatus) { status in
            // A new edit supersedes the confirmation of the last save.
            if status != .saved { showSavedConfirmation = false }
        }
        // Typing-undo steps hold character ranges in the text they were made
        // in; replayed against another snippet they'd corrupt it.
        .onChange(of: selectedFolderID) { _ in undoManager?.removeAllActions() }
        .onChange(of: selectedSnippetID) { _ in undoManager?.removeAllActions() }
        .confirmationDialog(deletionTitle, isPresented: deletionDialogShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let folder = folderPendingDeletion { removeFolder(folder.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
        .alert("Couldn't Save Snippets", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let message) = store.saveStatus {
                Text(message)
            }
        }
    }

    /// Fixed-size label so the borderless +/− buttons have a usable hit area.
    private func barIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
    }

    private var saveBar: some View {
        HStack(spacing: 8) {
            saveStatusLabel
            Spacer()
            Button("Save", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .controlSize(.small)
                .help("Save snippets now (⌘S). Changes are also saved automatically.")
        }
        .padding(.horizontal, 8)
        .frame(height: bottomBarHeight)
    }

    private var saveStatusLabel: some View {
        Group {
            switch store.saveStatus {
            case .failed(let message):
                statusLabel("Couldn't save", systemImage: "exclamationmark.triangle.fill",
                            iconColor: .red, textColor: .primary)
                    .help(message)
            case .pending:
                statusLabel("Saving…", systemImage: "arrow.triangle.2.circlepath",
                            iconColor: .secondary, textColor: .secondary)
            case .saved where showSavedConfirmation:
                statusLabel("Saved", systemImage: "checkmark.circle.fill",
                            iconColor: .green, textColor: .primary)
            case .saved:
                statusLabel("All changes saved", systemImage: "checkmark.circle",
                            iconColor: .secondary, textColor: .secondary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Tints only the icon: small colored text is hard to read on a light background.
    private func statusLabel(_ title: String, systemImage: String,
                             iconColor: Color, textColor: Color) -> some View {
        Label {
            Text(title).foregroundColor(textColor)
        } icon: {
            Image(systemName: systemImage).foregroundColor(iconColor)
        }
    }

    // MARK: Folder tree

    private struct FolderRow: Identifiable {
        let folder: SnippetFolder
        let depth: Int
        var id: UUID { folder.id }
    }

    /// A folder's full name for "Move to" menus, e.g. "Work › Salesforce".
    private struct FolderPath: Identifiable {
        let id: UUID
        let path: String
    }

    /// Folders in display order, skipping the insides of collapsed folders.
    private var visibleFolderRows: [FolderRow] {
        func rows(_ folders: [SnippetFolder], depth: Int) -> [FolderRow] {
            folders.flatMap { folder in
                [FolderRow(folder: folder, depth: depth)]
                    + (expandedFolderIDs.contains(folder.id) ? rows(folder.subfolders, depth: depth + 1) : [])
            }
        }
        return rows(store.folders, depth: 0)
    }

    private var allFolderPaths: [FolderPath] {
        func paths(_ folders: [SnippetFolder], prefix: String) -> [FolderPath] {
            folders.flatMap { folder in
                let name = folder.name.isEmpty ? "Untitled" : folder.name
                let path = prefix.isEmpty ? name : "\(prefix) › \(name)"
                return [FolderPath(id: folder.id, path: path)] + paths(folder.subfolders, prefix: path)
            }
        }
        return paths(store.folders, prefix: "")
    }

    private func folderRow(_ folder: SnippetFolder, depth: Int) -> some View {
        let isExpanded = expandedFolderIDs.contains(folder.id)
        return HStack(spacing: 4) {
            if folder.subfolders.isEmpty {
                Color.clear.frame(width: 12, height: 12)
            } else {
                Button {
                    toggleExpanded(folder.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help(isExpanded ? "Collapse" : "Expand")
            }
            Image(systemName: "folder")
                .foregroundColor(.secondary)
                .frame(width: 16)
            TextField("Folder name", text: folderNameBinding(folder.id))
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(dropTargetFolderID == folder.id ? Color.accentColor.opacity(0.3) : Color.clear)
        )
        .onDrag { NSItemProvider(object: DragPayload.folder(folder.id).string as NSString) }
        .onDrop(of: [.text], isTargeted: dropTargetBinding(folder.id)) { providers in
            acceptDrop(providers, onto: folder.id)
        }
        .contextMenu { folderContextMenu(folder) }
    }

    @ViewBuilder
    private func folderContextMenu(_ folder: SnippetFolder) -> some View {
        Button("New Subfolder") { addSubfolder(inside: folder.id) }
        Menu("Move to") {
            Button("Top Level") { moveFolder(folder.id, inside: nil) }
                .disabled(store.folders.contains { $0.id == folder.id })
            Divider()
            // A folder can't go inside itself or its own subfolders.
            let ownTree = Set([folder].flattened().map { $0.folder.id })
            ForEach(allFolderPaths.filter { !ownTree.contains($0.id) }) { target in
                Button(target.path) { moveFolder(folder.id, inside: target.id) }
                    .disabled(store.folders.folder(withID: target.id)?.subfolders.contains { $0.id == folder.id } == true)
            }
        }
        Divider()
        Button("Delete Folder…") { requestDeletion(of: folder) }
    }

    private func snippetRow(_ snippet: Binding<Snippet>, inFolder folderID: UUID) -> some View {
        let id = snippet.wrappedValue.id
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
                .frame(width: 16)
            TextField("Title", text: snippet.title)
        }
        .onDrag { NSItemProvider(object: DragPayload.snippet(id).string as NSString) }
        .contextMenu {
            Menu("Move to") {
                ForEach(allFolderPaths) { target in
                    Button(target.path) { moveSnippet(id, toFolder: target.id) }
                        .disabled(target.id == folderID)
                }
            }
            Divider()
            Button("Delete Snippet") { removeSnippet(id) }
        }
    }

    // MARK: Dragging

    /// What's being dragged, carried as text so it works with NSItemProvider.
    private enum DragPayload {
        case snippet(UUID)
        case folder(UUID)

        private static let snippetPrefix = "clipstack-snippet:"
        private static let folderPrefix = "clipstack-folder:"

        var string: String {
            switch self {
            case .snippet(let id): return Self.snippetPrefix + id.uuidString
            case .folder(let id): return Self.folderPrefix + id.uuidString
            }
        }

        init?(_ string: String) {
            if string.hasPrefix(Self.snippetPrefix),
               let id = UUID(uuidString: String(string.dropFirst(Self.snippetPrefix.count))) {
                self = .snippet(id)
            } else if string.hasPrefix(Self.folderPrefix),
                      let id = UUID(uuidString: String(string.dropFirst(Self.folderPrefix.count))) {
                self = .folder(id)
            } else {
                return nil
            }
        }
    }

    private func dropTargetBinding(_ folderID: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTargetFolderID == folderID },
            set: { isTargeted in
                if isTargeted {
                    dropTargetFolderID = folderID
                } else if dropTargetFolderID == folderID {
                    dropTargetFolderID = nil
                }
            })
    }

    private func acceptDrop(_ providers: [NSItemProvider], onto folderID: UUID) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            // Text dragged in from other apps isn't a payload and is ignored.
            guard let string = object as? NSString, let payload = DragPayload(string as String) else { return }
            DispatchQueue.main.async {
                switch payload {
                case .snippet(let id): moveSnippet(id, toFolder: folderID)
                case .folder(let id): moveFolder(id, inside: folderID)
                }
            }
        }
        return true
    }

    // MARK: Bindings

    private func folderNameBinding(_ folderID: UUID) -> Binding<String> {
        Binding(
            get: { store.folders.folder(withID: folderID)?.name ?? "" },
            set: { name in
                guard let path = store.folders.indexPath(ofFolder: folderID) else { return }
                store.folders[path: path].name = name
            })
    }

    /// Looked up by ID on every access, so it stays valid when folders move.
    private func snippetsBinding(inFolder folderID: UUID) -> Binding<[Snippet]> {
        Binding(
            get: { store.folders.folder(withID: folderID)?.snippets ?? [] },
            set: { snippets in
                guard let path = store.folders.indexPath(ofFolder: folderID) else { return }
                store.folders[path: path].snippets = snippets
            })
    }

    private var selectedSnippetContentBinding: Binding<String>? {
        guard let folderID = selectedFolderID, let snippetID = selectedSnippetID,
              store.folders.folder(withID: folderID)?.snippets.contains(where: { $0.id == snippetID }) == true
        else { return nil }
        return Binding(
            get: {
                store.folders.folder(withID: folderID)?.snippets.first { $0.id == snippetID }?.content ?? ""
            },
            set: { content in
                guard let path = store.folders.indexPath(ofFolder: folderID),
                      let index = store.folders[path: path].snippets.firstIndex(where: { $0.id == snippetID })
                else { return }
                store.folders[path: path].snippets[index].content = content
            })
    }

    // MARK: Actions

    private func toggleExpanded(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    /// Expands `folderID` and every folder above it so its contents show.
    private func reveal(_ folderID: UUID) {
        guard let path = store.folders.indexPath(ofFolder: folderID) else { return }
        for depth in 1...path.count {
            expandedFolderIDs.insert(store.folders[path: Array(path.prefix(depth))].id)
        }
    }

    private func addFolder() {
        let folder = store.addFolder(named: "New Folder", inside: nil)
        selectedFolderID = folder.id
    }

    private func addSubfolder() {
        guard let selectedFolderID else { return }
        addSubfolder(inside: selectedFolderID)
    }

    private func addSubfolder(inside parentID: UUID) {
        let folder = store.addFolder(named: "New Folder", inside: parentID)
        reveal(parentID)
        selectedFolderID = folder.id
    }

    private func moveFolder(_ folderID: UUID, inside parentID: UUID?) {
        guard store.moveFolder(id: folderID, inside: parentID) else { return }
        if let parentID { reveal(parentID) }
    }

    private func moveSnippet(_ snippetID: UUID, toFolder folderID: UUID) {
        guard store.moveSnippet(id: snippetID, toFolder: folderID) else { return }
        // The snippet left the folder on screen; drop its stale selection.
        if selectedSnippetID == snippetID { selectedSnippetID = nil }
    }

    private func removeSelectedFolder() {
        guard let selectedFolderID, let folder = store.folders.folder(withID: selectedFolderID) else { return }
        requestDeletion(of: folder)
    }

    /// Empty folders go at once; ones with contents ask first.
    private func requestDeletion(of folder: SnippetFolder) {
        if folder.snippets.isEmpty && folder.subfolders.isEmpty {
            removeFolder(folder.id)
        } else {
            folderPendingDeletion = folder
        }
    }

    private func removeFolder(_ folderID: UUID) {
        let removedIDs = store.folders.folder(withID: folderID).map { [$0].flattened().map { $0.folder.id } } ?? []
        store.removeFolder(id: folderID)
        if let selected = selectedFolderID, removedIDs.contains(selected) {
            selectedFolderID = nil
            selectedSnippetID = nil
        }
        expandedFolderIDs.subtract(removedIDs)
    }

    private var deletionDialogShown: Binding<Bool> {
        Binding(get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } })
    }

    private var deletionTitle: String {
        let name = folderPendingDeletion?.name ?? ""
        return "Delete “\(name.isEmpty ? "Untitled" : name)” and everything in it?"
    }

    private var deletionMessage: String {
        guard let folder = folderPendingDeletion else { return "" }
        let snippetCount = folder.totalSnippetCount
        let folderCount = [folder].flattened().count - 1
        var parts = ["\(snippetCount) snippet\(snippetCount == 1 ? "" : "s")"]
        if folderCount > 0 {
            parts.append("\(folderCount) subfolder\(folderCount == 1 ? "" : "s")")
        }
        return "It contains \(parts.joined(separator: " and ")). This can’t be undone."
    }

    private func addSnippet() {
        guard let folderID = selectedFolderID,
              let path = store.folders.indexPath(ofFolder: folderID) else { return }
        let snippet = Snippet(title: "New Snippet", content: "")
        store.folders[path: path].snippets.append(snippet)
        selectedSnippetID = snippet.id
    }

    private func removeSnippet() {
        guard let selectedSnippetID else { return }
        removeSnippet(selectedSnippetID)
    }

    private func removeSnippet(_ snippetID: UUID) {
        var tree = store.folders
        tree.removeSnippet(id: snippetID)
        store.folders = tree
        if selectedSnippetID == snippetID { selectedSnippetID = nil }
    }

    private func save() {
        guard store.saveNow() else {
            showSaveError = true
            return
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Snippets saved",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        savedConfirmationCount += 1
        let count = savedConfirmationCount
        // Swapped without animation: a cross-fade overlaps the two labels' text.
        showSavedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Only the most recent save gets to clear the confirmation.
            guard count == savedConfirmationCount else { return }
            showSavedConfirmation = false
        }
    }
}
