#!/usr/bin/env swift
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let iconsetPath = "/tmp/Canopy.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // Dark background with rounded corners
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.19
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).setFill()
    path.fill()

    // Draw tree emoji centered
    let emoji = "🌳" as NSString
    let fontSize = s * 0.8
    let font = NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let textSize = emoji.size(withAttributes: attrs)
    let origin = NSPoint(
        x: (s - textSize.width) / 2,
        y: (s - textSize.height) / 2
    )
    emoji.draw(at: origin, withAttributes: attrs)

    image.unlockFocus()

    // Save as PNG
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to render \(name)")
        continue
    }
    let filePath = (iconsetPath as NSString).appendingPathComponent(name)
    try! png.write(to: URL(fileURLWithPath: filePath))
}

print("Generated iconset at \(iconsetPath)")
