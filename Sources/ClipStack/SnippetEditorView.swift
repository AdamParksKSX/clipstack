import SwiftUI
import AppKit

/// Two-pane snippet editor: folders + snippets on the left, content on the right.
struct SnippetEditorView: View {
    @ObservedObject var store: SnippetStore
    @Environment(\.undoManager) private var undoManager
    @State private var selectedFolderID: UUID?
    @State private var selectedSnippetID: UUID?
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
                        ForEach($store.folders) { $folder in
                            TextField("Folder name", text: $folder.name)
                                .tag(folder.id)
                        }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Button(action: addFolder) { barIcon("plus") }
                    Button(action: removeFolder) { barIcon("minus") }
                        .disabled(selectedFolderID == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .frame(height: bottomBarHeight)
            }
            .frame(minWidth: 150, idealWidth: 180)

            VStack(spacing: 0) {
                List(selection: $selectedSnippetID) {
                    if let folderIndex = selectedFolderIndex {
                        Section("Snippets") {
                            ForEach($store.folders[folderIndex].snippets) { $snippet in
                                TextField("Title", text: $snippet.title)
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
        .frame(minWidth: 640, minHeight: 380)
        .onChange(of: store.saveStatus) { status in
            // A new edit supersedes the confirmation of the last save.
            if status != .saved { showSavedConfirmation = false }
        }
        // Typing-undo steps hold character ranges in the text they were made
        // in; replayed against another snippet they'd corrupt it.
        .onChange(of: selectedFolderID) { _ in undoManager?.removeAllActions() }
        .onChange(of: selectedSnippetID) { _ in undoManager?.removeAllActions() }
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

    private var selectedFolderIndex: Int? {
        guard let selectedFolderID else { return nil }
        return store.folders.firstIndex { $0.id == selectedFolderID }
    }

    private var selectedSnippetContentBinding: Binding<String>? {
        guard let folderIndex = selectedFolderIndex, let selectedSnippetID,
              let snippetIndex = store.folders[folderIndex].snippets.firstIndex(where: { $0.id == selectedSnippetID })
        else { return nil }
        return $store.folders[folderIndex].snippets[snippetIndex].content
    }

    private func addFolder() {
        let folder = SnippetFolder(name: "New Folder", snippets: [])
        store.folders.append(folder)
        selectedFolderID = folder.id
    }

    private func removeFolder() {
        guard let index = selectedFolderIndex else { return }
        store.folders.remove(at: index)
        selectedFolderID = nil
        selectedSnippetID = nil
    }

    private func addSnippet() {
        guard let index = selectedFolderIndex else { return }
        let snippet = Snippet(title: "New Snippet", content: "")
        store.folders[index].snippets.append(snippet)
        selectedSnippetID = snippet.id
    }

    private func removeSnippet() {
        guard let folderIndex = selectedFolderIndex, let selectedSnippetID else { return }
        store.folders[folderIndex].snippets.removeAll { $0.id == selectedSnippetID }
        self.selectedSnippetID = nil
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
