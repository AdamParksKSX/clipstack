import SwiftUI

/// Two-pane snippet editor: folders + snippets on the left, content on the right.
struct SnippetEditorView: View {
    @ObservedObject var store: SnippetStore
    @State private var selectedFolderID: UUID?
    @State private var selectedSnippetID: UUID?

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
                    Button(action: addFolder) { Image(systemName: "plus") }
                    Button(action: removeFolder) { Image(systemName: "minus") }
                        .disabled(selectedFolderID == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
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
                    Button(action: addSnippet) { Image(systemName: "plus") }
                        .disabled(selectedFolderID == nil)
                    Button(action: removeSnippet) { Image(systemName: "minus") }
                        .disabled(selectedSnippetID == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 170, idealWidth: 200)

            VStack(alignment: .leading) {
                if let binding = selectedSnippetContentBinding {
                    Text("Content").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: binding)
                        .font(.body.monospaced())
                } else {
                    Spacer()
                    Text("Select a snippet to edit its content")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            }
            .padding(8)
            .frame(minWidth: 260)
        }
        .frame(minWidth: 640, minHeight: 380)
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
}
