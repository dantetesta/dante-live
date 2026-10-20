import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GraphicColorPicker: View {
    let title: String
    @Binding var settings: [String: Any]
    let key: String
    let fallback: Double
    var onEdit: () -> Void
    var body: some View {
        ColorPicker(title, selection: Binding(get: { Color(nsColor: QRArtwork.rgb(settings.number(key, fallback))) }, set: { value in
            let c = NSColor(value).usingColorSpace(.sRGB) ?? .black
            settings[key] = (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8) | Int((c.blueComponent * 255).rounded()); onEdit()
        }), supportsOpacity: false)
    }
}

struct MarqueeSettingsView: View {
    @Binding var settings: [String: Any]
    var onEdit: (Bool) -> Void
    private var phraseMode: Bool { settings.number("displayMode") == 1 }
    private func color(_ key: String, fallback: Double) -> Binding<Color> {
        Binding(get: { Color(nsColor: QRArtwork.rgb(settings.number(key, fallback))) }, set: { value in
            let c = NSColor(value).usingColorSpace(.sRGB) ?? .black
            settings[key] = (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8) | Int((c.blueComponent * 255).rounded())
            onEdit(false)
        })
    }
    private func opacity(_ key: String) -> Binding<Double> {
        Binding(get: { min(1, max(0, settings.number(key, 1))) }, set: { settings[key] = $0; onEdit(false) })
    }
    private func gradientStop(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(get: { settings.number(key, fallback) }, set: { value in
            let position = value.rounded()
            settings[key] = position
            if key == "gradientStart", settings.number("gradientEndPosition", 100) <= position {
                settings["gradientEndPosition"] = min(100, position + 5)
            } else if key == "gradientEndPosition", settings.number("gradientStart") >= position {
                settings["gradientStart"] = max(0, position - 5)
            }
            onEdit(false)
        })
    }
    private func gradientSlider(_ title: String, key: String, fallback: Double, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text("\(Int(settings.number(key, fallback)))%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: gradientStop(key, fallback: fallback), in: range, step: 1).accessibilityLabel(title)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Faixa de texto", systemImage: "text.line.first.and.arrowtriangle.forward").font(.headline)
            Picker("Exibição", selection: Binding(get: { Int(settings.number("displayMode")) }, set: { settings["displayMode"] = $0; onEdit(true) })) {
                Text("Rolagem").tag(0)
                Text("Frases com slide").tag(1)
            }.pickerStyle(.segmented)
            TextEditor(text: Binding(get: { settings.string("text") }, set: { settings["text"] = String($0.prefix(250)); onEdit(false) }))
                .font(.body).frame(height: 90).overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
            Text(phraseMode ? "\(settings.string("text").count)/250 caracteres • cada linha não vazia é uma frase" : "\(settings.string("text").count)/250 caracteres • na rolagem, quebras de linha viram espaços")
                .font(.caption).foregroundStyle(.secondary)
            slider("Altura da faixa", key: "height", range: 40...320, fallback: 80, unit: "px")
            if phraseMode {
                slider("Intervalo entre frases", key: "phraseInterval", range: 1...30, fallback: 5, unit: "s")
                Picker("Entrada da frase", selection: Binding(get: { Int(settings.number("slideDirection")) }, set: { settings["slideDirection"] = $0; onEdit(true) })) {
                    Text("Sobe").tag(0); Text("Desce").tag(1)
                }
                Text("As frases se alternam no intervalo escolhido. Uma linha longa se ajusta à largura e à altura da faixa.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                slider("Velocidade", key: "speed", range: 0...500, fallback: 90, unit: "px/s")
                Picker("Sentido", selection: Binding(get: { Int(settings.number("scrollDirection")) }, set: { settings["scrollDirection"] = $0; onEdit(true) })) {
                    Text("Direita → esquerda").tag(0); Text("Esquerda → direita").tag(1)
                }
                Text(settings.number("speed", 90) == 0 ? "Texto parado. Aumente a velocidade para rolar." : "Rolagem contínua em repetição.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            InstalledFontPicker(title: "Fonte", selection: Binding(get: { settings.string("font", "Helvetica Neue") }, set: { settings["font"] = $0; onEdit(true) }))
            slider("Tamanho da letra", key: "fontSize", range: 12...96, fallback: 36, unit: "px")
            Text(phraseMode ? "Frases longas podem reduzir a letra; aumente a altura se houver corte." : "Em faixas baixas, a letra se ajusta para caber na altura.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("Negrito", isOn: flag("bold")).fontWeight(.bold)
                Toggle("Itálico", isOn: flag("italic")).italic()
            }.toggleStyle(.button)
            GraphicColorPicker(title: "Cor da letra", settings: $settings, key: "ink", fallback: 0xFFFFFF) { onEdit(false) }
            Divider()
            Toggle("Gradiente de duas cores", isOn: flag("gradientEnabled"))
            ColorPicker(settings.flag("gradientEnabled") ? "Cor inicial" : "Cor da faixa", selection: color("background", fallback: 0x142632), supportsOpacity: false)
            HStack { Text(settings.flag("gradientEnabled") ? "Opacidade inicial" : "Opacidade da faixa"); Spacer(); Text("\(Int(opacity("backgroundOpacity").wrappedValue * 100))%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: opacity("backgroundOpacity"), in: 0...1).accessibilityLabel("Opacidade da primeira cor da faixa")
            if settings.flag("gradientEnabled") {
                ColorPicker("Cor final", selection: color("gradientEndColor", fallback: 0x35B8C8), supportsOpacity: false)
                HStack { Text("Opacidade final"); Spacer(); Text("\(Int(opacity("gradientEndOpacity").wrappedValue * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: opacity("gradientEndOpacity"), in: 0...1).accessibilityLabel("Opacidade final da faixa")
                Picker("Direção do gradiente", selection: Binding(get: { Int(settings.number("gradientAxis")) }, set: { settings["gradientAxis"] = $0; onEdit(true) })) {
                    Text("Esquerda → direita").tag(0); Text("Direita → esquerda").tag(1)
                    Text("Cima → baixo").tag(2); Text("Baixo → cima").tag(3)
                }
                gradientSlider("Início do gradiente", key: "gradientStart", fallback: 0, range: 0...95)
                gradientSlider("Fim do gradiente", key: "gradientEndPosition", fallback: 100, range: 5...100)
                Text("Antes do início, prevalece a primeira cor; após o fim, a segunda. A transparência revela as fontes abaixo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    func flag(_ key: String) -> Binding<Bool> { Binding(get: { settings.flag(key) }, set: { settings[key] = $0; onEdit(true) }) }
    func slider(_ title: String, key: String, range: ClosedRange<Double>, fallback: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text("\(Int(settings.number(key, fallback))) \(unit)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, settings.number(key, fallback))) }, set: { settings[key] = $0.rounded(); onEdit(false) }), in: range).accessibilityLabel(title)
        }
    }
}

struct QRCodeSettingsView: View {
    @Binding var settings: [String: Any]
    var onApply: () -> Void
    @LegacyState private var error: String?
    @LegacyState private var generating = false
    @LegacyState private var pending = false
    @LegacyState private var generation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("QR Code", systemImage: "qrcode").font(.headline)
            if let bytes = Data(base64Encoded: settings.string("imagePNG")), let image = NSImage(data: bytes) {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 240, maxHeight: 240).frame(maxWidth: .infinity).accessibilityLabel("Prévia do QR Code aplicado")
            }
            Picker("Tipo", selection: text("qrType", fallback: "url")) {
                Text("Link / site").tag("url"); Text("Texto").tag("text"); Text("Pix").tag("pix")
            }
            if settings.string("qrType", "url") == "pix" {
                Picker("Tipo de chave", selection: text("pixKeyType", fallback: "email")) {
                    Text("E-mail").tag("email"); Text("Telefone").tag("phone"); Text("CPF").tag("cpf"); Text("CNPJ").tag("cnpj"); Text("Aleatória").tag("random")
                }
                field("Chave Pix cadastrada", key: "pixKey")
                field("Nome do recebedor", key: "pixName")
                field("Cidade", key: "pixCity")
                field("Valor em R$ (opcional)", key: "pixAmount", placeholder: "Vazio: quem paga escolhe")
                Text("O banco confirma o titular da chave. Aqui verificamos o formato e montamos o código; não consultamos o cadastro bancário. Leia no app do banco e confira o recebedor antes de divulgar.").font(.caption).foregroundStyle(.secondary)
            } else {
                field(settings.string("qrType", "url") == "url" ? "Link completo" : "Conteúdo", key: "qrValue", placeholder: settings.string("qrType", "url") == "url" ? "https://seusite.com.br" : "Sua mensagem")
            }
            Picker("Estilo", selection: text("qrStyle", fallback: "square")) { Text("Clássico").tag("square"); Text("Arredondado").tag("round"); Text("Pontos").tag("dots") }
            GraphicColorPicker(title: "Cor do código", settings: $settings, key: "qrInk", fallback: 0x102632) { changed() }
            GraphicColorPicker(title: "Cor do fundo", settings: $settings, key: "qrBackground", fallback: 0xFFFFFF) { changed() }
            HStack {
                Button("Escolher logo…", action: chooseLogo)
                if !settings.string("qrLogo").isEmpty { Button("Remover") { settings.removeValue(forKey: "qrLogo"); changed() } }
            }
            Text("O logo ocupa uma pequena área central. Cores e desenho são verificados por leitura automática antes de aplicar.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red).accessibilityLabel("Erro: \(error)") }
            Button(generating ? "Verificando leitura…" : "Gerar e aplicar QR Code", action: generate).buttonStyle(.borderedProminent).disabled(generating)
            if pending { Text("Alterações ainda não aplicadas à cena.").font(.caption).foregroundStyle(.orange) }
            Text("Redimensione pelas alças do canvas. Preserve o formato quadrado e a margem clara para facilitar a leitura na live.").font(.caption).foregroundStyle(.secondary)
        }.disabled(generating).onDisappear { generation?.cancel(); generation = nil; generating = false }
    }
    func changed() { pending = true; error = nil }
    func text(_ key: String, fallback: String = "") -> Binding<String> { Binding(get: { settings.string(key, fallback) }, set: { settings[key] = String($0.prefix(1000)); changed() }) }
    func field(_ title: String, key: String, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); TextField(placeholder.isEmpty ? title : placeholder, text: text(key)).textFieldStyle(.roundedBorder) }
    }
    func chooseLogo() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_000_000 else { throw QRContent.fail("Escolha uma imagem de até 8 MB.") }
                settings["qrLogo"] = try QRArtwork.logo(Data(contentsOf: url)).base64EncodedString(); changed()
            } catch { self.error = error.localizedDescription }
        }
    }
    func generate() {
        let candidate = settings; generating = true; error = nil
        // No network. Work stays bounded and runs away from the UI's render loop.
        generation = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { Result { try QRArtwork.generate(candidate) } }.value
            guard !Task.isCancelled else { return }
            generating = false
            switch result {
            case .success(let artwork):
                settings["imagePNG"] = artwork.png.base64EncodedString(); settings["qrPayload"] = artwork.payload; pending = false; onApply()
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}
