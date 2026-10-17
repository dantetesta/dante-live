import AppKit

struct ChatStyle: Identifiable {
    let id: Int
    let name: String
    let background: UInt32
    let accent: UInt32
    let ink: UInt32
    let radius: CGFloat
    let layout: Int
    static let all: [ChatStyle] = [
        .init(id: 0, name: "Estúdio", background: 0x14212C, accent: 0x55C6D5, ink: 0xFFFFFF, radius: 20, layout: 0),
        .init(id: 1, name: "Editorial", background: 0xF6F1E8, accent: 0xA14628, ink: 0x252525, radius: 2, layout: 1),
        .init(id: 2, name: "Rosa suave", background: 0xFFF1F5, accent: 0xAE396C, ink: 0x442136, radius: 36, layout: 2),
        .init(id: 3, name: "Neon", background: 0x111222, accent: 0x9AF36A, ink: 0xFFFFFF, radius: 6, layout: 3),
        .init(id: 4, name: "Lavanda", background: 0xF0ECFF, accent: 0x7050B0, ink: 0x30234B, radius: 28, layout: 0),
        .init(id: 5, name: "Esportivo", background: 0x16233B, accent: 0xFFBD42, ink: 0xFFFFFF, radius: 0, layout: 1),
        .init(id: 6, name: "Minimal", background: 0xFFFFFF, accent: 0x444444, ink: 0x202020, radius: 10, layout: 3),
        .init(id: 7, name: "Oceano", background: 0xE5F7F6, accent: 0x087C87, ink: 0x123A40, radius: 30, layout: 2),
        .init(id: 8, name: "Cinema", background: 0x161616, accent: 0xD9B979, ink: 0xF6EEDC, radius: 2, layout: 0),
        .init(id: 9, name: "Pêssego", background: 0xFFF0E3, accent: 0xB5502D, ink: 0x4B3029, radius: 32, layout: 1),
        .init(id: 10, name: "Pop", background: 0xFFED67, accent: 0x7A2DAD, ink: 0x281E35, radius: 14, layout: 2),
        .init(id: 11, name: "Grafite", background: 0x282D35, accent: 0xA5BED0, ink: 0xFFFFFF, radius: 8, layout: 3)
    ]
    static func selected(_ settings: [String: Any]) -> ChatStyle {
        all[Int(min(Double(all.count - 1), max(0, settings.number("style"))))]
    }
}
func chatColor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

