import Foundation

/// Imports snippet collections from a file. Supports the classic ClipMenu XML
/// export format (<folders><folder><title>…<snippets><snippet>…), this app's
/// own JSON format, and Text Blaze folder exports (JSON).
enum SnippetImporter {
    enum ImportError: LocalizedError {
        case unsupportedFormat
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "The file is not a recognized snippet format (classic ClipMenu XML, ClipStack JSON, or Text Blaze JSON)."
            case .emptyFile:
                return "No snippets were found in the file."
            }
        }
    }

    static func importFolders(from url: URL) throws -> [SnippetFolder] {
        let data = try Data(contentsOf: url)
        let folders: [SnippetFolder]
        switch url.pathExtension.lowercased() {
        case "json":
            // ClipStack's own format first, then Text Blaze folder exports.
            if let own = try? JSONDecoder().decode([SnippetFolder].self, from: data), !own.isEmpty {
                folders = own
            } else {
                folders = try parseTextBlaze(data)
            }
        default:
            folders = try parseXML(data)
        }
        guard !folders.isEmpty else { throw ImportError.emptyFile }
        return folders
    }

    /// Parses a Text Blaze folder export. Text Blaze exports a folder as a
    /// JSON object with a "name" and a "snippets" array whose entries carry
    /// "name"/"shortcut" and plain-text "text". The parser is deliberately
    /// tolerant: it accepts a single folder object, a {"folders": […]}
    /// wrapper, or a top-level array of folders, and falls back across
    /// common field-name variants. Dynamic Text Blaze {commands} arrive as
    /// literal text.
    private static func parseTextBlaze(_ data: Data) throws -> [SnippetFolder] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.unsupportedFormat
        }

        func string(_ dict: [String: Any], _ keys: [String]) -> String? {
            for key in keys {
                if let value = dict[key] as? String, !value.isEmpty { return value }
            }
            return nil
        }

        func folder(from dict: [String: Any]) -> SnippetFolder? {
            guard let snippetDicts = dict["snippets"] as? [[String: Any]] else { return nil }
            var snippets: [Snippet] = []
            for entry in snippetDicts {
                let content = string(entry, ["text", "content", "body"])
                    ?? (entry["data"] as? [String: Any]).flatMap { string($0, ["text", "content"]) }
                guard let content else { continue }
                let title = string(entry, ["name", "title", "label", "shortcut"])
                    ?? String(content.prefix(30))
                snippets.append(Snippet(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                        content: content))
            }
            guard !snippets.isEmpty else { return nil }
            let name = string(dict, ["name", "title", "label"]) ?? "Text Blaze Import"
            return SnippetFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                 snippets: snippets)
        }

        var folders: [SnippetFolder] = []
        if let dict = root as? [String: Any] {
            if let single = folder(from: dict) {
                folders.append(single)
            }
            if let wrapped = dict["folders"] as? [[String: Any]] {
                folders.append(contentsOf: wrapped.compactMap(folder(from:)))
            }
        } else if let array = root as? [[String: Any]] {
            folders.append(contentsOf: array.compactMap(folder(from:)))
        }

        guard !folders.isEmpty else { throw ImportError.unsupportedFormat }
        return folders
    }

    private static func parseXML(_ data: Data) throws -> [SnippetFolder] {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw ImportError.unsupportedFormat
        }
        guard let folderNodes = try? document.nodes(forXPath: "/folders/folder"),
              !folderNodes.isEmpty else {
            throw ImportError.unsupportedFormat
        }

        var folders: [SnippetFolder] = []
        for folderNode in folderNodes {
            let name = (try? folderNode.nodes(forXPath: "title").first?.stringValue)
                .flatMap { $0 }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
            var snippets: [Snippet] = []
            for snippetNode in (try? folderNode.nodes(forXPath: "snippets/snippet")) ?? [] {
                let title = (try? snippetNode.nodes(forXPath: "title").first?.stringValue)
                    .flatMap { $0 }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let content = (try? snippetNode.nodes(forXPath: "content").first?.stringValue)
                    .flatMap { $0 } ?? ""
                snippets.append(Snippet(title: title, content: content))
            }
            folders.append(SnippetFolder(name: name, snippets: snippets))
        }
        return folders
    }
}
