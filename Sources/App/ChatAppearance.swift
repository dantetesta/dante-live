import AppKit

struct ChatStyle: Identifiable {
    let id: Int
    let name: String
    let background: UInt32
    let accent: UInt32
    let ink: UInt32
    let radius: CGFloat
    /// 0 clean, 1 glass, 2 neon, 3 light, 4 bubbles, 5 terminal.
    let layout: Int
    // Stable IDs preserve existing project choices. First six follow the visual reference.
    static let all: [ChatStyle] = [
        .init(id: 0, name: "YouTube Clean", background: 0x171D25, accent: 0xF4BD58, ink: 0xF8FAFC, radius: 16, layout: 0),
        .init(id: 7, name: "Vidro", background: 0x19303B, accent: 0x6AD4DE, ink: 0xF8FBFC, radius: 18, layout: 1),
        .init(id: 3, name: "Neon", background: 0x1A1725, accent: 0xD788DA, ink: 0xFAF7FC, radius: 16, layout: 2),
        .init(id: 6, name: "Claro", background: 0xF7F8FC, accent: 0xFFE56A, ink: 0x182035, radius: 18, layout: 3),
        .init(id: 2, name: "Balões", background: 0x252D3A, accent: 0xFF666C, ink: 0xFFFFFF, radius: 28, layout: 4),
        .init(id: 11, name: "Terminal", background: 0x071D29, accent: 0x46F499, ink: 0xDDF5FF, radius: 4, layout: 5),
        .init(id: 1, name: "Editorial", background: 0xF6F1E8, accent: 0xA14628, ink: 0x252525, radius: 4, layout: 3),
        .init(id: 4, name: "Lavanda", background: 0xF0ECFF, accent: 0x7050B0, ink: 0x30234B, radius: 18, layout: 4),
        .init(id: 5, name: "Esportivo", background: 0x1C2836, accent: 0xE7AD6D, ink: 0xF7FAFD, radius: 12, layout: 2),
        .init(id: 8, name: "Cinema", background: 0x161616, accent: 0xD9B979, ink: 0xF6EEDC, radius: 8, layout: 0),
        .init(id: 9, name: "Pêssego", background: 0xFFF0E3, accent: 0xB5502D, ink: 0x4B3029, radius: 18, layout: 3),
        .init(id: 10, name: "Pop", background: 0xFFED67, accent: 0x7A2DAD, ink: 0x281E35, radius: 24, layout: 4)
    ]
    static func selected(_ settings: [String: Any]) -> ChatStyle {
        all.first { Double($0.id) == settings.number("style") } ?? all[0]
    }
}
func chatColor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

