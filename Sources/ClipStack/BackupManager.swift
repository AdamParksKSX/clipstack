import Foundation

/// Automatic backups of snippets into a folder — by default the
/// Google Drive for desktop sync folder, so backups land in Drive without any
/// API integration. Runs backups at a configurable interval and keeps the most recent ones.
final class BackupManager {
    static let shared = BackupManager()
    static let didBackUpNotification = Notification.Name("BackupManagerDidBackUp")

    /// How many timestamped backups to keep in the backup folder.
    static let keepCount = 14
    private static let lastBackupKey = "lastBackupDate"

    private var settings: Settings?
    private var snippets: SnippetStore?
    private var timer: Timer?

    private init() {}

    func configure(settings: Settings, snippets: SnippetStore) {
        self.settings = settings
        self.snippets = snippets
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: Settings.changedNotification, object: nil)
    }

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date
    }

    func start() {
        stop()
        // Check periodically (every 10 minutes) so hourly intervals are timely.
        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
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

    @objc private func settingsChanged() {
        backUpIfDue()
    }

    private func backUpIfDue() {
        guard let settings, settings.backupEnabled, !settings.backupFolderPath.isEmpty else { return }
        if let last = lastBackupDate, Date().timeIntervalSince(last) < settings.backupInterval.timeInterval { return }
        do {
            try backUpNow()
        } catch {
            NSLog("Automatic backup failed: \(error.localizedDescription)")
        }
    }

    /// Performs a backup immediately. Returns the created backup directory.
    @discardableResult
    func backUpNow() throws -> URL {
        guard let settings, let snippets else {
            throw NSError(domain: "ClipStack", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "BackupManager not configured."])
        }
        let baseFolder = URL(fileURLWithPath: settings.backupFolderPath, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: baseFolder, withIntermediateDirectories: true)

        // Flush pending saves so the copied file is current.
        try snippets.save()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let backupDir = baseFolder.appendingPathComponent("ClipStack Backup \(formatter.string(from: Date()))",
                                                          isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let sourceFile = HistoryStore.storageDirectory.appendingPathComponent("snippets.json")
        if fileManager.fileExists(atPath: sourceFile.path) {
            try fileManager.copyItem(at: sourceFile, to: backupDir.appendingPathComponent("snippets.json"))
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
