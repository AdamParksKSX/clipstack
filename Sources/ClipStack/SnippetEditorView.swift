import SwiftUI
import AppKit

/// Three-pane snippet editor: a folder tree (folders can hold subfolders),
/// the selected folder's snippets, and the selected snippet's content.
/// Snippets and folders move by dragging them onto a folder in the tree, or
/// with their right-click "Move to" menu. Double-click a name to rename it.
/// The tree and snippet list are AppKit views (see SnippetTreeViews.swift).
struct SnippetEditorView: View {
    @ObservedObject var store: SnippetStore
    @Environment(\.undoManager) private var undoManager
    @State private var selectedFolderID: UUID?
    @State private var selectedSnippetID: UUID?
    @State private var folderPendingDeletion: SnippetFolder?
    /// A new folder or snippet to put straight into rename mode.
    @State private var folderToRename: UUID?
    @State private var snippetToRename: UUID?
    /// True briefly after an explicit Save, to flash a confirmation.
    @State private var showSavedConfirmation = false
    @State private var savedConfirmationCount = 0
    @State private var showSaveError = false

    /// Shared by all three bottom bars so their dividers line up.
    private let bottomBarHeight: CGFloat = 30

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                paneTitle("Folders")
                SnippetFolderTree(
                    folders: store.folders,
                    selection: $selectedFolderID,
                    renameRequest: $folderToRename,
                    onRename: renameFolder,
                    onMoveFolder: moveFolder,
                    onMoveSnippet: moveSnippet,
                    onNewSubfolder: { addSubfolder(inside: $0) },
                    onDelete: { id in
                        if let folder = store.folders.folder(withID: id) { requestDeletion(of: folder) }
                    })
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
                paneTitle("Snippets")
                if let folderID = selectedFolderID, let folder = store.folders.folder(withID: folderID) {
                    SnippetList(
                        snippets: folder.snippets,
                        folderID: folderID,
                        folders: store.folders,
                        selection: $selectedSnippetID,
                        renameRequest: $snippetToRename,
                        onRename: renameSnippet,
                        onMoveSnippet: moveSnippet,
                        onDelete: removeSnippet)
                } else {
                    Text("Select a folder")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack(spacing: 12) {
                    Button(action: addSnippet) { barIcon("plus") }
                        .disabled(selectedFolderID == nil)
                    Button(action: removeSelectedSnippet) { barIcon("minus") }
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
        .onChange(of: store.saveStatus) { status in
            // A new edit supersedes the confirmation of the last save.
            if status != .saved { showSavedConfirmation = false }
        }
        // Typing-undo steps hold character ranges in the text they were made
        // in; replayed against another snippet they'd corrupt it.
        .onChange(of: selectedFolderID) { _ in
            undoManager?.removeAllActions()
            selectedSnippetID = nil
        }
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

    private func paneTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
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

    // MARK: Content

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

    private func renameFolder(_ folderID: UUID, to name: String) {
        guard let path = store.folders.indexPath(ofFolder: folderID),
              store.folders[path: path].name != name else { return }
        store.folders[path: path].name = name
    }

    private func renameSnippet(_ snippetID: UUID, to title: String) {
        guard let folderID = store.folders.folderID(containingSnippet: snippetID),
              let path = store.folders.indexPath(ofFolder: folderID),
              let index = store.folders[path: path].snippets.firstIndex(where: { $0.id == snippetID }),
              store.folders[path: path].snippets[index].title != title else { return }
        store.folders[path: path].snippets[index].title = title
    }

    private func addFolder() {
        let folder = store.addFolder(named: "New Folder", inside: nil)
        selectedFolderID = folder.id
        folderToRename = folder.id
    }

    private func addSubfolder() {
        guard let selectedFolderID else { return }
        addSubfolder(inside: selectedFolderID)
    }

    private func addSubfolder(inside parentID: UUID) {
        let folder = store.addFolder(named: "New Folder", inside: parentID)
        selectedFolderID = folder.id
        folderToRename = folder.id
    }

    private func moveFolder(_ folderID: UUID, inside parentID: UUID?) {
        store.moveFolder(id: folderID, inside: parentID)
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
        snippetToRename = snippet.id
    }

    private func removeSelectedSnippet() {
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