@MainActor enum ChatFontCatalog {
    static func availableFamilies() -> [String] {
        Array(Set(NSFontManager.shared.availableFontFamilies)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func isInstalled(_ name: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(name) || NSFont(name: name, size: 12) != nil
    }

    static func font(named name: String, size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? NSFont(name: name, size: size)
            ?? .systemFont(ofSize: size)
    }

    static func styledFont(named name: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let base = font(named: name, size: size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return traits.isEmpty ? base : NSFontManager.shared.convert(base, toHaveTrait: traits)
    }
}

struct ChatLayout {
    let width: Int, height: Int
    let bodySize: CGFloat, nameSize: CGFloat, badgeSize: CGFloat, amountSize: CGFloat, gap: CGFloat
    init(lower: Bool, settings: [String: Any]) {
        func bounded(_ key: String, _ fallback: Double, _ lo: Double, _ hi: Double) -> Double {
            let value = settings.number(key, fallback)
            return value.isFinite ? min(hi, max(lo, value)) : fallback
        }
        width = Int(bounded("layoutWidth", lower ? 1100 : 480, 240, 3840))
        bodySize = bounded("fontSize", lower ? 22 : 24, 14, 64)
        nameSize = bounded("nameSize", lower ? 26 : 20, 12, 48)
        badgeSize = bounded("badgeSize", 14, 10, 32)
        amountSize = bounded("amountSize", 38, 18, 72)
        gap = bounded("messageGap", 10, 0, 48)
        let authorHeight = max(Self.avatarSize(settings), ceil(nameSize*1.4))
        let minimumHeight = lower ? 140 : ceil(44 + authorHeight + bodySize * 1.4)
        height = Int(bounded("layoutHeight", lower ? 420 : 720, max(140, minimumHeight), 2160))
    }
    static func avatarSize(_ settings: [String: Any]) -> CGFloat {
        let requested = settings.number("avatarSize", 64)
        return CGFloat(requested.isFinite ? min(144, max(24, requested)) : 64)
    }
}

/// Layout dimensions control line wrapping; componentScale changes the physical
/// raster size without stretching a previously rendered texture.
enum OverlayComponentScale {
    static func effective(settings: [String: Any], width: Int, height: Int) -> CGFloat {
        let requested = settings.number("componentScale", 1)
        let bounded = requested.isFinite ? min(2, max(0.5, requested)) : 1
        return CGFloat(min(bounded, 3840 / Double(max(1, width)), 2160 / Double(max(1, height))))
    }
    static func pixels(_ size: Int, scale: CGFloat) -> Int {
        Int((CGFloat(size) * scale).rounded())
    }
}

/// Event-driven rasterization: variable-size cards on a transparent surface.
/// No browser, avatar requests, per-video-frame layout or remote markup.
@MainActor enum ChatRaster {
    static func render(messages: [ChatMessage], featured: ChatMessage?, page: Int, lower: Bool, settings: [String: Any]) -> NSBitmapImageRep? {
        let layout = ChatLayout(lower: lower, settings: settings)
        let width = layout.width, height = layout.height
        let scale = OverlayComponentScale.effective(settings: settings, width: width, height: height)
        let pixelsWide = OverlayComponentScale.pixels(width, scale: scale)
        let pixelsHigh = OverlayComponentScale.pixels(height, scale: scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: pixelsWide * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        cg.translateBy(x: 0, y: CGFloat(pixelsHigh)); cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let style = ChatStyle.selected(settings)
        func color(_ key: String, _ fallback: UInt32) -> NSColor {
            let value = settings.number(key, Double(fallback))
            return chatColor(value.isFinite ? UInt32(min(0xFFFFFF, max(0, value))) : fallback)
        }
        let accent = color("accent", style.accent), background = color("background", style.background), ink = color("ink", style.ink)
        let legacyFace = settings.string("font", style.layout == 5 ? "Menlo" : "Helvetica Neue")
        func face(_ role: String) -> String { settings.string(role + "Font", legacyFace) }
        let rawOpacity = settings.number("cardOpacity", style.layout == 1 ? 0.65 : 0.96)
        let opacity = rawOpacity.isFinite ? min(1,max(0.15,rawOpacity)) : 0.96
        func attributes(_ size: CGFloat, _ color: NSColor, role: String, defaultBold: Bool = false, single: Bool = false) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = single ? .byTruncatingTail : .byWordWrapping
            paragraph.lineSpacing = 2
            let font = ChatFontCatalog.styledFont(named: face(role), size: size,
                bold: settings.flag(role + "Bold", defaultBold), italic: settings.flag(role + "Italic"))
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if settings.flag(role + "Underline") { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            return attrs
        }
        func measure(_ value: String, width: CGFloat, size: CGFloat) -> CGFloat {
            ceil((value as NSString).boundingRect(with: CGSize(width: width, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size, ink, role: "body")).height) + 2
        }
        func text(_ value: String, _ rect: CGRect, _ size: CGFloat, _ color: NSColor, role: String, defaultBold: Bool = false, single: Bool = false) {
            NSAttributedString(string: value, attributes: attributes(size, color, role: role, defaultBold: defaultBold, single: single))
                .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }
        func authorColor(_ message: ChatMessage) -> NSColor {
            let key = message.channelID.isEmpty ? message.author : message.channelID
            let hash = key.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            let bg=background.usingColorSpace(.sRGB) ?? background
            let light=0.2126*bg.redComponent+0.7152*bg.greenComponent+0.0722*bg.blueComponent > 0.6
            let colors: [UInt32] = light ? [0xB62E63,0x2056CE,0x08764B,0x7843B3,0x8A4D09,0x005D78] : [0xFF729E,0x68A6FF,0x56DBA0,0xD499FF,0xFFD171,0x59DDE3]
            return chatColor(colors[Int((hash ^ (hash >> 32)) % UInt64(colors.count))])
        }
        func panel(_ rect: CGRect, paid: Bool) {
            let path = NSBezierPath(roundedRect: rect, xRadius: style.radius, yRadius: style.radius)
            let fill = paid && style.layout != 2 && style.layout != 5 ? accent : background
            fill.withAlphaComponent(opacity).setFill(); path.fill()
            if style.layout == 1 {
                NSGraphicsContext.saveGraphicsState(); path.addClip()
                NSGradient(starting: .white.withAlphaComponent(0.18), ending: .white.withAlphaComponent(0))?.draw(in: rect, angle: 90)
                NSGraphicsContext.restoreGraphicsState()
            }
            let stroke = style.layout == 2 || style.layout == 5 ? accent.withAlphaComponent(0.48) :
                (style.layout == 3 ? NSColor.black : NSColor.white).withAlphaComponent(style.layout == 1 ? 0.42 : 0.18)
            stroke.setStroke(); path.lineWidth = 1; path.stroke()
            if style.layout == 4 {
                let tail = NSBezierPath(); tail.move(to:CGPoint(x:rect.minX+1,y:rect.minY+25));tail.line(to:CGPoint(x:rect.minX-9,y:rect.minY+34));tail.line(to:CGPoint(x:rect.minX+1,y:rect.minY+43));tail.close()
                fill.withAlphaComponent(opacity).setFill();tail.fill()
            }
        }
        let avatar = ChatLayout.avatarSize(settings), padding: CGFloat = 16, outside = style.layout == 4
        let margin: CGFloat = 4
        let textX = margin + padding + avatar + 12
        let contentWidth = CGFloat(width) - textX - padding - margin
        let nameHeight = ceil(layout.nameSize * 1.4)
        let authorHeight = max(avatar, nameHeight)
        let badgeHeight: CGFloat = lower ? max(26,layout.badgeSize*1.6) : 0
        let amountHeight: CGFloat = lower && featured?.paid == true ? max(52,layout.amountSize*1.4) : 0
        func cardHeight(_ value: String, lower: Bool) -> CGFloat {
            if lower {
                let featuredPadding: CGFloat = width < 500 ? 14 : 22
                let featuredAvatar = min(avatar, max(36, min(72, CGFloat(height) * 0.24)))
                let featuredBadge = min(layout.badgeSize, CGFloat(height) * 0.11)
                let featuredAmount = featured?.paid == true ? min(layout.amountSize, CGFloat(height) * 0.19) : 0
                let header = max(featuredAvatar, featuredBadge * 1.4 + max(layout.nameSize * 1.4, featuredAmount * 1.4) + 4)
                let body = measure(value, width: CGFloat(width) - margin * 2 - featuredPadding * 2 - 7, size: layout.bodySize)
                return featuredPadding * 2 + header + 12 + body
            }
            let bodyHeight = measure(value, width: contentWidth, size: layout.bodySize)
            return padding*2 + badgeHeight + authorHeight + 4 + amountHeight + (lower ? bodyHeight : min(bodyHeight, layout.bodySize*5.9))
        }
        func drawFeatured(_ message: ChatMessage, value: String, y: CGFloat, cardHeight: CGFloat) {
            let rect = CGRect(x: margin, y: y, width: CGFloat(width) - margin * 2, height: cardHeight)
            panel(rect, paid: false)
            let inset: CGFloat = width < 500 ? 14 : 22
            let left = rect.minX + inset + 7
            accent.setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.minX + 8, y: rect.minY + 12,
                                             width: 5, height: max(1, rect.height - 24)), xRadius: 2.5, yRadius: 2.5).fill()
            let avatarSize = min(avatar, max(36, min(72, CGFloat(height) * 0.24)))
            let avatarRect = CGRect(x: left, y: rect.minY + inset, width: avatarSize, height: avatarSize)
            let personColor = authorColor(message)
            personColor.withAlphaComponent(0.22).setFill(); NSBezierPath(ovalIn: avatarRect).fill()
            personColor.setStroke(); let ring = NSBezierPath(ovalIn: avatarRect.insetBy(dx: 0.7, dy: 0.7)); ring.lineWidth = 1.4; ring.stroke()
            let initial = String(message.author.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "@", with: "").prefix(1)).uppercased()
            let initialStyle = NSMutableParagraphStyle(); initialStyle.alignment = .center
            NSAttributedString(string: initial, attributes: [.font: NSFont.systemFont(ofSize: avatarSize * 0.48, weight: .bold),
                .foregroundColor: personColor, .paragraphStyle: initialStyle])
                .draw(with: avatarRect.insetBy(dx: 1, dy: avatarSize * 0.18), options: [.usesLineFragmentOrigin])

            let badgeSize = min(layout.badgeSize, CGFloat(height) * 0.11)
            var amountSize = message.paid ? min(layout.amountSize, CGFloat(height) * 0.19) : 0
            let rightWidth = min(rect.width * 0.38, max(160, rect.width * 0.28))
            let rightX = rect.maxX - inset - rightWidth
            while amountSize > 16 {
                let font = ChatFontCatalog.styledFont(named: face("amount"), size: amountSize,
                    bold: settings.flag("amountBold", true), italic: settings.flag("amountItalic"))
                if (message.amount as NSString).size(withAttributes: [.font: font]).width <= rightWidth { break }
                amountSize -= 1
            }
            let badgeText = message.paid ? "SUPER CHAT" : "EM DESTAQUE"
            text(badgeText, CGRect(x: rightX, y: rect.minY + inset, width: rightWidth, height: badgeSize * 1.45),
                 badgeSize, accent, role: "badge", defaultBold: true, single: true)
            if message.paid {
                text(message.amount, CGRect(x: rightX, y: rect.minY + inset + badgeSize * 1.45 + 3,
                                              width: rightWidth, height: amountSize * 1.4),
                     amountSize, accent, role: "amount", defaultBold: true, single: true)
            }
            let nameX = avatarRect.maxX + 14
            let nameWidth = max(40, rightX - nameX - 10)
            var nameSize = min(layout.nameSize, CGFloat(height) * 0.24)
            while nameSize > 12 {
                let font = ChatFontCatalog.styledFont(named: face("name"), size: nameSize,
                    bold: settings.flag("nameBold", true), italic: settings.flag("nameItalic"))
                if (message.author as NSString).size(withAttributes: [.font: font]).width <= nameWidth { break }
                nameSize -= 1
            }
            let headerHeight = max(avatarSize, badgeSize * 1.4 + max(nameSize * 1.4, amountSize * 1.4) + 4)
            let nameY = rect.minY + inset + (headerHeight - nameSize * 1.4) / 2
            text(message.author, CGRect(x: nameX, y: nameY, width: nameWidth, height: nameSize * 1.5),
                 nameSize, ink, role: "name", defaultBold: true, single: true)

            let bodyY = rect.minY + inset + headerHeight + 12
            let bodyX = left
            let bodyWidth = rect.maxX - inset - bodyX
            let bodyHeight = max(1, rect.maxY - inset - bodyY)
            text(value, CGRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight),
                 layout.bodySize, ink, role: "body")
        }
        func draw(_ message: ChatMessage, value: String, y: CGFloat, cardHeight: CGFloat, featured: Bool) {
            let paid = featured && message.paid
            let rect = CGRect(x: outside ? textX-10 : margin, y:y, width:CGFloat(width)-(outside ? textX-10 : margin)-margin, height:cardHeight)
            panel(rect, paid:paid)
            let personColor = authorColor(message)
            let authorY = y + padding + badgeHeight
            let avatarRect = CGRect(x:margin + (outside ? 2 : padding),y:authorY + (authorHeight-avatar)/2,width:avatar,height:avatar)
            (style.layout == 5 ? background : personColor).setFill(); NSBezierPath(ovalIn:avatarRect).fill()
            if style.layout == 5 { personColor.setStroke();let circle=NSBezierPath(ovalIn:avatarRect);circle.lineWidth=2;circle.stroke() }
            let initial = String(message.author.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"@",with:"").prefix(1)).uppercased()
            let initialSize = avatar * 0.56
            let initialStyle = NSMutableParagraphStyle(); initialStyle.alignment = .center
            NSAttributedString(string:initial, attributes:[.font:NSFont.systemFont(ofSize:initialSize,weight:.bold),
                .foregroundColor:style.layout == 5 ? personColor : NSColor.white,.paragraphStyle:initialStyle])
                .draw(with:CGRect(x:avatarRect.minX,y:avatarRect.minY+(avatar-initialSize*1.25)/2,width:avatar,height:initialSize*1.25),
                      options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine])
            let paidInk: NSColor
            let rgb=accent.usingColorSpace(.sRGB) ?? accent
            let brightness=0.2126*rgb.redComponent+0.7152*rgb.greenComponent+0.0722*rgb.blueComponent
            paidInk = paid && style.layout != 2 && style.layout != 5 ? (brightness > 0.55 ? chatColor(0x101520) : .white) : ink
            if featured { text(paid ? "♥  SUPER CHAT" : "COMENTÁRIO EM DESTAQUE",CGRect(x:textX,y:y+padding,width:contentWidth,height:badgeHeight),layout.badgeSize,paid ? paidInk : accent,role:"badge",defaultBold:true,single:true) }
            let nameY=authorY+(authorHeight-nameHeight)/2
            text((style.layout == 5 ? "> " : "") + message.author, CGRect(x:textX,y:nameY,width:contentWidth,height:nameHeight),layout.nameSize,paid ? paidInk : personColor,role:"name",defaultBold:true,single:true)
            var bodyY=authorY+authorHeight+4
            if paid { text(message.amount,CGRect(x:textX,y:bodyY,width:contentWidth,height:amountHeight),layout.amountSize,style.layout == 2 || style.layout == 5 ? accent : paidInk,role:"amount",defaultBold:true,single:true);bodyY += amountHeight }
            let bodyBox=CGRect(x:textX,y:bodyY,width:contentWidth,height:max(1,y+cardHeight-padding-bodyY))
            text(value,bodyBox,layout.bodySize,paidInk,role:"body")
        }
        if lower, let featured {
            let pages = pages(for: featured, settings: settings)
            let index = min(max(0,page),pages.count-1)
            let content=pages[index]
            let footer: CGFloat = pages.count > 1 ? 24 : 0
            let h=min(CGFloat(height)-margin*2-footer,cardHeight(content,lower:true))
            drawFeatured(featured,value:content,y:margin,cardHeight:h)
            if footer > 0 { text("\(index+1) / \(pages.count)",CGRect(x:margin+12,y:margin+h+3,width:CGFloat(width)-24,height:21),13,accent,role:"badge",single:true) }
        } else if !lower {
            // Keep the newest whole cards that fit, oldest-to-newest. No fixed slots.
            var visible: [(ChatMessage,String,CGFloat)] = [], occupied: CGFloat = 0
            for message in messages.suffix(100).reversed() {
                let value=message.text.isEmpty ? "…" : message.text
                let h=min(CGFloat(height)-margin*2,cardHeight(value,lower:false))
                let next=occupied+(visible.isEmpty ? 0 : layout.gap)+h
                if next > CGFloat(height)-margin*2 { break }
                visible.append((message,value,h));occupied=next
            }
            var y=margin
            for (message,value,h) in visible.reversed() { draw(message,value:value,y:y,cardHeight:h,featured:false);y += h+layout.gap }
        }
        return bitmap
    }

    /// Reflow the entire featured text into pages for the current box and fonts.
    /// Never drop a suffix when a narrow/short frame cannot fit the old 380-char page.
    static func pages(for message: ChatMessage, settings: [String: Any]) -> [String] {
        let layout=ChatLayout(lower:true,settings:settings), style=ChatStyle.selected(settings)
        let face=settings.string("bodyFont",settings.string("font",style.layout == 5 ? "Menlo" : "Helvetica Neue"))
        let font=ChatFontCatalog.styledFont(named:face,size:layout.bodySize,bold:settings.flag("bodyBold"),italic:settings.flag("bodyItalic"))
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping;paragraph.lineSpacing=2
        let avatar=ChatLayout.avatarSize(settings)
        let margin: CGFloat = 4
        let inset: CGFloat = layout.width < 500 ? 14 : 22
        let width = CGFloat(layout.width) - margin * 2 - inset * 2 - 7
        let featuredAvatar = min(avatar, max(36, min(72, CGFloat(layout.height) * 0.24)))
        let badge = min(layout.badgeSize, CGFloat(layout.height) * 0.11)
        let amount = message.paid ? min(layout.amountSize, CGFloat(layout.height) * 0.19) : 0
        let header = max(featuredAvatar, badge * 1.4 + max(layout.nameSize * 1.4, amount * 1.4) + 4)
        let fullHeight = max(layout.bodySize * 1.4, CGFloat(layout.height) - margin * 2 - inset * 2 - header - 12)
        let attrs: [NSAttributedString.Key:Any]=[.font:font,.paragraphStyle:paragraph]
        let fullText = message.text.isEmpty ? "Obrigado pelo apoio!" : message.text
        let fullMeasure = (fullText as NSString).boundingRect(with:CGSize(width:width,height:100000),
            options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs).height
        if fullMeasure <= fullHeight { return [fullText] }
        let height = max(layout.bodySize * 1.4, fullHeight - 24)
        var remaining=Array(fullText), result:[String]=[]
        while !remaining.isEmpty {
            var low=1, high=min(remaining.count,1000), count=1
            while low <= high {
                let middle=(low+high)/2
                let measured=(String(remaining.prefix(middle)) as NSString).boundingRect(with:CGSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs).height
                if measured <= height { count=middle;low=middle+1 } else { high=middle-1 }
            }
            if count < remaining.count, let space=remaining[..<count].lastIndex(where:{$0.isWhitespace}), space > count/2 { count=space+1 }
            result.append(String(remaining.prefix(count)));remaining.removeFirst(count)
        }
        return result.isEmpty ? [""] : result
    }
}

