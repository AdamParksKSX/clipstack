import AppKit
import UniformTypeIdentifiers

/// One captured clipboard entry. Text, rich text, image, and file-list
/// representations are stored so repasting preserves fidelity.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
        case files
    }

    let id: UUID
    let date: Date
    let kind: Kind
    var text: String?
    var rtfData: Data?
    var imagePNGData: Data?
    var filePaths: [String]
    var isFavorite: Bool

    init(id: UUID = UUID(), date: Date = Date(), kind: Kind,
         text: String? = nil, rtfData: Data? = nil,
         imagePNGData: Data? = nil, filePaths: [String] = [],
         isFavorite: Bool = false) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
        self.rtfData = rtfData
        self.imagePNGData = imagePNGData
        self.filePaths = filePaths
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(Kind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        imagePNGData = try container.decodeIfPresent(Data.self, forKey: .imagePNGData)
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        // History files written before favourites existed lack this key.
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    /// Compares user-visible content (used for deduplication).
    func contentEquals(_ other: ClipItem) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return imagePNGData == other.imagePNGData
        case .files: return filePaths == other.filePaths
        }
    }

    /// Single-line title for menu display.
    func menuTitle(maxLength: Int) -> String {
        let raw: String
        switch kind {
        case .text:
            raw = (text ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
        case .image:
            raw = "🏞 Image"
        case .files:
            raw = filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        }
        if raw.isEmpty { return "(empty)" }
        if raw.count > maxLength {
            return String(raw.prefix(maxLength)) + "…"
        }
        return raw
    }

    var toolTip: String? {
        switch kind {
        case .text:
            guard let text else { return nil }
            return text.count > 1500 ? String(text.prefix(1500)) + "…" : text
        case .image:
            return "Image copied \(Self.dateFormatter.string(from: date))"
        case .files:
            return filePaths.joined(separator: "\n")
        }
    }

    func thumbnail(height: CGFloat) -> NSImage? {
        guard kind == .image, let data = imagePNGData, let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.height > 0 else { return nil }
        let scale = min(1, height / size.height)
        let newSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        thumb.unlockFocus()
        return thumb
    }

    /// Writes this clip back onto the given pasteboard.
    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch kind {
        case .text:
            var wroteRTF = false
            if let rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
                wroteRTF = true
            }
            if let text {
                if wroteRTF {
                    pasteboard.setString(text, forType: .string)
                } else {
                    pasteboard.setString(text, forType: .string)
                }
            }
        case .image:
            if let imagePNGData {
                pasteboard.setData(imagePNGData, forType: .png)
                if let image = NSImage(data: imagePNGData), let tiff = image.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }
        case .files:
            let urls = filePaths.map { URL(fileURLWithPath: $0) } as [NSURL]
            pasteboard.writeObjects(urls as [NSPasteboardWriting])
            if let joined = text {
                pasteboard.setString(joined, forType: .string)
            }
        }
    }

    /// Reads the current pasteboard contents into a ClipItem, or nil if unsupported/empty.
    static func read(from pasteboard: NSPasteboard, settings: Settings) -> ClipItem? {
        // File lists take priority over their text representation.
        if settings.captureFiles,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map(\.path)
            return ClipItem(kind: .files, text: paths.joined(separator: "\n"), filePaths: paths)
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let rtf = pasteboard.data(forType: .rtf)
            return ClipItem(kind: .text, text: text, rtfData: rtf)
        }

        if settings.captureImages {
            if let png = pasteboard.data(forType: .png) {
                guard png.count <= maxImageBytes else { return nil }
                return ClipItem(kind: .image, imagePNGData: png)
            }
            if let tiff = pasteboard.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                guard png.count <= maxImageBytes else { return nil }
                return ClipItem(kind: .image, imagePNGData: png)
            }
        }
        return nil
    }

    /// Images larger than this are not captured (keeps the history file sane).
    static let maxImageBytes = 10 * 1024 * 1024

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
