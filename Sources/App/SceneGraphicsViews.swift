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
    let fonts = ["Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Trebuchet MS", "Verdana"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Faixa de texto rolante", systemImage: "text.line.first.and.arrowtriangle.forward").font(.headline)
            TextEditor(text: Binding(get: { settings.string("text") }, set: { settings["text"] = String($0.prefix(250)); onEdit(false) }))
                .font(.body).frame(height: 90).overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
            Text("\(settings.string("text").count)/250 caracteres • links aparecem como texto").font(.caption).foregroundStyle(.secondary)
            slider("Altura da faixa", key: "height", range: 40...320, fallback: 80, unit: "px")
            slider("Velocidade", key: "speed", range: 0...500, fallback: 90, unit: "px/s")
            Text(settings.number("speed", 90) == 0 ? "Texto parado. Aumente a velocidade para rolar." : "Rolagem da direita para a esquerda, em repetição.").font(.caption).foregroundStyle(.secondary)
            Picker("Fonte", selection: Binding(get: { settings.string("font", "Helvetica Neue") }, set: { settings["font"] = $0; onEdit(true) })) { ForEach(fonts, id: \.self) { Text($0).tag($0) } }
            slider("Tamanho da letra", key: "fontSize", range: 12...96, fallback: 36, unit: "px")
            Text("Em faixas baixas, a letra se ajusta para caber na altura.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("Negrito", isOn: flag("bold")).fontWeight(.bold)
                Toggle("Itálico", isOn: flag("italic")).italic()
            }.toggleStyle(.button)
            GraphicColorPicker(title: "Cor da letra", settings: $settings, key: "ink", fallback: 0xFFFFFF) { onEdit(false) }
            GraphicColorPicker(title: "Cor da faixa", settings: $settings, key: "background", fallback: 0x142632) { onEdit(false) }
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
