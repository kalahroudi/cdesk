// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import AppKit

/// The app icon, drawn in code so the build needs no image tools and stays crisp at every size.
/// It matches assets/logo.svg: an isometric teal cube on a deep teal tile.
enum AppIcon {
    /// - padded: leave the transparent margin macOS expects around Dock icons (824 of 1024).
    static func image(size: CGFloat, padded: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = size / 1024
            let inset: CGFloat = padded ? 100 : 0
            let tile = NSRect(x: inset * s, y: inset * s, width: (1024 - 2 * inset) * s, height: (1024 - 2 * inset) * s)
            let radius = tile.width * 0.2246

            let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
            if padded {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 14 * s; shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
                shadow.set()
                NSColor(srgbRed: 0.03, green: 0.16, blue: 0.22, alpha: 1).setFill(); shape.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGradient(starting: NSColor(srgbRed: 0.078, green: 0.439, blue: 0.486, alpha: 1), ending: NSColor(srgbRed: 0.027, green: 0.165, blue: 0.216, alpha: 1))?
                .draw(in: shape, angle: -55)
            NSGradient(starting: NSColor.white.withAlphaComponent(0.2), ending: NSColor.white.withAlphaComponent(0))?
                .draw(in: shape, relativeCenterPosition: NSPoint(x: 0, y: 0.8))

            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: tile.minX + (x - inset) / (1024 - 2 * inset) * tile.width, y: tile.minY + (y - inset) / (1024 - 2 * inset) * tile.height) }
            func face(_ pts: [(CGFloat, CGFloat)], _ color: NSColor) {
                let p = NSBezierPath()
                p.move(to: pt(pts[0].0, pts[0].1)); for q in pts.dropFirst() { p.line(to: pt(q.0, q.1)) }; p.close()
                color.setFill(); p.fill()
                NSColor(srgbRed: 0.039, green: 0.2, blue: 0.251, alpha: 1).setStroke()
                p.lineWidth = 18 * s * (tile.width / (1024 * s)); p.lineJoinStyle = .round; p.stroke()
            }
            face([(512, 242), (746, 377), (512, 512), (278, 377)], .white)
            face([(278, 377), (512, 512), (512, 782), (278, 647)], NSColor(srgbRed: 0.655, green: 0.953, blue: 0.894, alpha: 1))
            face([(746, 377), (512, 512), (512, 782), (746, 647)], NSColor(srgbRed: 0.176, green: 0.831, blue: 0.749, alpha: 1))
            return true
        }
    }

    /// Writes an .iconset folder for `iconutil -c icns`.
    static func writeIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                          ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        for (name, px) in sizes {
            let img = image(size: px, padded: true)
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            // tiffRepresentation of a point-sized image is 1x, so the pixel size equals px.
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
        }
    }
}
