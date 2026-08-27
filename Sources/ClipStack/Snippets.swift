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
    @Published var folders: [SnippetFolder] {
        didSet { scheduleSave() }
    }

    private var saveWorkItem: DispatchWorkItem?
    private var fileURL: URL { HistoryStore.storageDirectory.appendingPathComponent("snippets.json") }

    init() {
        if let data = try? Data(contentsOf: HistoryStore.storageDirectory.appendingPathComponent("snippets.json")),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func saveNow() {
        try? FileManager.default.createDirectory(at: HistoryStore.storageDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(folders) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
