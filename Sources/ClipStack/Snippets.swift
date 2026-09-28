import Foundation
import Combine

struct Snippet: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var content: String
}

struct SnippetFolder: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var snippets: [Snippet]
}

/// User-defined snippet folders, editable in the snippet editor window and
/// shown at the bottom of the clip menu (like the original ClipMenu).
final class SnippetStore: ObservableObject {
    enum SaveStatus: Equatable {
        /// Everything on disk matches what's in memory.
        case saved
        /// An edit is waiting for the autosave debounce.
        case pending
        case failed(String)
    }

    @Published var folders: [SnippetFolder] {
        didSet { scheduleSave() }
    }

    @Published private(set) var saveStatus: SaveStatus = .saved

    private var saveWorkItem: DispatchWorkItem?
    private let fileURL: URL

    init(fileURL: URL = HistoryStore.storageDirectory.appendingPathComponent("snippets.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([SnippetFolder].self, from: data) {
            folders = loaded
        } else {
            folders = [
                SnippetFolder(name: "Snippets", snippets: [
                    Snippet(title: "Example snippet", content: "Edit me in the Snippet Editor"),
                ]),
            ]
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = workItem
        saveStatus = .pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Writes the snippets to disk immediately, superseding any pending autosave.
    @discardableResult
    func saveNow() -> Bool {
        do {
            try save()
            return true
        } catch {
            return false
        }
    }

    /// Like `saveNow()`, but throws the underlying error.
    func save() throws {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(folders).write(to: fileURL, options: .atomic)
            saveStatus = .saved
        } catch {
            saveStatus = .failed(error.localizedDescription)
            throw error
        }
    }
}
