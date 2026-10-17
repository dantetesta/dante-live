import AppKit
import CoreImage
import Vision
import ImageIO

struct QRArtwork {
    let png: Data
    let payload: String
    static func rgb(_ value: Double) -> NSColor {
        let v = UInt32(min(0xFFFFFF, max(0, value.isFinite ? value : 0)))
        return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    static func luminance(_ c: NSColor) -> Double {
        func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }
    static func logo(_ bytes: Data) throws -> Data {
        guard bytes.count <= 8_000_000, let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw QRContent.fail("Escolha uma imagem PNG ou JPEG de até 8 MB.") }
        return png
    }
    static func generate(_ s: [String: Any]) throws -> QRArtwork {
        let payload = try QRContent.payload(s)
        let ink = rgb(s.number("qrInk", 0x102632)), background = rgb(s.number("qrBackground", 0xFFFFFF))
        let contrast = (luminance(background) + 0.05) / (luminance(ink) + 0.05)
        guard contrast >= 4.5 else { throw QRContent.fail("Use um código escuro sobre fundo claro, com mais contraste entre as cores.") }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw QRContent.fail("O gerador de QR Code não está disponível neste Mac.") }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage"); filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let matrix = filter.outputImage else { throw QRContent.fail("Reduza o conteúdo para gerar o código.") }
        let n = Int(matrix.extent.width), cell = 10, quiet = 4
        guard n > 0, n <= 177 else { throw QRContent.fail("Conteúdo muito longo para o QR Code.") }
        var pixels = [UInt8](repeating: 255, count: n * n)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        pixels.withUnsafeMutableBytes { buffer in context.render(matrix, toBitmap: buffer.baseAddress!, rowBytes: n, bounds: matrix.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()) }
        let side = (n + quiet * 2) * cell
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw QRContent.fail("Não foi possível preparar a imagem.") }
        NSGraphicsContext.saveGraphicsState()
        graphics.cgContext.translateBy(x: 0, y: CGFloat(side)); graphics.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        background.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
        ink.setFill()
        let style = s.string("qrStyle", "square")
        for y in 0..<n { for x in 0..<n where pixels[y * n + x] < 128 {
            let rect = NSRect(x: (x + quiet) * cell, y: (y + quiet) * cell, width: cell, height: cell)
            // Keep finder/timing structures square. Only soften data modules.
            let reserved = (x < 10 && y < 10) || (x >= n - 10 && y < 10) || (x < 10 && y >= n - 10) || x <= 7 || y <= 7
            if style == "round" && !reserved { NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill() }
            else if style == "dots" && !reserved { NSBezierPath(ovalIn: rect.insetBy(dx: 0.2, dy: 0.2)).fill() }
            else { NSBezierPath(rect: rect).fill() }
        } }
        if let data = Data(base64Encoded: s.string("qrLogo")), !data.isEmpty {
            let safe = try logo(data)
            guard let image = NSImage(data: safe) else { throw QRContent.fail("Não foi possível ler o logo.") }
            let size = CGFloat(n * cell) * 0.15, box = NSRect(x: (CGFloat(side) - size) / 2, y: (CGFloat(side) - size) / 2, width: size, height: size)
            background.setFill(); NSBezierPath(roundedRect: box.insetBy(dx: -5, dy: -5), xRadius: 6, yRadius: 6).fill()
            let factor = min(box.width / image.size.width, box.height / image.size.height)
            let fitted = NSRect(x: box.midX - image.size.width * factor / 2, y: box.midY - image.size.height * factor / 2, width: image.size.width * factor, height: image.size.height * factor)
            image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        guard let cg = bitmap.cgImage, let png = bitmap.representation(using: .png, properties: [:]) else { throw QRContent.fail("Não foi possível gerar o QR Code.") }
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        guard request.results?.contains(where: { $0.payloadStringValue == payload }) == true else { throw QRContent.fail("Este visual prejudicou a leitura. Remova o logo ou escolha o estilo Clássico e tente novamente.") }
        return QRArtwork(png: png, payload: payload)
    }
}
