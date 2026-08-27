import AppKit

/// Draws the menu bar icon: a monochrome miniature of the app icon's
/// clipboard (board frame, clip, and history lines). Rendered as a template
/// image so macOS recolors it for light/dark menu bars.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            // Clipboard frame: outer rounded rect with the paper area knocked out.
            let frame = NSBezierPath()
            frame.windingRule = .evenOdd
            frame.appendRoundedRect(NSRect(x: 3.5, y: 1.0, width: 11, height: 14),
                                    xRadius: 2.5, yRadius: 2.5)
            frame.appendRoundedRect(NSRect(x: 5.0, y: 2.5, width: 8, height: 11),
                                    xRadius: 1.5, yRadius: 1.5)
            frame.fill()

            // Clip at the top.
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 13.2, width: 5, height: 3.6),
                         xRadius: 1.8, yRadius: 1.8).fill()

            // History lines on the paper.
            let lineWidths: [CGFloat] = [6.0, 4.5, 5.5]
            var lineY: CGFloat = 10.4
            for width in lineWidths {
                NSBezierPath(roundedRect: NSRect(x: 6.0, y: lineY, width: width, height: 1.5),
                             xRadius: 0.75, yRadius: 0.75).fill()
                lineY -= 2.6
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
