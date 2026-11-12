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
    /// Nested folders, shown before the folder's own snippets.
    var subfolders: [SnippetFolder] = []

    /// Whether this folder or any folder inside it holds a snippet.
    var containsSnippets: Bool {
        !snippets.isEmpty || subfolders.contains { $0.containsSnippets }
    }

    /// Snippets in this folder and every folder inside it.
    var totalSnippetCount: Int {
        snippets.count + subfolders.reduce(0) { $0 + $1.totalSnippetCount }
    }

    /// A copy with new IDs throughout, so imported folders (e.g. from a
    /// ClipStack backup of the current snippets) never clash with existing ones.
    func withFreshIDs() -> SnippetFolder {
        SnippetFolder(name: name,
                      snippets: snippets.map { Snippet(title: $0.title, content: $0.content) },
                      subfolders: subfolders.map { $0.withFreshIDs() })
    }
}

extension SnippetFolder {
    // Declared in an extension to keep the memberwise initializer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        snippets = try container.decode([Snippet].self, forKey: .snippets)
        // Snippet files and backups written before 1.4.0 have no subfolders.
        subfolders = try container.decodeIfPresent([SnippetFolder].self, forKey: .subfolders) ?? []
    }
}

/// Tree operations on a list of top-level folders. A folder's position is an
/// index path: its index at the top level, then within each subfolder list.
extension Array where Element == SnippetFolder {
    /// Index path of the folder with `id`, or nil if it isn't in the tree.
    func indexPath(ofFolder id: UUID) -> [Int]? {
        for (index, folder) in enumerated() {
            if folder.id == id { return [index] }
            if let inner = folder.subfolders.indexPath(ofFolder: id) {
                return [index] + inner
            }
        }
        return nil
    }

    /// The folder at a valid, non-empty index path.
    subscript(path path: [Int]) -> SnippetFolder {
        get {
            let folder = self[path[0]]
            return path.count == 1 ? folder : folder.subfolders[path: Array<Int>(path.dropFirst())]
        }
        set {
            if path.count == 1 {
                self[path[0]] = newValue
            } else {
                self[path[0]].subfolders[path: Array<Int>(path.dropFirst())] = newValue
            }
        }
    }

    func folder(withID id: UUID) -> SnippetFolder? {
        indexPath(ofFolder: id).map { self[path: $0] }
    }

    /// The folder holding the snippet with `id`.
    func folderID(containingSnippet id: UUID) -> UUID? {
        for folder in self {
            if folder.snippets.contains(where: { $0.id == id }) { return folder.id }
            if let inner = folder.subfolders.folderID(containingSnippet: id) { return inner }
        }
        return nil
    }

    /// The folder that holds folder `id`: nil for a top-level folder (or one
    /// that isn't in the tree).
    func parentID(ofFolder id: UUID) -> UUID? {
        guard let path = indexPath(ofFolder: id), path.count > 1 else { return nil }
        return self[path: Array<Int>(path.dropLast())].id
    }

    /// Where folder `id` would end up in `parentID`'s subfolders (nil = the
    /// top level) if moved there: before what is now at `index` in that list,
    /// or at the end when `index` is nil. The result counts positions after
    /// the folder leaves its current place. Nil when the move isn't allowed
    /// (into the folder itself or one of its own subfolders) or wouldn't change
    /// anything — including a move to the end of the list it is already in,
    /// so "move into" its own parent is refused rather than reordering.
    func folderMoveDestination(_ id: UUID, into parentID: UUID?, at index: Int? = nil) -> Int? {
        guard let path = indexPath(ofFolder: id) else { return nil }
        let siblings: [SnippetFolder]
        if let parentID {
            // A folder's own subtree is every path starting with its own.
            guard let parentPath = indexPath(ofFolder: parentID),
                  !parentPath.starts(with: path) else { return nil }
            siblings = self[path: parentPath].subfolders
        } else {
            siblings = self
        }
        guard let current = siblings.firstIndex(where: { $0.id == id }) else {
            return Swift.min(Swift.max(index ?? siblings.count, 0), siblings.count)
        }
        guard let index else { return nil }
        let insertion = Swift.min(Swift.max(index, 0), siblings.count)
        // Positions after the folder shift up by one once it's taken out.
        let destination = insertion > current ? insertion - 1 : insertion
        return destination == current ? nil : destination
    }

