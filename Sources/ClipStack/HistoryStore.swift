import Foundation

/// Ordered clipboard history (newest first) with JSON persistence.
final class HistoryStore {
    private(set) var clips: [ClipItem] = []
    private let settings: Settings
    private var saveWorkItem: DispatchWorkItem?

    static var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ClipStack", isDirectory: true)
        // One-time migration from the app's pre-rename data directory.
        let legacy = base.appendingPathComponent("ClipMenu V2", isDirectory: true)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path), fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.moveItem(at: legacy, to: directory)
        }
        return directory
    }

    private var fileURL: URL { Self.storageDirectory.appendingPathComponent("history.json") }

    init(settings: Settings) {
        self.settings = settings
        load()
    }

    var favorites: [ClipItem] { clips.filter(\.isFavorite) }

    func add(_ clip: ClipItem) {
        var clip = clip
        // Deduplicate: an existing identical clip moves to the front,
        // keeping its favourite status.
        if let existing = clips.firstIndex(where: { $0.contentEquals(clip) }) {
            clip.isFavorite = clip.isFavorite || clips[existing].isFavorite
            clips.remove(at: existing)
        }
        clips.insert(clip, at: 0)
        trim()
        scheduleSave()
    }

    func remove(id: UUID) {
        clips.removeAll { $0.id == id }
        scheduleSave()
    }

    func toggleFavorite(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].isFavorite.toggle()
        scheduleSave()
    }

    /// Replaces a text clip's content. Rich-text data is dropped because it
    /// no longer matches the edited plain text.
    func updateText(id: UUID, text: String) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].kind == .text else { return }
        clips[index].text = text
        clips[index].rtfData = nil
        scheduleSave()
    }

    /// Removes everything except favourites.
    func clear() {
        clips.removeAll { !$0.isFavorite }
        scheduleSave()
    }

    /// Drops the oldest non-favourite clips beyond the history size limit.
    /// Favourites never age out.
    func trim() {
        var excess = clips.count - settings.maxHistorySize
        guard excess > 0 else { return }
        for index in stride(from: clips.count - 1, through: 0, by: -1) where excess > 0 {
            if !clips[index].isFavorite {
                clips.remove(at: index)
                excess -= 1
            }
        }
    }

    private func load() {
        guard settings.persistHistory,
              let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        clips = loaded
        trim()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func saveNow() {
        let directory = Self.storageDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard settings.persistHistory else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        if let data = try? JSONEncoder().encode(clips) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
