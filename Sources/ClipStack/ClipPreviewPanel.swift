import AppKit

/// A floating panel that previews a clip in full while the history menu is
/// open: a row's preview (eye) button toggles it, and while it is visible it
/// follows the highlighted row. It sits at menu level beside the menu and
/// never takes focus, so the menu keeps handling the keyboard and mouse.
/// (A Space-bar trigger isn't possible: open menus don't pass key presses on
/// reliably.)
@MainActor
final class ClipPreviewPanel {
    private var panel: NSPanel?
    /// The clip currently shown, if the panel is visible.
    private(set) var clipID: UUID?

    /// Text previews are cut off here; a menu preview never needs megabytes.
    private static let maxPreviewCharacters = 20_000

    var isVisible: Bool { panel?.isVisible == true }

    /// Shows `clip` beside the menu row `row` (or centred when there is none).
    func show(_ clip: ClipItem, beside row: NSView?) {
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        clipID = clip.id
        panel.title = Self.title(for: clip)
        panel.contentView = Self.makeContentView(for: clip)
        panel.setContentSize(Self.preferredSize(for: clip))
        Self.position(panel, beside: row)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        clipID = nil
    }

    // MARK: Layout

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                            styleMask: [.titled, .utilityWindow, .hudWindow, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Menus live at pop-up-menu level; anything lower would sit behind one.
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    /// Prefers the left side of the menu (the status-item menu hugs the right
    /// edge of the screen), falls back to the right, and lines the panel's top
    /// up with the highlighted row, clamped to the visible screen area.
    private static func position(_ panel: NSPanel, beside row: NSView?) {
        guard let row, let window = row.window else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let menuFrame = window.frame
        let rowRect = window.convertToScreen(row.convert(row.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? menuFrame
        let gap: CGFloat = 6

        var x = menuFrame.minX - gap - size.width
        if x < visible.minX {
            x = menuFrame.maxX + gap
        }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = min(max(rowRect.maxY - size.height, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func preferredSize(for clip: ClipItem) -> NSSize {
        switch clip.kind {
        case .image:
            if let data = clip.imagePNGData, let image = NSImage(data: data) {
                let size = image.size
                let scale = min(1, min(600 / max(size.width, 1), 500 / max(size.height, 1)))
                return NSSize(width: max(240, size.width * scale), height: max(160, size.height * scale))
            }
            return NSSize(width: 400, height: 300)
        case .text, .files:
            return NSSize(width: 480, height: 360)
        }
    }

    private static func title(for clip: ClipItem) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named   // "now" rather than "in 0 seconds"
        let now = Date()
        let age = formatter.localizedString(for: min(clip.date, now), relativeTo: now)
        if let app = clip.sourceAppName, !app.isEmpty {
            return "\(app) · \(age)"
        }
        return "Copied \(age)"
    }

    // MARK: Content

    private static func makeContentView(for clip: ClipItem) -> NSView {
        switch clip.kind {
        case .image:
            guard let data = clip.imagePNGData, let image = NSImage(data: data) else {
                return placeholder("No image data")
            }
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            return imageView
        case .text:
            var text = clip.text ?? ""
            if text.count > maxPreviewCharacters {
                text = String(text.prefix(maxPreviewCharacters)) + "\n…"
            }
            return textView(text.isEmpty ? "(empty)" : text)
        case .files:
            return textView(clip.filePaths.joined(separator: "\n"))
        }
    }

    private static func textView(_ string: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = false
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 6, height: 8)
            textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            textView.textColor = .labelColor
            textView.string = string
        }
        return scroll
    }

    private static func placeholder(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }
}
