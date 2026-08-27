import Foundation
import JavaScriptCore

/// Text-transform actions applied to the current clipboard text, replicating
/// ClipMenu's "script actions". Built-in transforms are native; users can add
/// their own JavaScript actions in
/// ~/Library/Application Support/ClipMenu V2/actions/*.js
/// Each script receives the clipboard text as `clipText` and returns the
/// transformed string (same contract as the original ClipMenu scripts).
struct ClipAction {
    let name: String
    let group: String?
    let transform: (String) -> String?
}

enum ActionEngine {
    static var actionsDirectory: URL {
        HistoryStore.storageDirectory.appendingPathComponent("actions", isDirectory: true)
    }

    /// Trimmed to the transforms the team actually uses; more can be
    /// added back here or dropped into the user scripts folder.
    static let builtIns: [ClipAction] = [
        ClipAction(name: "Encode to Base64", group: nil) {
            Data($0.utf8).base64EncodedString()
        },
        ClipAction(name: "Decode from Base64", group: nil) {
            guard let data = Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return String(data: data, encoding: .utf8)
        },
    ]

    /// User scripts found in the actions directory, run through JavaScriptCore.
    static func userActions() -> [ClipAction] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: actionsDirectory,
                                                               includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                return ClipAction(name: name, group: "User Scripts") { input in
                    runScript(source, clipText: input)
                }
            }
    }

    private static func runScript(_ source: String, clipText: String) -> String? {
        guard let context = JSContext() else { return nil }
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }
        context.setObject(clipText, forKeyedSubscript: "clipText" as NSString)
        // Original ClipMenu scripts use a bare top-level `return`, so wrap the
        // body in a function taking clipText.
        let wrapped = "(function(clipText) {\n\(source)\n})(clipText);"
        let result = context.evaluateScript(wrapped)
        if let jsError {
            NSLog("Action script error: \(jsError)")
            return nil
        }
        guard let result, !result.isUndefined, !result.isNull else { return nil }
        return result.toString()
    }
}
