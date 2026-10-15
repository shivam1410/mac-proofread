// Renders the app icon to a 1024px PNG: `swift make_icon.swift out.png`.
// Drawn in code so the repo needs no binary assets.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon grid: 824px rounded square centered on a 1024px canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.42, green: 0.33, blue: 0.96, alpha: 1),
                    NSColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1)])!
    .draw(in: shape, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = (NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: nil)
    ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil))!
    .withSymbolConfiguration(config)!
let s = symbol.size
symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: out))
