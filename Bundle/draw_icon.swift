import AppKit

// Renders a 1024x1024 macOS-style app icon: blue squircle tile with a white
// clipboard holding colored "history" lines.

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { fatalError() }

// --- Squircle tile with drop shadow ---
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 36,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(calibratedRed: 0.24, green: 0.38, blue: 0.90, alpha: 1).setFill()
tile.fill()
context.restoreGState()

let tileGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.46, green: 0.60, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.17, green: 0.30, blue: 0.82, alpha: 1),
])!
tileGradient.draw(in: tile, angle: -90)

// Subtle top highlight for depth
let highlight = NSBezierPath(roundedRect: tileRect.insetBy(dx: 6, dy: 6), xRadius: 180, yRadius: 180)
NSColor.white.withAlphaComponent(0.12).setStroke()
highlight.lineWidth = 8
highlight.stroke()

// --- Clipboard board (darker backing) ---
let boardRect = NSRect(x: 277, y: 185, width: 470, height: 590)
let board = NSBezierPath(roundedRect: boardRect, xRadius: 52, yRadius: 52)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                  color: NSColor.black.withAlphaComponent(0.30).cgColor)
NSColor(calibratedRed: 0.82, green: 0.60, blue: 0.34, alpha: 1).setFill() // wood tone rim
board.fill()
context.restoreGState()
let boardGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.90, green: 0.70, blue: 0.44, alpha: 1),
    NSColor(calibratedRed: 0.74, green: 0.52, blue: 0.28, alpha: 1),
])!
boardGradient.draw(in: board, angle: -90)

// --- Paper sheet ---
let paperRect = NSRect(x: 312, y: 218, width: 400, height: 500)
let paper = NSBezierPath(roundedRect: paperRect, xRadius: 24, yRadius: 24)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -6), blur: 12,
                  color: NSColor.black.withAlphaComponent(0.22).cgColor)
NSColor.white.setFill()
paper.fill()
context.restoreGState()
let paperGradient = NSGradient(colors: [
    NSColor.white,
    NSColor(calibratedWhite: 0.93, alpha: 1),
])!
paperGradient.draw(in: paper, angle: -90)

// --- History lines on the paper ---
struct Line { let width: CGFloat; let color: NSColor }
let accent = NSColor(calibratedRed: 0.24, green: 0.48, blue: 0.98, alpha: 1)
let gray = NSColor(calibratedWhite: 0.72, alpha: 1)
let lightGray = NSColor(calibratedWhite: 0.80, alpha: 1)
let lines: [Line] = [
    Line(width: 280, color: accent),
    Line(width: 320, color: gray),
    Line(width: 240, color: lightGray),
    Line(width: 300, color: gray),
    Line(width: 200, color: lightGray),
]
var lineY: CGFloat = paperRect.maxY - 105
for line in lines {
    let rect = NSRect(x: paperRect.minX + 42, y: lineY, width: line.width, height: 36)
    let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    line.color.setFill()
    path.fill()
    lineY -= 82
}

// --- Metal clip at top ---
// Clip stem (the part behind the board top edge)
let clipOuter = NSBezierPath(roundedRect: NSRect(x: 427, y: 700, width: 170, height: 118),
                             xRadius: 38, yRadius: 38)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -6), blur: 10,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
clipOuter.fill()
context.restoreGState()
let clipGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.92, alpha: 1),
    NSColor(calibratedWhite: 0.62, alpha: 1),
])!
clipGradient.draw(in: clipOuter, angle: -90)

// Clip hole
let hole = NSBezierPath(roundedRect: NSRect(x: 462, y: 726, width: 100, height: 44),
                        xRadius: 22, yRadius: 22)
NSColor(calibratedRed: 0.20, green: 0.33, blue: 0.85, alpha: 1).setFill()
hole.fill()

image.unlockFocus()

// --- Write PNG ---
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! png.write(to: out)
print("Wrote \(out.path)")