@MainActor final class ChatOverlayRenderer {
    private var signatures: [String: String] = [:]
    func invalidate() { signatures.removeAll() }
    func update(studio: StudioModel) {
        guard let engine = studio.engine else { return }
        let chat = studio.youtube.chat
        let sources = studio.scenes.flatMap { $0.array("items") }.filter { $0.string("type").hasPrefix("dante_") && ["dante_youtube_chat", "dante_superchat", "dante_youtube_alert"].contains($0.string("type")) }
        let alerts = sources.filter { $0.string("type") == "dante_youtube_alert" }.map { studio.properties(name:$0.string("name")).object("settings") }
        let activity=studio.youtube.activity
        activity.configure(
            subscribers: alerts.contains { $0.flag("showSubscribers", true) || $0.flag("showNewSubscribers", false) },
            likes: alerts.contains { $0.flag("showLikes", true) },
            subscriberAlerts: alerts.contains { $0.flag("showSubscribers", true) },
            channelTotal: alerts.contains { $0.flag("showChannelTotal", false) }
        )
        activity.tick()
        let names = Set(sources.map { $0.string("name") })
        for name in signatures.keys where !names.contains(name) { _ = dante_chat_frame(name, nil, 0, 0, 0, false) }
        signatures = signatures.filter { names.contains($0.key) }
        for name in names {
            guard let item = sources.first(where: { $0.string("name") == name }) else { continue }
            let lower = item.string("type") == "dante_superchat"
            let settings = studio.properties(name: name).object("settings")
            if item.string("type") == "dante_youtube_alert" {
                var event=activity.current
                if let candidate=event, candidate.kind == .subscriber ? !settings.flag("showSubscribers",true) : !settings.flag("showLikes",true) {event=nil}
                let total=settings.flag("showLikes",true) ? activity.totalLikes : nil
                let subscribers=settings.flag("showChannelTotal",false) ? activity.totalSubscribers : nil
                let newPublic=settings.flag("showNewSubscribers",false) ? activity.newPublicSubscribers : nil
                let signature=(event?.id ?? "idle") + ":" + (total.map(String.init) ?? "") + ":" + (subscribers.map(String.init) ?? "") + ":" + (newPublic.map(String.init) ?? "") + ":" + jsonString(settings)
                guard signatures[name] != signature else{continue};signatures[name]=signature
                if let bitmap=YouTubeActivityRaster.render(event:event,total:total,subscriberTotal:subscribers,newPublicSubscribers:newPublic,settings:settings),let bytes=bitmap.bitmapData {
                    _ = dante_chat_frame(name,bytes,UInt32(bitmap.pixelsWide),UInt32(bitmap.pixelsHigh),UInt32(bitmap.bytesPerRow),event != nil)
                } else {_ = dante_chat_frame(name,nil,0,0,0,false)}
                continue
            }
            let contentKey = lower ? "\(chat.featured?.id ?? ""):\(chat.page)" : "\(chat.revision)"
            let signature = contentKey + ":" + jsonString(settings)
            guard signatures[name] != signature else { continue }
            signatures[name] = signature
            if (lower && chat.featured == nil) || (!lower && !chat.running && chat.messages.isEmpty) {
                _ = dante_chat_frame(name, nil, 0, 0, 0, false); continue
            }
            guard let bitmap = ChatRaster.render(messages: chat.messages, featured: chat.featured, page: chat.page, lower: lower, settings: settings), let bytes = bitmap.bitmapData else { continue }
            if !dante_chat_frame(name, bytes, UInt32(bitmap.pixelsWide), UInt32(bitmap.pixelsHigh), UInt32(bitmap.bytesPerRow), lower) { signatures[name] = nil }
        }
        chat.updatePresentation(visible: studio.streaming && sources.contains { $0.string("type") == "dante_superchat" && $0.flag("sourceActive") })
        _ = engine // All bridge operations above are main-actor serialized.
    }
}