/// Event-driven rasterization into memory. No web renderer, avatar fetch, file,
/// per-video-frame SwiftUI layout, or remote markup evaluation.
@MainActor enum ChatRaster {
    static func render(messages: [ChatMessage], featured: ChatMessage?, page: Int, lower: Bool, settings: [String: Any]) -> NSBitmapImageRep? {
        let width = lower ? 1100 : 480, height = lower ? 420 : 720
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let cg = context.cgContext; cg.clear(CGRect(x: 0, y: 0, width: width, height: height))
        cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let style = ChatStyle.selected(settings)
        let accent = chatColor(UInt32(min(0xFFFFFF, max(0, settings.number("accent", Double(style.accent))))))
        let background = chatColor(UInt32(min(0xFFFFFF, max(0, settings.number("background", Double(style.background))))))
        let ink = chatColor(UInt32(min(0xFFFFFF, max(0, settings.number("ink", Double(style.ink))))))
        let face = settings.string("font", "Helvetica Neue")
        let bodySize = CGFloat(min(36, max(20, settings.number("fontSize", 30))))
        func text(_ value: String, rect: CGRect, size: CGFloat, color: NSColor, bold: Bool = false) {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 3
            let font = NSFont(name: face, size: size) ?? .systemFont(ofSize: size)
            let weight = bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
            NSAttributedString(string: value, attributes: [.font: weight, .foregroundColor: color, .paragraphStyle: paragraph])
                .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        func card(_ rect: CGRect) {
            background.setFill(); NSBezierPath(roundedRect: rect, xRadius: style.radius, yRadius: style.radius).fill()
            accent.setFill()
            if style.layout == 0 { NSBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY + 20, width: 6, height: rect.height - 40), xRadius: 3, yRadius: 3).fill() }
            if style.layout == 1 { NSBezierPath(rect: CGRect(x: rect.minX + 24, y: rect.minY + 67, width: rect.width - 48, height: 3)).fill() }
            if style.layout == 2 { NSBezierPath(ovalIn: CGRect(x: rect.maxX - 65, y: rect.minY + 20, width: 36, height: 36)).fill() }
            if style.layout == 3 { let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: style.radius, yRadius: style.radius); accent.setStroke(); path.lineWidth = 3; path.stroke() }
        }
        if lower, let featured {
            let rect = CGRect(x: 8, y: 8, width: 1084, height: 404); card(rect)
            let badge = featured.paid ? "SUPER CHAT  •  \(featured.amount)" : "COMENTÁRIO DO YOUTUBE"
            text(badge, rect: CGRect(x: 36, y: 24, width: 950, height: 28), size: 18, color: accent, bold: true)
            text(featured.author, rect: CGRect(x: 36, y: 84, width: 1000, height: 44), size: 30, color: ink, bold: true)
            let content = featured.pages[min(page, featured.pages.count - 1)]
            // Fit the entire page, reducing size only when it needs more lines.
            let box = CGRect(x: 36, y: 142, width: 1012, height: 210)
            var size = bodySize
            while size > 16 {
                let font = NSFont(name: face, size: size) ?? .systemFont(ofSize: size)
                let measure = (content as NSString).boundingRect(with: CGSize(width: box.width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
                if measure.height + 35 <= box.height { break }; size -= 1
            }
            text(content, rect: box, size: size, color: ink)
            if featured.pages.count > 1 { text("\(page + 1) / \(featured.pages.count)", rect: CGRect(x: 960, y: 376, width: 90, height: 24), size: 16, color: accent) }
        } else if !lower {
            card(CGRect(x: 4, y: 4, width: 472, height: 712))
            text("CHAT AO VIVO", rect: CGRect(x: 24, y: 23, width: 360, height: 34), size: 22, color: accent, bold: true)
            for (index, message) in messages.suffix(4).enumerated() {
                let y = CGFloat(88 + index * 152)
                text(message.author, rect: CGRect(x: 24, y: y, width: 428, height: 27), size: 18, color: accent, bold: true)
                let value = message.text.count > 130 ? String(message.text.prefix(130)) + "…" : message.text
                text(value, rect: CGRect(x: 24, y: y + 33, width: 428, height: 110), size: min(24, bodySize), color: ink)
            }
        }
        NSGraphicsContext.restoreGraphicsState(); return bitmap
    }
}

@MainActor final class ChatOverlayRenderer {
    private var signatures: [String: String] = [:]
    func invalidate() { signatures.removeAll() }
    func update(studio: StudioModel) {
        guard let engine = studio.engine else { return }
        let chat = studio.youtube.chat
        let sources = studio.scenes.flatMap { $0.array("items") }.filter { $0.string("type").hasPrefix("dante_") && ["dante_youtube_chat", "dante_superchat"].contains($0.string("type")) }
        let names = Set(sources.map { $0.string("name") })
        for name in signatures.keys where !names.contains(name) { _ = dante_chat_frame(name, nil, 0, 0, 0, false) }
        signatures = signatures.filter { names.contains($0.key) }
        for name in names {
            guard let item = sources.first(where: { $0.string("name") == name }) else { continue }
            let lower = item.string("type") == "dante_superchat"
            let settings = studio.properties(name: name).object("settings")
            let contentKey = lower ? "\(chat.featured?.id ?? ""):\(chat.page)" : "\(chat.revision)"
            let signature = contentKey + ":" + jsonString(settings)
            guard signatures[name] != signature else { continue }
            signatures[name] = signature
            if (lower && chat.featured == nil) || (!lower && !chat.running && chat.messages.isEmpty) {
                _ = dante_chat_frame(name, nil, 0, 0, 0, false); continue
            }
            guard let bitmap = ChatRaster.render(messages: chat.messages, featured: chat.featured, page: chat.page, lower: lower, settings: settings), let bytes = bitmap.bitmapData else { continue }
            _ = dante_chat_frame(name, bytes, UInt32(bitmap.pixelsWide), UInt32(bitmap.pixelsHigh), UInt32(bitmap.bytesPerRow), lower)
        }
        _ = engine // All bridge operations above are main-actor serialized.
    }
}
