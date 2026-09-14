// One-shot: build the app icon from the Jinger logo.
// Strategy: logo fills the icon full-bleed in width; the area above/below is
// filled by stretching the logo's own top/bottom pixel rows, so there is no
// visible seam even if the logo background has a subtle gradient.
// Run from package root: swift Scripts/make_icon.swift
import AppKit

let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logoURL = root.appendingPathComponent("Assets/jinger-logo.png")
let outURL = URL(fileURLWithPath: "/tmp/kimidesk_icon_1024.png")

guard let logo = NSImage(contentsOf: logoURL) else {
    print("logo not found: \(logoURL.path)")
    exit(1)
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 裁成 macOS 圆角图标
let clip = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
    xRadius: canvas * 0.225, yRadius: canvas * 0.225
)
clip.addClip()

// logo 全宽绘制，垂直居中
let lw = logo.size.width, lh = logo.size.height
let logoH = canvas * lh / lw                       // ≈ 500
let logoY = (canvas - logoH) / 2
logo.draw(in: NSRect(x: 0, y: logoY, width: canvas, height: logoH))

// 上缘：拉伸 logo 最上面一行像素（图像坐标系 y 向上，顶行 y = lh-1）
logo.draw(
    in: NSRect(x: 0, y: logoY + logoH, width: canvas, height: canvas - logoY - logoH),
    from: NSRect(x: 0, y: lh - 1, width: lw, height: 1),
    operation: .sourceOver, fraction: 1
)
// 下缘：拉伸 logo 最下面一行像素
logo.draw(
    in: NSRect(x: 0, y: 0, width: canvas, height: logoY),
    from: NSRect(x: 0, y: 0, width: lw, height: 1),
    operation: .sourceOver, fraction: 1
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("png encode failed")
    exit(1)
}
try png.write(to: outURL)
print("wrote \(outURL.path)")
