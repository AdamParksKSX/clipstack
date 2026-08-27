import Foundation
import CryptoKit
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

    static let builtIns: [ClipAction] = [
        ClipAction(name: "Uppercase", group: "Change Case") { $0.uppercased() },
        ClipAction(name: "Lowercase", group: "Change Case") { $0.lowercased() },
        ClipAction(name: "Capitalize Words", group: "Change Case") { $0.capitalized },
        ClipAction(name: "Trim Whitespace", group: "Whitespace") {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        },
        ClipAction(name: "Collapse Spaces", group: "Whitespace") {
            $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        },
        ClipAction(name: "Remove Line Breaks", group: "Whitespace") {
            $0.replacingOccurrences(of: "\r\n", with: " ")
              .replacingOccurrences(of: "\n", with: " ")
              .replacingOccurrences(of: "\r", with: " ")
        },
        ClipAction(name: "Reverse", group: nil) { String($0.reversed()) },
        ClipAction(name: "Encode to Base64", group: "Encoding") {
            Data($0.utf8).base64EncodedString()
        },
        ClipAction(name: "Decode from Base64", group: "Encoding") {
            guard let data = Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return String(data: data, encoding: .utf8)
        },
        ClipAction(name: "Encode URI Component", group: "Encoding") {
            $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
        },
        ClipAction(name: "Decode URI Component", group: "Encoding") { $0.removingPercentEncoding },
        ClipAction(name: "Escape HTML Characters", group: "HTML") {
            $0.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
              .replacingOccurrences(of: "'", with: "&#39;")
        },
        ClipAction(name: "Unescape HTML Characters", group: "HTML") {
            $0.replacingOccurrences(of: "&lt;", with: "<")
              .replacingOccurrences(of: "&gt;", with: ">")
              .replacingOccurrences(of: "&quot;", with: "\"")
              .replacingOccurrences(of: "&#39;", with: "'")
              .replacingOccurrences(of: "&amp;", with: "&")
        },
        ClipAction(name: "Calculate MD5 Hash", group: "Crypt") {
            Insecure.MD5.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
        },
        ClipAction(name: "Calculate SHA-1 Hash", group: "Crypt") {
            Insecure.SHA1.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
        },
        ClipAction(name: "Calculate SHA-256 Hash", group: "Crypt") {
            SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
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
