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
        .init(id: 0, name: "YouTube Clean", background: 0x171D25, accent: 0xFFC43D, ink: 0xFFFFFF, radius: 12, layout: 0),
        .init(id: 7, name: "Vidro", background: 0x17434E, accent: 0x58DCEA, ink: 0xFFFFFF, radius: 18, layout: 1),
        .init(id: 3, name: "Neon", background: 0x101525, accent: 0xD939FF, ink: 0xFFFFFF, radius: 0, layout: 2),
        .init(id: 6, name: "Claro", background: 0xF7F8FC, accent: 0xFFE56A, ink: 0x182035, radius: 18, layout: 3),
        .init(id: 2, name: "Balões", background: 0x252D3A, accent: 0xFF666C, ink: 0xFFFFFF, radius: 28, layout: 4),
        .init(id: 11, name: "Terminal", background: 0x071D29, accent: 0x46F499, ink: 0xDDF5FF, radius: 4, layout: 5),
        .init(id: 1, name: "Editorial", background: 0xF6F1E8, accent: 0xA14628, ink: 0x252525, radius: 4, layout: 3),
        .init(id: 4, name: "Lavanda", background: 0xF0ECFF, accent: 0x7050B0, ink: 0x30234B, radius: 18, layout: 4),
        .init(id: 5, name: "Esportivo", background: 0x16233B, accent: 0xFFBD42, ink: 0xFFFFFF, radius: 0, layout: 2),
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

struct ChatLayout {
    let width: Int, height: Int
    let bodySize: CGFloat, nameSize: CGFloat, gap: CGFloat
    init(lower: Bool, settings: [String: Any]) {
        func bounded(_ key: String, _ fallback: Double, _ lo: Double, _ hi: Double) -> Double {
            let value = settings.number(key, fallback)
            return value.isFinite ? min(hi, max(lo, value)) : fallback
        }
        width = Int(bounded("layoutWidth", lower ? 1100 : 480, 240, 1920))
        bodySize = bounded("fontSize", 24, 14, 64)
        nameSize = bounded("nameSize", 20, 12, 48)
        gap = bounded("messageGap", 10, 0, 48)
        let minimumHeight = lower ? ceil(146 + nameSize*1.4 + bodySize*1.4) : ceil(40 + nameSize*1.4 + bodySize*1.4)
        height = Int(bounded("layoutHeight", lower ? 420 : 720, max(140, minimumHeight), 2160))
    }
}

