import Foundation

/// Automatic backups of snippets + history into a folder — by default the
/// Google Drive for desktop sync folder, so backups land in Drive without any
/// API integration. Runs a daily backup and keeps the most recent ones.
final class BackupManager {
    static let shared = BackupManager()
    static let didBackUpNotification = Notification.Name("BackupManagerDidBackUp")

    /// How many timestamped backups to keep in the backup folder.
    static let keepCount = 14
    private static let lastBackupKey = "lastBackupDate"

    private var settings: Settings!
    private var history: HistoryStore!
    private var snippets: SnippetStore!
    private var timer: Timer?

    private init() {}

    func configure(settings: Settings, history: HistoryStore, snippets: SnippetStore) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
    }

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date
    }

    func start() {
        stop()
        // Check hourly; back up when the last backup is over a day old.
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            self?.backUpIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Also check shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.backUpIfDue()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func backUpIfDue() {
        guard settings.backupEnabled, !settings.backupFolderPath.isEmpty else { return }
        if let last = lastBackupDate, Date().timeIntervalSince(last) < 24 * 3600 { return }
        do {
            try backUpNow()
        } catch {
            NSLog("Automatic backup failed: \(error.localizedDescription)")
        }
    }

    /// Performs a backup immediately. Returns the created backup directory.
    @discardableResult
    func backUpNow() throws -> URL {
        let baseFolder = URL(fileURLWithPath: settings.backupFolderPath, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: baseFolder, withIntermediateDirectories: true)

        // Flush pending saves so the copied files are current.
        history.saveNow()
        snippets.saveNow()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let backupDir = baseFolder.appendingPathComponent("ClipStack Backup \(formatter.string(from: Date()))",
                                                          isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let source = HistoryStore.storageDirectory
        for name in ["snippets.json", "history.json"] {
            let sourceFile = source.appendingPathComponent(name)
            if fileManager.fileExists(atPath: sourceFile.path) {
                try fileManager.copyItem(at: sourceFile, to: backupDir.appendingPathComponent(name))
            }
        }

        UserDefaults.standard.set(Date(), forKey: Self.lastBackupKey)
        prune(in: baseFolder)
        NotificationCenter.default.post(name: Self.didBackUpNotification, object: self)
        return backupDir
    }

    /// Removes the oldest backups beyond the keep count.
    private func prune(in baseFolder: URL) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: baseFolder,
                                                                 includingPropertiesForKeys: nil) else { return }
        let backups = entries
            .filter { $0.lastPathComponent.hasPrefix("ClipStack Backup ") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } // timestamp order
        guard backups.count > Self.keepCount else { return }
        for old in backups.prefix(backups.count - Self.keepCount) {
            try? fileManager.removeItem(at: old)
        }
    }
}
