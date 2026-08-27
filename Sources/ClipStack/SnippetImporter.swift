import Foundation

/// Imports snippet collections from a file. Supports the classic ClipMenu XML
/// export format (<folders><folder><title>…<snippets><snippet>…) and this
/// app's own JSON format.
enum SnippetImporter {
    enum ImportError: LocalizedError {
        case unsupportedFormat
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "The file is not a recognized snippet format (classic ClipMenu XML or ClipStack JSON)."
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
            folders = try JSONDecoder().decode([SnippetFolder].self, from: data)
        default:
            folders = try parseXML(data)
        }
        guard !folders.isEmpty else { throw ImportError.emptyFile }
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
