// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import AppKit

/// The menu bar glyph: a filled cube while Colima runs, an outline when stopped. Drawn as a template image so macOS tints it for light and dark.
enum StatusIcon {
    enum State { case running, stopped, busy }

    static func image(_ state: State) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let hex = NSBezierPath()
            hex.move(to: NSPoint(x: 9, y: 1.8)); hex.line(to: NSPoint(x: 15.2, y: 5.4)); hex.line(to: NSPoint(x: 15.2, y: 12.6))
            hex.line(to: NSPoint(x: 9, y: 16.2)); hex.line(to: NSPoint(x: 2.8, y: 12.6)); hex.line(to: NSPoint(x: 2.8, y: 5.4)); hex.close()
            let y = NSBezierPath()
            y.move(to: NSPoint(x: 2.8, y: 5.4)); y.line(to: NSPoint(x: 9, y: 9)); y.line(to: NSPoint(x: 15.2, y: 5.4))
            y.move(to: NSPoint(x: 9, y: 9)); y.line(to: NSPoint(x: 9, y: 16.2))
            for p in [hex, y] { p.lineJoinStyle = .round; p.lineCapStyle = .round }
            NSColor.black.setFill(); NSColor.black.setStroke()
            switch state {
            case .running:
                hex.fill()
                NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
                y.lineWidth = 1.3; y.stroke()
            case .stopped:
                hex.lineWidth = 1.4; hex.stroke(); y.lineWidth = 1.2; y.stroke()
            case .busy:
                let dash: [CGFloat] = [3, 2]
                hex.lineWidth = 1.4; hex.setLineDash(dash, count: 2, phase: 0); hex.stroke()
                y.lineWidth = 1.2; y.setLineDash([2, 2], count: 2, phase: 0); y.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
