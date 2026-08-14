import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-app-icon.swift <appiconset-directory>\n", stderr)
    exit(2)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: CGFloat(size) * 0.04, dy: CGFloat(size) * 0.04),
                 xRadius: CGFloat(size) * 0.18,
                 yRadius: CGFloat(size) * 0.18).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: CGFloat(size) * 0.39, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let glyph = ">_" as NSString
    glyph.draw(in: NSRect(x: 0, y: CGFloat(size) * 0.26, width: CGFloat(size), height: CGFloat(size) * 0.5),
               withAttributes: attributes)

    NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.37, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: CGFloat(size) * 0.70,
                               y: CGFloat(size) * 0.18,
                               width: CGFloat(size) * 0.11,
                               height: CGFloat(size) * 0.11)).fill()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for (name, size) in sizes {
    try drawIcon(size: size).write(to: destination.appendingPathComponent(name), options: .atomic)
}
