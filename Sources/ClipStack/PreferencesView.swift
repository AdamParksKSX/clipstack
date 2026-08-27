import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        TabView {
            GeneralPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuPane(settings: settings)
                .tabItem { Label("Menu", systemImage: "filemenu.and.selection") }
            HistoryPane(settings: settings)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ShortcutsPane(settings: settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            ExcludedAppsPane(settings: settings)
                .tabItem { Label("Excluded", systemImage: "hand.raised") }
            BackupPane(settings: settings)
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.icloud") }
        }
        .frame(width: 480)
        .padding()
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: Settings
    @State private var accessibilityGranted = Paster.isTrusted

    var body: some View {
        Form {
            Toggle("Launch ClipStack at login", isOn: $settings.launchAtLogin)
            Toggle("Paste automatically after selecting a history item", isOn: $settings.pasteAutomatically)
            Toggle("Paste automatically after selecting a snippet", isOn: $settings.pasteSnippetsAutomatically)
                .onChange(of: settings.pasteAutomatically) { newValue in
                    if newValue && !Paster.isTrusted {
                        Paster.requestPermission()
                    }
                    accessibilityGranted = Paster.isTrusted
                }
                .onChange(of: settings.pasteSnippetsAutomatically) { newValue in
                    if newValue && !Paster.isTrusted {
                        Paster.requestPermission()
                    }
                    accessibilityGranted = Paster.isTrusted
                }
            if (settings.pasteAutomatically || settings.pasteSnippetsAutomatically) && !accessibilityGranted {
                Text("Requires the Accessibility permission. Grant it in System Settings → Privacy & Security → Accessibility, then relaunch ClipMenu.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("Without automatic paste, selecting an item copies it to the clipboard for you to paste with ⌘V.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

private struct MenuPane: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Stepper("Items placed inline: \(settings.inlineItemCount)",
                    value: $settings.inlineItemCount, in: 0...50)
            Stepper("Items per folder: \(settings.itemsPerFolder)",
                    value: $settings.itemsPerFolder, in: 1...50)
            Stepper("Maximum title length: \(settings.maxTitleLength)",
                    value: $settings.maxTitleLength, in: 10...200, step: 5)
            Toggle("Number all menu items in their titles", isOn: $settings.showItemNumbers)
            Toggle("Assign number keys (1–9, 0) as shortcuts", isOn: $settings.numericKeyEquivalents)
            Text("With numbered titles, type an item's number to jump to it and press Return to select. Shortcut badges are shown only when title numbering is off.")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle("Show image thumbnails in menu", isOn: $settings.showImageThumbnails)
            Toggle("Show full content as tooltip", isOn: $settings.showToolTips)
        }
        .padding()
    }
}

private struct HistoryPane: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Stepper("Maximum history size: \(settings.maxHistorySize)",
                    value: $settings.maxHistorySize, in: 1...500, step: 5)
            Toggle("Save history to disk (restored at launch)", isOn: $settings.persistHistory)
            Toggle("Capture images", isOn: $settings.captureImages)
            Toggle("Capture copied files", isOn: $settings.captureFiles)
            Toggle("Ignore concealed content (password managers)", isOn: $settings.ignoreConcealedContent)
            Text("Apps that mark clipboard content as concealed or transient (most password managers) are never recorded when this is on.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            LabeledContent("Open history menu:") {
                ShortcutRecorderView(combo: $settings.historyHotKey)
            }
            LabeledContent("Open snippets menu:") {
                ShortcutRecorderView(combo: $settings.snippetsHotKey)
            }
            Text("The menu pops up at the mouse cursor, in any application.")
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            LabeledContent("Encode clipboard to Base64:") {
                ShortcutRecorderView(combo: $settings.encodeHotKey)
            }
            LabeledContent("Decode clipboard from Base64:") {
                ShortcutRecorderView(combo: $settings.decodeHotKey)
            }
            Text("Transforms the clipboard text in place and adds the result to the history.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

private struct BackupPane: View {
    @ObservedObject var settings: Settings
    @State private var lastBackup: Date? = BackupManager.shared.lastBackupDate
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Toggle("Back up snippets and history automatically (daily)", isOn: $settings.backupEnabled)

            LabeledContent("Backup folder:") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayPath)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .trailing)
                    Button("Choose…", action: chooseFolder)
                }
            }

            LabeledContent("Last backup:") {
                Text(lastBackup.map { Self.dateFormatter.string(from: $0) } ?? "Never")
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Back Up Now", action: backUpNow)
                    .disabled(settings.backupFolderPath.isEmpty)
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundColor(.secondary)
                }
            }

            Text("Backups go to your Google Drive sync folder, so Drive uploads them automatically. The \(BackupManager.keepCount) most recent daily backups are kept.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: BackupManager.didBackUpNotification)) { _ in
            lastBackup = BackupManager.shared.lastBackupDate
        }
    }

    private var displayPath: String {
        settings.backupFolderPath.isEmpty
            ? "Not set — choose a folder"
            : (settings.backupFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose the folder to store ClipStack backups"
        if !settings.backupFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.backupFolderPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.backupFolderPath = url.path
        }
    }

    private func backUpNow() {
        do {
            try BackupManager.shared.backUpNow()
            statusMessage = "Backup complete."
        } catch {
            statusMessage = "Backup failed: \(error.localizedDescription)"
        }
        lastBackup = BackupManager.shared.lastBackupDate
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ExcludedAppsPane: View {
    @ObservedObject var settings: Settings
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Clipboard changes are not recorded while these apps are frontmost:")
                .font(.caption)
            List(selection: $selection) {
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(appName(for: bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundColor(.secondary)
                    }
                    .tag(bundleID)
                }
            }
            .frame(minHeight: 140)
            HStack {
                Button("Add App…", action: addApp)
                Button("Remove") {
                    if let selection {
                        settings.excludedBundleIDs.removeAll { $0 == selection }
                    }
                    selection = nil
                }
                .disabled(selection == nil)
            }
        }
        .padding()
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.message = "Choose applications to exclude from clipboard recording"
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let bundleID = Bundle(url: url)?.bundleIdentifier,
                   !settings.excludedBundleIDs.contains(bundleID) {
                    settings.excludedBundleIDs.append(bundleID)
                }
            }
        }
    }
}
