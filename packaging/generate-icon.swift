import AppKit
import Foundation

// Original vector identity: an open geometric D with a teal audiovisual waveform.
// This draws new vector artwork; it does not sample or alter the OBS icon.
let arguments = CommandLine.arguments
guard arguments.count == 2 else { fatalError("Usage: swift generate-icon.swift output.iconset") }
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(size) / 1024)
        let affine = NSAffineTransform(transform: transform)
        affine.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.20, blue: 0.25, alpha: 1),
                   ending: NSColor(srgbRed: 0.025, green: 0.065, blue: 0.10, alpha: 1))!.draw(in: background, angle: -55)
        NSColor(srgbRed: 0.16, green: 0.34, blue: 0.39, alpha: 1).setStroke()
        background.lineWidth = 2
        background.stroke()
        let d = NSBezierPath()
        d.move(to: NSPoint(x: 330, y: 325))
        d.line(to: NSPoint(x: 330, y: 710))
        d.line(to: NSPoint(x: 490, y: 710))
        d.curve(to: NSPoint(x: 700, y: 510), controlPoint1: NSPoint(x: 650, y: 710), controlPoint2: NSPoint(x: 700, y: 625))
        d.curve(to: NSPoint(x: 490, y: 305), controlPoint1: NSPoint(x: 700, y: 390), controlPoint2: NSPoint(x: 650, y: 305))
        d.lineWidth = 82
        d.lineCapStyle = .round
        d.lineJoinStyle = .round
        NSColor(srgbRed: 0.92, green: 0.98, blue: 0.98, alpha: 1).setStroke()
        d.stroke()
        let wave = NSBezierPath()
        for (index, pair) in [(230.0,470.0),(390,470),(440,550),(495,400),(550,500),(610,470),(790,470)].enumerated() {
            let point = NSPoint(x: pair.0, y: pair.1)
            if index == 0 { wave.move(to: point) } else { wave.line(to: point) }
        }
        wave.lineWidth = 38
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        NSColor(srgbRed: 0.12, green: 0.88, blue: 0.73, alpha: 1).setStroke()
        wave.stroke()
        NSColor(srgbRed: 1, green: 0.36, blue: 0.37, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 738, y: 733, width: 64, height: 64)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
