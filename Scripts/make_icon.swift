// One-shot: render an SF Symbol to a 1024x1024 PNG for the app icon.
// Run: swift Scripts/make_icon.swift <output.png>
import AppKit

guard CommandLine.arguments.count > 1 else {
    print("usage: swift make_icon.swift <output.png>")
    exit(1)
}

let size: CGFloat = 1024
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.62, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [
        NSColor(red: 0.35, green: 0.45, blue: 1.0, alpha: 1), // kimi blue-violet
        .white,
    ]))
guard let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) else {
    print("symbol not found")
    exit(1)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
// rounded-rect dark background
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                      xRadius: size * 0.22, yRadius: size * 0.22)
NSColor(white: 0.09, alpha: 1).setFill()
bg.fill()
// centered symbol
let symSize = symbol.size
let rect = NSRect(x: (size - symSize.width) / 2, y: (size - symSize.height) / 2,
                  width: symSize.width, height: symSize.height)
symbol.draw(in: rect)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("png encode failed")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