    /// Every folder in display order with its nesting depth (0 = top level).
    func flattened(depth: Int = 0) -> [(folder: SnippetFolder, depth: Int)] {
        flatMap { [($0, depth)] + $0.subfolders.flattened(depth: depth + 1) }
    }

    /// Removes and returns the folder with `id`, wherever it is in the tree.
    @discardableResult
    mutating func removeFolder(id: UUID) -> SnippetFolder? {
        guard let path = indexPath(ofFolder: id) else { return nil }
        if path.count == 1 {
            return remove(at: path[0])
        }
        let parentPath = Array<Int>(path.dropLast())
        return self[path: parentPath].subfolders.remove(at: path[path.count - 1])
    }

    /// Removes and returns the snippet with `id` from whichever folder holds it.
    @discardableResult
    mutating func removeSnippet(id: UUID) -> Snippet? {
        guard let folderID = folderID(containingSnippet: id),
              let path = indexPath(ofFolder: folderID),
              let index = self[path: path].snippets.firstIndex(where: { $0.id == id }) else { return nil }
        return self[path: path].snippets.remove(at: index)
    }
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

    // MARK: Tree edits
    // Each edit works on a copy and assigns `folders` once, so it is a
    // single change (one autosave, one SwiftUI update).

    /// Adds a folder at the top level, or inside `parentID` when given.
    @discardableResult
    func addFolder(named name: String, inside parentID: UUID?) -> SnippetFolder {
        let folder = SnippetFolder(name: name, snippets: [])
        var tree = folders
        if let parentID, let path = tree.indexPath(ofFolder: parentID) {
            tree[path: path].subfolders.append(folder)
        } else {
            tree.append(folder)
        }
        folders = tree
        return folder
    }

    func removeFolder(id: UUID) {
        var tree = folders
        tree.removeFolder(id: id)
        folders = tree
    }

    /// Moves a folder (with everything in it) into `parentID`'s subfolders,
    /// or the top level when `parentID` is nil: before what is now at `index`
    /// in that list, or at the end when `index` is nil. A move within the
    /// folder's own list reorders it, which is also its order in the menu.
    /// Returns false, changing nothing, for a move into itself or one of its
    /// own subfolders, or one that wouldn't change anything (see
    /// `folderMoveDestination`).
    @discardableResult
    func moveFolder(id: UUID, inside parentID: UUID?, at index: Int? = nil) -> Bool {
        guard let destination = folders.folderMoveDestination(id, into: parentID, at: index) else { return false }
        var tree = folders
        guard let folder = tree.removeFolder(id: id) else { return false }
        // The destination list is untouched by the removal unless it's the
        // folder's own list, which `destination` already allows for.
        if let parentID {
            guard let path = tree.indexPath(ofFolder: parentID) else { return false }
            tree[path: path].subfolders.insert(folder, at: destination)
        } else {
            tree.insert(folder, at: destination)
        }
        folders = tree
        return true
    }

    /// Moves a snippet to the end of folder `folderID`. Returns false,
    /// changing nothing, if it's already there or either one is missing.
    @discardableResult
    func moveSnippet(id: UUID, toFolder folderID: UUID) -> Bool {
        guard folders.folderID(containingSnippet: id) != folderID,
              folders.folder(withID: folderID) != nil else { return false }
        var tree = folders
        guard let snippet = tree.removeSnippet(id: id),
              let path = tree.indexPath(ofFolder: folderID) else { return false }
        tree[path: path].snippets.append(snippet)
        folders = tree
        return true
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
