import SwiftUI
import AppKit

struct YouTubeActivityStyle: Identifiable {
    let id: Int
    let name: String
    let accent: UInt32
    let background: UInt32
    let ink: UInt32
    let font: String
    static let all: [Self] = [
        .init(id: 0, name: "Estúdio", accent: 0x57CDDF, background: 0x14212C, ink: 0xFFFFFF, font: "Helvetica Neue"),
        .init(id: 1, name: "Pílula", accent: 0xC1F17B, background: 0x202C23, ink: 0xF7FFF1, font: "Helvetica Neue"),
        .init(id: 2, name: "Neon", accent: 0xFF51CD, background: 0x120D29, ink: 0xFFFFFF, font: "Helvetica Neue"),
        .init(id: 3, name: "Editorial", accent: 0xA54D38, background: 0xF8F0E4, ink: 0x302A29, font: "Georgia"),
        .init(id: 4, name: "Pop", accent: 0x6E26C8, background: 0xFFE75C, ink: 0x231634, font: "Helvetica Neue"),
        .init(id: 5, name: "Terminal", accent: 0x54F5A6, background: 0x061512, ink: 0xE2FFEF, font: "Menlo")
    ]
    static func selected(_ settings: [String: Any]) -> Self {
        all.first { $0.id == Int(settings.number("style")) } ?? all[0]
    }
}

struct YouTubeActivitySettings: View {
    @Binding var settings: [String: Any]
    @ObservedObject var activity: YouTubeActivity
    var changed: () -> Void

