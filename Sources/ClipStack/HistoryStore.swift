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

    func add(_ clip: ClipItem) {
        // Deduplicate: an existing identical clip moves to the front.
        if let existing = clips.firstIndex(where: { $0.contentEquals(clip) }) {
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

    func clear() {
        clips.removeAll()
        scheduleSave()
    }

    func trim() {
        if clips.count > settings.maxHistorySize {
            clips.removeLast(clips.count - settings.maxHistorySize)
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
