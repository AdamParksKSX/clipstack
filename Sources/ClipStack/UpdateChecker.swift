import AppKit
import Security

/// Weekly self-updater. Checks the GitHub Releases API for a newer version,
/// downloads the release zip, verifies the new app is signed with the SAME
/// designated requirement as the running app (so a tampered or foreign build
/// is refused), swaps it into place, and offers to relaunch.
///
/// Note: the API is queried anonymously, so checks succeed only while the
/// GitHub repository is public; while it is private the check fails quietly.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "AdamParksKSX/clipstack"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let weekInterval: TimeInterval = 7 * 24 * 3600

    private var settings: Settings!
    private var timer: Timer?
    private var isChecking = false

    private init() {}

    func configure(settings: Settings) {
        self.settings = settings
    }

    var lastCheckDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.checkIfDue()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkIfDue() {
        guard settings.autoUpdateEnabled else { return }
        if let last = lastCheckDate, Date().timeIntervalSince(last) < Self.weekInterval { return }
        check(userInitiated: false)
    }

    /// Runs a check. When user-initiated, outcomes are reported with alerts;
    /// scheduled checks stay silent unless an update is actually installed.
    func check(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                self.finish(userInitiated: userInitiated,
                            message: status == 404
                                ? "Could not reach the releases feed. (The GitHub repository may be private — update checks work once it is public.)"
                                : "Could not reach the releases feed (HTTP \(status)).")
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Self.isVersion(latest, newerThan: self.currentVersion) else {
                self.finish(userInitiated: userInitiated,
                            message: "ClipStack \(self.currentVersion) is up to date.")
                return
            }
            guard let assets = json["assets"] as? [[String: Any]],
                  let zipURLString = assets.compactMap({ $0["browser_download_url"] as? String })
                      .first(where: { $0.hasSuffix(".zip") }),
                  let zipURL = URL(string: zipURLString) else {
                self.finish(userInitiated: userInitiated,
                            message: "Version \(latest) is available but has no downloadable build attached.")
                return
            }
            self.downloadAndInstall(version: latest, from: zipURL, userInitiated: userInitiated)
        }.resume()
    }

    // MARK: Download & install

    private func downloadAndInstall(version: String, from zipURL: URL, userInitiated: Bool) {
        URLSession.shared.downloadTask(with: zipURL) { [weak self] tempFile, _, error in
            guard let self else { return }
            guard let tempFile else {
                self.finish(userInitiated: userInitiated,
                            message: "Downloading version \(version) failed: \(error?.localizedDescription ?? "unknown error").")
                return
            }
            do {
                let newApp = try self.extractApp(fromZip: tempFile)
                guard self.signatureMatchesRunningApp(newApp) else {
                    throw NSError(domain: "ClipStack", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "The downloaded build is not signed with the expected certificate; refusing to install it.",
                    ])
                }
                try self.install(newApp: newApp)
                self.isChecking = false
                DispatchQueue.main.async { self.offerRelaunch(version: version) }
            } catch {
                self.finish(userInitiated: userInitiated,
                            message: "Updating to \(version) failed: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func extractApp(fromZip zipFile: URL) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStackUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipFile.path, staging.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw NSError(domain: "ClipStack", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The downloaded archive could not be extracted."])
        }
        let app = staging.appendingPathComponent("ClipStack.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw NSError(domain: "ClipStack", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The downloaded archive does not contain ClipStack.app."])
        }
        return app
    }

    /// The new bundle must satisfy the running app's designated requirement
    /// (same bundle identifier signed by the same certificate).
    private func signatureMatchesRunningApp(_ appURL: URL) -> Bool {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return false }
        var selfStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic else { return false }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement else { return false }
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &newCode) == errSecSuccess, let newCode else { return false }
        return SecStaticCodeCheckValidity(newCode, [], requirement) == errSecSuccess
    }

    private func install(newApp: URL) throws {
        let fileManager = FileManager.default
        let currentURL = Bundle.main.bundleURL
        let backup = currentURL.deletingLastPathComponent()
            .appendingPathComponent(".\(currentURL.lastPathComponent).previous")
        try? fileManager.removeItem(at: backup)
        try fileManager.moveItem(at: currentURL, to: backup)
        do {
            do {
                try fileManager.moveItem(at: newApp, to: currentURL)
            } catch {
                try fileManager.copyItem(at: newApp, to: currentURL)
            }
        } catch {
            // Put the old version back rather than leaving no app at all.
            try? fileManager.moveItem(at: backup, to: currentURL)
            throw error
        }
        try? fileManager.removeItem(at: backup)
    }

    private func offerRelaunch(version: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ClipStack updated to \(version)"
        alert.informativeText = "The new version has been installed. Relaunch now to start using it?"
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    private func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func finish(userInitiated: Bool, message: String) {
        isChecking = false
        NSLog("Update check: \(message)")
        guard userInitiated else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Check for Updates"
            alert.informativeText = message
            alert.runModal()
        }
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").map { Int($0) ?? 0 }
        let bParts = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(aParts.count, bParts.count) {
            let x = i < aParts.count ? aParts[i] : 0
            let y = i < bParts.count ? bParts[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
