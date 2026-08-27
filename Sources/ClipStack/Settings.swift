import AppKit
import Combine
import ServiceManagement

/// App-wide user settings, persisted in UserDefaults.
/// Mirrors the preference surface of the original ClipMenu.
final class Settings: ObservableObject {
    static let shared = Settings()
    static let changedNotification = Notification.Name("SettingsChanged")

    private let defaults = UserDefaults.standard

    // MARK: History
    @Published var maxHistorySize: Int { didSet { save("maxHistorySize", maxHistorySize) } }
    @Published var persistHistory: Bool { didSet { save("persistHistory", persistHistory) } }
    @Published var ignoreConcealedContent: Bool { didSet { save("ignoreConcealedContent", ignoreConcealedContent) } }
    @Published var captureImages: Bool { didSet { save("captureImages", captureImages) } }
    @Published var captureFiles: Bool { didSet { save("captureFiles", captureFiles) } }

    // MARK: Menu
    @Published var inlineItemCount: Int { didSet { save("inlineItemCount", inlineItemCount) } }
    @Published var itemsPerFolder: Int { didSet { save("itemsPerFolder", itemsPerFolder) } }
    @Published var maxTitleLength: Int { didSet { save("maxTitleLength", maxTitleLength) } }
    @Published var numericKeyEquivalents: Bool { didSet { save("numericKeyEquivalents", numericKeyEquivalents) } }
    @Published var showItemNumbers: Bool { didSet { save("showItemNumbers", showItemNumbers) } }
    @Published var showImageThumbnails: Bool { didSet { save("showImageThumbnails", showImageThumbnails) } }
    @Published var showToolTips: Bool { didSet { save("showToolTips", showToolTips) } }

    // MARK: Behavior
    @Published var pasteAutomatically: Bool { didSet { save("pasteAutomatically", pasteAutomatically) } }
    @Published var pasteSnippetsAutomatically: Bool { didSet { save("pasteSnippetsAutomatically", pasteSnippetsAutomatically) } }
    @Published var excludedBundleIDs: [String] { didSet { save("excludedBundleIDs", excludedBundleIDs) } }
    @Published var launchAtLogin: Bool {
        didSet {
            save("launchAtLogin", launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    // MARK: Updates
    @Published var autoUpdateEnabled: Bool { didSet { save("autoUpdateEnabled", autoUpdateEnabled) } }

    // MARK: Backup
    @Published var backupEnabled: Bool { didSet { save("backupEnabled", backupEnabled) } }
    @Published var backupFolderPath: String { didSet { save("backupFolderPath", backupFolderPath) } }

    // MARK: Hotkeys
    @Published var historyHotKey: KeyCombo? { didSet { saveCombo("historyHotKey", historyHotKey) } }
    @Published var snippetsHotKey: KeyCombo? { didSet { saveCombo("snippetsHotKey", snippetsHotKey) } }
    @Published var encodeHotKey: KeyCombo? { didSet { saveCombo("encodeHotKey", encodeHotKey) } }
    @Published var decodeHotKey: KeyCombo? { didSet { saveCombo("decodeHotKey", decodeHotKey) } }

    private init() {
        defaults.register(defaults: [
            "maxHistorySize": 30,
            "persistHistory": true,
            "ignoreConcealedContent": true,
            "captureImages": true,
            "captureFiles": true,
            "inlineItemCount": 10,
            "itemsPerFolder": 10,
            "maxTitleLength": 50,
            "numericKeyEquivalents": true,
            "showItemNumbers": true,
            "showImageThumbnails": true,
            "showToolTips": true,
            "pasteAutomatically": false,
            "pasteSnippetsAutomatically": true,
            "launchAtLogin": false,
            "autoUpdateEnabled": true,
            "backupEnabled": true,
            "backupFolderPath": Self.defaultBackupFolder() ?? "",
        ])

        maxHistorySize = defaults.integer(forKey: "maxHistorySize")
        persistHistory = defaults.bool(forKey: "persistHistory")
        ignoreConcealedContent = defaults.bool(forKey: "ignoreConcealedContent")
        captureImages = defaults.bool(forKey: "captureImages")
        captureFiles = defaults.bool(forKey: "captureFiles")
        inlineItemCount = defaults.integer(forKey: "inlineItemCount")
        itemsPerFolder = defaults.integer(forKey: "itemsPerFolder")
        maxTitleLength = defaults.integer(forKey: "maxTitleLength")
        numericKeyEquivalents = defaults.bool(forKey: "numericKeyEquivalents")
        showItemNumbers = defaults.bool(forKey: "showItemNumbers")
        showImageThumbnails = defaults.bool(forKey: "showImageThumbnails")
        showToolTips = defaults.bool(forKey: "showToolTips")
        pasteAutomatically = defaults.bool(forKey: "pasteAutomatically")
        pasteSnippetsAutomatically = defaults.bool(forKey: "pasteSnippetsAutomatically")
        autoUpdateEnabled = defaults.bool(forKey: "autoUpdateEnabled")
        backupEnabled = defaults.bool(forKey: "backupEnabled")
        backupFolderPath = defaults.string(forKey: "backupFolderPath") ?? ""
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        historyHotKey = Self.loadCombo(defaults, "historyHotKey") ?? KeyCombo.defaultHistory
        snippetsHotKey = Self.loadCombo(defaults, "snippetsHotKey") ?? KeyCombo.defaultSnippets
        encodeHotKey = Self.loadCombo(defaults, "encodeHotKey") ?? KeyCombo.defaultEncode
        decodeHotKey = Self.loadCombo(defaults, "decodeHotKey") ?? KeyCombo.defaultDecode
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    private func saveCombo(_ key: String, _ combo: KeyCombo?) {
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
            defaults.set(true, forKey: key + ".cleared")
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    private static func loadCombo(_ defaults: UserDefaults, _ key: String) -> KeyCombo? {
        if let data = defaults.data(forKey: key) {
            return try? JSONDecoder().decode(KeyCombo.self, from: data)
        }
        if defaults.bool(forKey: key + ".cleared") { return KeyCombo.none }
        return nil
    }

    /// Locates the Google Drive for desktop sync folder, if installed, and
    /// proposes a backup directory inside it.
    static func defaultBackupFolder() -> String? {
        let fileManager = FileManager.default
        let cloudStorage = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage")
        if let entries = try? fileManager.contentsOfDirectory(at: cloudStorage, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.hasPrefix("GoogleDrive-") {
                let myDrive = entry.appendingPathComponent("My Drive")
                if fileManager.fileExists(atPath: myDrive.path) {
                    return myDrive.appendingPathComponent("ClipStack Backups").path
                }
            }
        }
        let legacy = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Google Drive/My Drive")
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy.appendingPathComponent("ClipStack Backups").path
        }
        return nil
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login change failed: \(error.localizedDescription)")
        }
    }
}