    private func enabled(_ key: String, fallback: Bool) -> Binding<Bool> {
        Binding(get: { settings.flag(key, fallback) }, set: { settings[key] = $0; changed() })
    }
    private func value(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { min(range.upperBound, max(range.lowerBound, settings.number(key, fallback))) },
                set: { settings[key] = min(range.upperBound, max(range.lowerBound, $0.rounded())); changed() })
    }
    private func sizeControl(_ title: String, key: String, fallback: Double, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(settings.number(key, fallback))) px").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value(key, fallback: fallback, range: range), in: range).accessibilityLabel(title)
        }
    }
    private var componentScale: Binding<Double> {
        Binding(get: {
            let value = settings.number("componentScale", 1)
            return value.isFinite ? min(2, max(0.5, value)) : 1
        }, set: { settings["componentScale"] = ($0 * 20).rounded() / 20; changed() })
    }
    private func preview(_ style: YouTubeActivityStyle) -> NSImage? {
        guard let sample = YouTubeActivityRaster.render(event: nil, total: 1234, subscriberTotal: 8500,
                                                        newPublicSubscribers: 3,
                                                        settings: ["style": style.id, "layoutWidth": 310, "layoutHeight": 150,
                                                                   "labelSize": 14, "valueSize": 42, "detailSize": 15]) else { return nil }
        let image = NSImage(size: NSSize(width: sample.pixelsWide, height: sample.pixelsHigh))
        image.addRepresentation(sample)
        return image
    }

    var body: some View {
        let selected = YouTubeActivityStyle.selected(settings)
        VStack(alignment: .leading, spacing: 16) {
            Label("Likes e inscrições", systemImage: "hand.thumbsup.fill").font(.headline)
            Toggle("Mostrar contador de likes", isOn: enabled("showLikes", fallback: true))
            Toggle("Avisar novos inscritos públicos", isOn: enabled("showSubscribers", fallback: true))
            Toggle("Mostrar total de inscritos do canal", isOn: enabled("showChannelTotal", fallback: false))
            Toggle("Mostrar novos públicos detectados nesta live", isOn: enabled("showNewSubscribers", fallback: false))
            Text(activity.status).font(.caption).foregroundStyle(.secondary)

            Text("Estilos prontos").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(YouTubeActivityStyle.all) { style in
                    Button {
                        settings["style"] = style.id
                        for key in ["accent", "background", "ink", "font", "labelFont", "valueFont", "detailFont", "labelSize", "valueSize", "detailSize", "labelBold", "labelItalic", "labelUnderline", "valueBold", "valueItalic", "valueUnderline", "detailBold", "detailItalic", "detailUnderline"] { settings[key] = nil }
                        changed()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            if let image = preview(style) {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                            }
                            Text(style.name).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                        }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected.id == style.id ? .teal : .secondary.opacity(0.2), lineWidth: selected.id == style.id ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("Estilo \(style.name)")
                }
            }
            GraphicColorPicker(title: "Destaque", settings: $settings, key: "accent", fallback: Double(selected.accent)) { changed() }
            GraphicColorPicker(title: "Fundo", settings: $settings, key: "background", fallback: Double(selected.background)) { changed() }
            GraphicColorPicker(title: "Texto", settings: $settings, key: "ink", fallback: Double(selected.ink)) { changed() }
            InstalledFontPicker(title: "Fonte do título", selection: Binding(get: { settings.string("labelFont", settings.string("font", selected.font)) }, set: { settings["labelFont"] = $0; changed() }))
            sizeControl("Título", key: "labelSize", fallback: 20, range: 10...26)
            FontStyleControls(title: "título", settings: $settings, prefix: "label", defaultBold: true, changed: changed)
            InstalledFontPicker(title: "Fonte da contagem ou nome", selection: Binding(get: { settings.string("valueFont", settings.string("font", selected.font)) }, set: { settings["valueFont"] = $0; changed() }))
            sizeControl("Contagem ou nome", key: "valueSize", fallback: 68, range: 18...90)
            FontStyleControls(title: "contagem ou nome", settings: $settings, prefix: "value", defaultBold: true, changed: changed)
            InstalledFontPicker(title: "Fonte dos detalhes", selection: Binding(get: { settings.string("detailFont", settings.string("font", selected.font)) }, set: { settings["detailFont"] = $0; changed() }))
            sizeControl("Detalhes", key: "detailSize", fallback: 22, range: 10...32)
            FontStyleControls(title: "detalhes", settings: $settings, prefix: "detail", changed: changed)
            sizeControl("Ícone de like e inscrição", key: "iconSize",
                        fallback: min(70, max(40, settings.number("layoutWidth", 820) * 0.16)), range: 24...120)
            Text("Em cartões menores, o ícone se ajusta ao espaço disponível.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack { Text("Escala geral").font(.subheadline.bold()); Spacer(); Text("\(Int(componentScale.wrappedValue * 100))%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: componentScale, in: 0.5...2, step: 0.05).accessibilityLabel("Escala geral do componente")
            HStack {
                Text("Aumenta cartão, ícone e fontes juntos, com desenho em nova resolução.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("100%") { componentScale.wrappedValue = 1 }.disabled(componentScale.wrappedValue == 1)
            }
            Divider()
            Text("Área do componente").font(.subheadline.bold())
            HStack {
                Text("Largura")
                TextField("Largura", value: value("layoutWidth", fallback: 820, range: 240...1920), format: .number).textFieldStyle(.roundedBorder)
                Text("Altura")
                TextField("Altura", value: value("layoutHeight", fallback: 240, range: 140...2160), format: .number).textFieldStyle(.roundedBorder)
            }
            Text("Largura e altura mudam a área e a quebra de linha. Arraste as alças no canvas para ajustar cada eixo; use Escala geral para aumentar tudo proporcionalmente.").font(.caption).foregroundStyle(.secondary)
            Text("O total de inscritos fornecido pelo YouTube é arredondado. Novos inscritos públicos detectados são uma contagem parcial, pois o YouTube pode atrasar ou limitar a lista. Likes são consultados a cada 15 segundos; os dados de inscritos, a cada 30 segundos.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor enum YouTubeActivityRaster {
    static func render(event: YouTubeActivityEvent?, total: UInt64?, subscriberTotal: UInt64? = nil,
                       newPublicSubscribers: Int? = nil, settings: [String: Any]) -> NSBitmapImageRep? {
        guard event != nil || total != nil || subscriberTotal != nil || newPublicSubscribers != nil else { return nil }
        let width = Int(min(1920, max(240, settings.number("layoutWidth", 820))))
        let height = Int(min(2160, max(140, settings.number("layoutHeight", 240))))
        let scale = OverlayComponentScale.effective(settings: settings, width: width, height: height)
        let pixelsWide = OverlayComponentScale.pixels(width, scale: scale)
        let pixelsHigh = OverlayComponentScale.pixels(height, scale: scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: pixelsWide * 4,
                                            bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        cg.translateBy(x: 0, y: CGFloat(pixelsHigh)); cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

        let style = YouTubeActivityStyle.selected(settings)
        func paint(_ key: String, _ fallback: UInt32) -> NSColor {
            let raw = settings.number(key, Double(fallback))
            return chatColor(raw.isFinite ? UInt32(min(0xFFFFFF, max(0, raw))) : fallback)
        }
        let accent = paint("accent", style.accent), background = paint("background", style.background), ink = paint("ink", style.ink)
        let legacyFace = settings.string("font", style.font)
        let labelFace = settings.string("labelFont", legacyFace)
        let valueFace = settings.string("valueFont", legacyFace)
        let detailFace = settings.string("detailFont", legacyFace)
        let labelSize = CGFloat(min(26, max(10, settings.number("labelSize", 20))))
        let valueSize = CGFloat(min(90, max(18, settings.number("valueSize", 68))))
        let detailSize = CGFloat(min(32, max(10, settings.number("detailSize", 22))))
        let bounds = CGRect(x: 4, y: 4, width: width - 8, height: height - 8)
        let radius: CGFloat = [1, 4].contains(style.id) ? 34 : style.id == 3 ? 9 : 22
        let card = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        if style.id == 4 {
            NSGradient(starting: background, ending: background.blended(withFraction: 0.22, of: accent) ?? background)?.draw(in: card, angle: 0)
        } else {
            background.withAlphaComponent(style.id == 1 ? 0.94 : 0.97).setFill(); card.fill()
        }
        (style.id == 2 || style.id == 5 ? accent : accent.withAlphaComponent(0.4)).setStroke()
        card.lineWidth = style.id == 2 ? 3 : style.id == 5 ? 1.5 : 1
        card.stroke()
        if style.id == 2 {
            let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), xRadius: radius - 5, yRadius: radius - 5)
            accent.withAlphaComponent(0.25).setStroke(); inner.lineWidth = 1; inner.stroke()
        }

        let legacyIcon = min(70, max(40, CGFloat(width) * 0.16))
        let requestedIcon = CGFloat(min(120, max(24, settings.number("iconSize", Double(legacyIcon)))))
        let iconWidth = min(requestedIcon, CGFloat(height) - 20, CGFloat(width) * 0.32)
        let iconRect = CGRect(x: 19, y: (CGFloat(height) - iconWidth) / 2, width: iconWidth, height: iconWidth)
        if style.id != 3 && style.id != 5 {
            accent.withAlphaComponent(style.id == 4 ? 0.28 : 0.17).setFill()
            NSBezierPath(ovalIn: iconRect).fill()
        }
        let subscribed = event?.kind == .subscriber
        let customIcon = settings["iconSize"] != nil
        if let symbol = NSImage(systemSymbolName: subscribed ? "person.badge.plus.fill" : "hand.thumbsup.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: customIcon ? iconWidth * 0.58 : min(42, iconWidth * 0.53), weight: .semibold)) {
            let image = symbol.copy() as! NSImage
            image.isTemplate = false
            image.lockFocus(); accent.set(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop); image.unlockFocus()
            image.draw(in: iconRect.insetBy(dx: iconWidth * (customIcon ? 0.21 : 0.23), dy: iconWidth * (customIcon ? 0.21 : 0.23)),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        let x = iconRect.maxX + 16
        let available = max(48, CGFloat(width) - x - 18)
        func text(_ value: String, y: CGFloat, size: CGFloat, color: NSColor, face: String, role: String, defaultBold: Bool = false) {
            let font = ChatFontCatalog.styledFont(named: face, size: size,
                bold: settings.flag(role + "Bold", defaultBold), italic: settings.flag(role + "Italic"))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if settings.flag(role + "Underline") { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            (value as NSString).draw(in: CGRect(x: x, y: y, width: available, height: size * 1.45),
                                     withAttributes: attrs)
        }
        let formatted: (UInt64) -> String = { $0.formatted(.number.locale(Locale(identifier: "pt_BR"))) }
        let label = subscribed ? "NOVO INSCRITO PÚBLICO" : total != nil ? "LIKES NA LIVE" : "INSCRITOS DO CANAL"
        let primary = subscribed ? (event?.name ?? "") : total.map(formatted) ?? subscriberTotal.map { "≈ " + formatted($0) } ?? "0"
        let footer = [subscriberTotal.map { "≈ \(formatted($0)) inscritos" },
                      newPublicSubscribers.map { "+\($0) novos públicos" }].compactMap { $0 }
        let footerStep = detailSize * 1.45 + 3
        let footerHeight = footer.isEmpty ? footerStep : CGFloat(footer.count) * footerStep
        let maxPrimary = max(18, (CGFloat(height) - 22 - footerHeight - labelSize * 1.45 - 6) / 1.45)
        let actualPrimary = min(valueSize, maxPrimary)
        let lineTop = max(8, (CGFloat(height) - footerHeight - labelSize * 1.45 - 6 - actualPrimary * 1.45) / 2)
        text(label, y: lineTop, size: labelSize, color: accent, face: labelFace, role: "label", defaultBold: true)
        text(primary, y: lineTop + labelSize + 6, size: actualPrimary, color: ink, face: valueFace, role: "value", defaultBold: true)
        if footer.isEmpty {
            text(subscribed ? "Boas-vindas ao canal!" : "Obrigado pelo apoio!", y: CGFloat(height) - 10 - footerHeight,
                 size: detailSize, color: ink.withAlphaComponent(0.77), face: detailFace, role: "detail")
        } else {
            for (index, line) in footer.enumerated() {
                text(line, y: CGFloat(height) - 10 - footerHeight + CGFloat(index) * footerStep,
                     size: detailSize, color: ink.withAlphaComponent(0.82), face: detailFace, role: "detail")
            }
        }
        return bitmap
    }
}