/// Event-driven rasterization: variable-size cards on a transparent surface.
/// No browser, avatar requests, per-video-frame layout or remote markup.
@MainActor enum ChatRaster {
    static func render(messages: [ChatMessage], featured: ChatMessage?, page: Int, lower: Bool, settings: [String: Any]) -> NSBitmapImageRep? {
        let layout = ChatLayout(lower: lower, settings: settings)
        let width = layout.width, height = layout.height
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.clear(CGRect(x: 0, y: 0, width: width, height: height))
        cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let style = ChatStyle.selected(settings)
        func color(_ key: String, _ fallback: UInt32) -> NSColor {
            let value = settings.number(key, Double(fallback))
            return chatColor(value.isFinite ? UInt32(min(0xFFFFFF, max(0, value))) : fallback)
        }
        let accent = color("accent", style.accent), background = color("background", style.background), ink = color("ink", style.ink)
        let face = settings.string("font", style.layout == 5 ? "Menlo" : "Helvetica Neue")
        let rawOpacity = settings.number("cardOpacity", style.layout == 1 ? 0.65 : 0.96)
        let opacity = rawOpacity.isFinite ? min(1,max(0.15,rawOpacity)) : 0.96
        func attributes(_ size: CGFloat, _ color: NSColor, bold: Bool = false, single: Bool = false) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = single ? .byTruncatingTail : .byWordWrapping
            paragraph.lineSpacing = 2
            let font = NSFont(name: face, size: size) ?? .systemFont(ofSize: size)
            return [.font: bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font, .foregroundColor: color, .paragraphStyle: paragraph]
        }
        func measure(_ value: String, width: CGFloat, size: CGFloat) -> CGFloat {
            ceil((value as NSString).boundingRect(with: CGSize(width: width, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size, ink)).height) + 2
        }
        func text(_ value: String, _ rect: CGRect, _ size: CGFloat, _ color: NSColor, bold: Bool = false, single: Bool = false) {
            NSAttributedString(string: value, attributes: attributes(size, color, bold: bold, single: single))
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
            let path: NSBezierPath
            if style.layout == 2 {
                let cut: CGFloat = 14
                path = NSBezierPath()
                path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
                for point in [CGPoint(x: rect.maxX-cut,y:rect.minY), CGPoint(x:rect.maxX,y:rect.minY+cut), CGPoint(x:rect.maxX,y:rect.maxY-cut), CGPoint(x:rect.maxX-cut,y:rect.maxY), CGPoint(x:rect.minX+cut,y:rect.maxY), CGPoint(x:rect.minX,y:rect.maxY-cut), CGPoint(x:rect.minX,y:rect.minY+cut)] { path.line(to: point) }; path.close()
            } else { path = NSBezierPath(roundedRect: rect, xRadius: style.radius, yRadius: style.radius) }
            let fill = paid && style.layout != 2 && style.layout != 5 ? accent : background
            fill.withAlphaComponent(opacity).setFill(); path.fill()
            if style.layout == 1 {
                NSGraphicsContext.saveGraphicsState(); path.addClip()
                NSGradient(starting: .white.withAlphaComponent(0.18), ending: .white.withAlphaComponent(0))?.draw(in: rect, angle: 90)
                NSGraphicsContext.restoreGraphicsState()
            }
            let stroke = style.layout == 2 || style.layout == 5 ? accent : (style.layout == 3 ? NSColor.black : NSColor.white).withAlphaComponent(style.layout == 1 ? 0.65 : 0.16)
            if style.layout == 2 {
                NSGraphicsContext.saveGraphicsState()
                let glow=NSShadow();glow.shadowColor=accent.withAlphaComponent(paid ? 0.6 : 0.25);glow.shadowBlurRadius=paid ? 8:4;glow.shadowOffset = .zero;glow.set()
                accent.setStroke();path.lineWidth=paid ? 3:1.5;path.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            stroke.setStroke(); path.lineWidth = style.layout == 2 ? (paid ? 3 : 1.5) : 1; path.stroke()
            if style.layout == 2 {
                let line = NSBezierPath(); line.move(to: CGPoint(x:rect.minX+16,y:rect.minY)); line.line(to:CGPoint(x:rect.minX+min(110,rect.width/3),y:rect.minY))
                accent.setStroke(); line.lineWidth = 4; line.stroke()
            }
            if style.layout == 4 {
                let tail = NSBezierPath(); tail.move(to:CGPoint(x:rect.minX+1,y:rect.minY+25));tail.line(to:CGPoint(x:rect.minX-9,y:rect.minY+34));tail.line(to:CGPoint(x:rect.minX+1,y:rect.minY+43));tail.close()
                fill.withAlphaComponent(opacity).setFill();tail.fill()
            }
        }
        let avatar: CGFloat = 42, padding: CGFloat = 16, outside = style.layout == 4
        let margin: CGFloat = style.layout == 2 ? 8 : 4
        let textX = margin + padding + avatar + 12
        let contentWidth = CGFloat(width) - textX - padding - margin
        let nameHeight = ceil(layout.nameSize * 1.4)
        let badgeHeight: CGFloat = lower ? 26 : 0
        let amountHeight: CGFloat = lower && featured?.paid == true ? 52 : 0
        func cardHeight(_ value: String, lower: Bool) -> CGFloat {
            let bodyHeight = measure(value, width: contentWidth, size: layout.bodySize)
            return max(avatar + padding*2, padding*2 + badgeHeight + nameHeight + 4 + amountHeight + (lower ? bodyHeight : min(bodyHeight, layout.bodySize*5.9)))
        }
        func draw(_ message: ChatMessage, value: String, y: CGFloat, cardHeight: CGFloat, featured: Bool) {
            let paid = featured && message.paid
            let rect = CGRect(x: outside ? textX-10 : margin, y:y, width:CGFloat(width)-(outside ? textX-10 : margin)-margin, height:cardHeight)
            panel(rect, paid:paid)
            let personColor = authorColor(message)
            let avatarRect = CGRect(x:margin + (outside ? 2 : padding),y:y+padding+badgeHeight,width:avatar,height:avatar)
            (style.layout == 5 ? background : personColor).setFill(); NSBezierPath(ovalIn:avatarRect).fill()
            if style.layout == 5 { personColor.setStroke();let circle=NSBezierPath(ovalIn:avatarRect);circle.lineWidth=2;circle.stroke() }
            let initial = String(message.author.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"@",with:"").prefix(1)).uppercased()
            text(initial, CGRect(x:avatarRect.minX+10,y:avatarRect.minY+5,width:30,height:34), 26, style.layout == 5 ? personColor : .white, bold:true)
            let paidInk: NSColor
            let rgb=accent.usingColorSpace(.sRGB) ?? accent
            let brightness=0.2126*rgb.redComponent+0.7152*rgb.greenComponent+0.0722*rgb.blueComponent
            paidInk = paid && style.layout != 2 && style.layout != 5 ? (brightness > 0.55 ? chatColor(0x101520) : .white) : ink
            if featured { text(paid ? "♥  SUPER CHAT" : "COMENTÁRIO EM DESTAQUE",CGRect(x:textX,y:y+padding,width:contentWidth,height:24),14,paid ? paidInk : accent,bold:true,single:true) }
            let nameY=y+padding+badgeHeight
            text((style.layout == 5 ? "> " : "") + message.author, CGRect(x:textX,y:nameY,width:contentWidth,height:nameHeight),layout.nameSize,paid ? paidInk : personColor,bold:true,single:true)
            var bodyY=nameY+nameHeight+4
            if paid { text(message.amount,CGRect(x:textX,y:bodyY,width:contentWidth,height:amountHeight),38,style.layout == 2 || style.layout == 5 ? accent : paidInk,bold:true,single:true);bodyY += amountHeight }
            let bodyBox=CGRect(x:textX,y:bodyY,width:contentWidth,height:max(1,y+cardHeight-padding-bodyY))
            text(value,bodyBox,layout.bodySize,paidInk)
        }
        if lower, let featured {
            let pages = pages(for: featured, settings: settings)
            let index = min(max(0,page),pages.count-1)
            let content=pages[index]
            let footer: CGFloat = pages.count > 1 ? 24 : 0
            let h=min(CGFloat(height)-margin*2-footer,cardHeight(content,lower:true))
            draw(featured,value:content,y:margin,cardHeight:h,featured:true)
            if footer > 0 { text("\(index+1) / \(pages.count)",CGRect(x:margin+12,y:margin+h+3,width:CGFloat(width)-24,height:21),13,accent,single:true) }
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
        let face=settings.string("font",style.layout == 5 ? "Menlo" : "Helvetica Neue")
        let font=NSFont(name:face,size:layout.bodySize) ?? .systemFont(ofSize:layout.bodySize)
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping;paragraph.lineSpacing=2
        let width=CGFloat(layout.width)-(style.layout == 2 ? 102 : 94)
        let height=max(layout.bodySize*1.4,CGFloat(layout.height)-8-32-26-ceil(layout.nameSize*1.4)-4-(message.paid ? 52 : 0)-24)
        let attrs: [NSAttributedString.Key:Any]=[.font:font,.paragraphStyle:paragraph]
        var remaining=Array(message.text.isEmpty ? "Obrigado pelo apoio!" : message.text), result:[String]=[]
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
        activity.configure(subscribers:alerts.contains{$0.flag("showSubscribers",true)},likes:alerts.contains{$0.flag("showLikes",true)})
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
                let signature=(event?.id ?? "idle") + ":" + (total.map(String.init) ?? "") + ":" + jsonString(settings)
                guard signatures[name] != signature else{continue};signatures[name]=signature
                if let bitmap=YouTubeActivityRaster.render(event:event,total:total,settings:settings),let bytes=bitmap.bitmapData {
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
        _ = engine // All bridge operations above are main-actor serialized.
    }
}
