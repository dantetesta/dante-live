import SwiftUI
import AppKit

struct PropertyFields: View {
    let properties: [[String: Any]]
    @Binding var settings: [String: Any]
    var onEdit: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(properties.filter { $0.flag("visible", true) }, id: \.entryName) { property in
                field(property).disabled(!property.flag("enabled", true))
            }
        }
    }
    @ViewBuilder func field(_ p: [String: Any]) -> some View {
        let key = p.string("name"), label = p.string("description", p.string("label", key))
        switch Int(p.number("type")) {
        case 1:
            Toggle(label, isOn: Binding(get: { settings.flag(key) }, set: { set(key, $0) }))
        case 2, 3:
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                TextField(label, value: Binding<Double>(get: { settings.number(key) }, set: { set(key, min(p.number("max", Double.greatestFiniteMagnitude), max(p.number("min", -Double.greatestFiniteMagnitude), $0)), immediate: false) }), format: .number).textFieldStyle(.roundedBorder)
            }
        case 4:
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if p.number("textType") == 1 {
                    SecureField(label, text: text(key)).textFieldStyle(.roundedBorder)
                } else if p.number("textType") == 2 {
                    TextEditor(text: text(key)).frame(minHeight: 65, maxHeight: 120).font(.body).border(.secondary.opacity(0.2))
                } else if p.number("textType") == 3 { Text(settings.string(key)).font(.caption).textSelection(.enabled) }
                else { TextField(label, text: text(key)).textFieldStyle(.roundedBorder) }
            }
        case 5:
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                HStack { TextField(label, text: text(key)).textFieldStyle(.roundedBorder); Button("…") { choosePath(key, directory: p.number("pathType") == 2) } }
            }
        case 6:
            let options = p.array("items")
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Picker(label, selection: Binding(get: { optionIndex(options, value: settings[key]) }, set: { if options.indices.contains($0) { set(key, options[$0]["value"] ?? "") } })) {
                    Text("Selecionar…").tag(-1)
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Text(option.string("name", option.string("label")).isEmpty ? "Selecionar…" : option.string("name", option.string("label")))
                            .tag(index).disabled(option.flag("disabled"))
                    }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                if options.isEmpty { Text("Nenhuma opção disponível. Atualize a lista ou verifique a permissão e o dispositivo.").font(.caption).foregroundStyle(.secondary) }
            }
        case 7, 13:
            ColorPicker(label, selection: Binding(get: {
                let value = UInt32(min(Double(UInt32.max), max(0, settings.number(key, 0xFFFFFFFF))))
                return Color(red: Double(value & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double((value >> 16) & 255) / 255, opacity: Double((value >> 24) & 255) / 255)
            }, set: { color in
                let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
                let r = UInt32(c.redComponent * 255), g = UInt32(c.greenComponent * 255), b = UInt32(c.blueComponent * 255), a = UInt32(c.alphaComponent * 255)
                set(key, NSNumber(value: r | (g << 8) | (b << 16) | (a << 24)), immediate: false)
            }), supportsOpacity: p.number("type") == 13)
        case 9:
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                TextField("Família da fonte", text: Binding(get: { settings.object(key).string("face", "Helvetica") }, set: { var font = settings.object(key); font["face"] = $0; set(key, font, immediate: false) })).textFieldStyle(.roundedBorder)
                TextField("Tamanho", value: Binding<Double>(get: { settings.object(key).number("size", 48) }, set: { var font = settings.object(key); font["size"] = max(1, $0); set(key, font, immediate: false) }), format: .number).textFieldStyle(.roundedBorder)
            }
        case 10:
            VStack(alignment: .leading) {
                Text(label).font(.caption)
                ForEach(Array(settings.array(key).enumerated()), id: \.offset) { index, item in
                    HStack { Text(item.string("value")).font(.caption).lineLimit(1); Spacer(); Button { var files = settings.array(key); files.remove(at: index); set(key, files) } label: { Image(systemName: "minus.circle") } }
                }
                Button("Adicionar arquivos…") {
                    let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK { set(key, settings.array(key) + panel.urls.map { ["value": $0.path, "selected": false, "hidden": false] as [String: Any] }) }
                }
            }
        case 12:
            DisclosureGroup(label) { AnyView(PropertyFields(properties: p.array("children"), settings: $settings, onEdit: onEdit).padding(.top, 8)) }
        case 8:
            Text("\(label): ação específica do módulo ainda não integrada.").font(.caption).foregroundStyle(.secondary)
        default:
            Text("\(label): configure no JSON avançado.").font(.caption).foregroundStyle(.secondary)
        }
    }
    func set(_ key: String, _ value: Any, immediate: Bool = true) {
        settings[key] = value
        onEdit(immediate)
    }
    func text(_ key: String) -> Binding<String> { Binding(get: { settings.string(key) }, set: { set(key, $0, immediate: false) }) }
    func choosePath(_ key: String, directory: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        if panel.runModal() == .OK, let url = panel.url { set(key, url.path) }
    }
    func optionIndex(_ options: [[String: Any]], value: Any?) -> Int {
        guard let value else { return -1 }
        return options.firstIndex { String(describing: $0["value"] ?? "") == String(describing: value) } ?? -1
    }
}

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    var allowsSecondarySheets = true
    var onCollapse: (() -> Void)?
    @LegacyState private var settings: [String: Any] = [:]
    @LegacyState private var properties: [[String: Any]] = []
    @LegacyState private var advanced = "{}"
    @LegacyState private var loadedSource = ""
    @StateObject private var edits = PropertyEditQueue()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("PROPRIEDADES").font(.caption.weight(.bold)); Spacer(); if let onCollapse { Button(action: onCollapse) { Image(systemName: "sidebar.right") }.help("Recolher propriedades").accessibilityLabel("Recolher propriedades") }; Button { reload() } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar propriedades") }.padding(12)
            Divider()
            if let item = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.string("name")).font(.headline)
                        if allowsSecondarySheets && isCameraSource(item.string("type")) {
                            Button("Escolher câmera e visualizar…") {
                                model.cameraSourceName = model.selectedName; model.showingCamera = true
                            }.buttonStyle(.borderedProminent)
                        }
                        if isCameraSource(item.string("type")) || item.string("type")=="dante_guest_video" || !item.object("cameraMask").isEmpty {
                            CameraMaskView(model:model,item:item)
                            Divider()
                        }
                        if item.flag("awaitingVideo") || (item.number("width") > 0 && item.number("height") > 0) {
                        if item.flag("awaitingVideo") {
                            Text("Esta fonte ainda não fornece imagem. Selecione o dispositivo ou arquivo. O enquadramento será preparado quando o vídeo estiver disponível.")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Text("Imagem da fonte: \(Int(item.number("width"))) × \(Int(item.number("height")))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Ajustar") { _ = model.command("item.fit", ["scene": model.sceneName, "id": item.sceneItemID]) }.help("Ajustar ao canvas mantendo a proporção")
                            Button("Centralizar") { _ = model.command("item.center", ["scene": model.sceneName, "id": item.sceneItemID]) }
                        }.disabled(item.flag("locked") || item.number("width") <= 0 || item.number("height") <= 0)
                        Button("Tamanho original (100%)") { _ = model.command("item.native", ["scene": model.sceneName, "id": item.sceneItemID]) }
                            .disabled(item.flag("locked") || item.number("width") <= 0 || item.number("height") <= 0)
                        DisclosureGroup("Transformação") {
                            VStack(spacing: 8) {
                                ForEach(["x", "y", "scaleX", "scaleY", "rotation", "cropLeft", "cropTop", "cropRight", "cropBottom"], id: \.self) { key in
                                    HStack {
                                        Text(transformLabel(key)).font(.caption); Spacer()
                                        TextField(key, value: Binding<Double>(get: { item.number(key, key.hasPrefix("scale") ? 1 : 0) }, set: {
                                            _ = model.command("item.transform", ["scene": model.sceneName, "id": item.sceneItemID, key: $0])
                                        }), format: .number).textFieldStyle(.roundedBorder).frame(width: 85).disabled(item.flag("locked"))
                                    }
                                }
                                Button("Ajustar ao canvas") { _ = model.command("item.fit", ["scene": model.sceneName, "id": item.sceneItemID]) }.disabled(item.flag("locked"))
                            }.padding(.top, 8)
                        }
                        CanvasFramingControls(model:model,item:item)
                        Text("⌘F ajusta à cena. ⌥ deixa as alças laranja para recortar; por dentro, ajusta o enquadramento.").font(.caption2).foregroundStyle(.secondary)
                        }
                        if allowsSecondarySheets { Button("Filtros (\(item.array("filters").count))") { model.showingFilters = true } }
                        if item.flag("audio") { AudioAdvancedView(model: model, item: item) }
                        if item.number("mediaDuration") > 0 || item.string("type").contains("ffmpeg") {
                            HStack { Button("Reproduzir") { _ = model.command("media.play", ["name": model.selectedName], undo: false) }; Button("Pausar") { _ = model.command("media.pause", ["name": model.selectedName], undo: false) }; Button { _ = model.command("media.restart", ["name": model.selectedName], undo: false) } label: { Image(systemName: "backward.end") } }.controlSize(.small)
                        }
                        Divider()
                        if item.string("type") == "dante_guest_name" {
                            GuestNameSettingsView(settings: $settings) { applyChange(immediate: $0) }
                        } else if item.string("type") == "dante_audio_visualizer" {
                            AudioVisualizerSettingsView(settings: $settings, scenes: model.scenes, onEdit: applyChange)
                        } else if item.string("type") == "dante_browser_tab_audio" {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("Áudio de uma aba do Chrome").font(.headline)
                                Text(model.browserTabAudio.message(for: item.string("name")))
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Escolher ou trocar aba…") {
                                    Task { @MainActor in await model.browserTabAudio.select(item.string("name")) }
                                }.buttonStyle(.borderedProminent)
                                Text("No Chrome, selecione Aba do Chrome e ative Compartilhar áudio. A página de captura precisa ficar aberta; escolha novamente após reiniciar o Dante.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if ["dante_youtube_chat", "dante_superchat"].contains(item.string("type")) {
                            ChatStylePicker(settings: $settings, lower: item.string("type") == "dante_superchat") { applyChange(immediate: true) }
                            Button("Abrir chat e fila de Super Chats") { model.showingChat = true }
                        } else if item.string("type") == "dante_youtube_alert" {
                            YouTubeActivitySettings(settings:$settings,activity:model.youtube.activity) { applyChange(immediate:true) }
                        } else if item.string("type") == "dante_marquee" {
                            MarqueeSettingsView(settings: $settings, onEdit: applyChange)
                        } else if item.string("type") == "dante_qrcode" {
                            QRCodeSettingsView(settings: $settings) { applyChange(immediate: true) }
                        } else { PropertyFields(properties: properties, settings: $settings, onEdit: applyChange) }
                        if item.string("type") == "sck_audio_capture" {
                            Text("A captura de aplicativo inclui todo o áudio desse app. Para isolar uma aba, adicione a fonte Áudio de aba do navegador à cena e retire esta fonte do mixer para não duplicar o som.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Adicionar áudio de uma aba do Chrome…") {
                                let used = Set(model.scenes.flatMap { $0.array("items").map { $0.string("name") } })
                                var name = "Aba do Chrome", suffix = 2
                                while used.contains(name) { name = "Aba do Chrome \(suffix)"; suffix += 1 }
                                if model.command("source.add", ["scene": model.sceneName, "type": "dante_browser_tab_audio", "name": name]) {
                                    model.selectedItem = model.items.first(where: { $0.string("name") == name })?.sceneItemID
                                    model.notice = "Fonte de aba criada. Desative Áudio do Mac se não quiser duplicar o som."
                                    Task { @MainActor in await model.browserTabAudio.select(name) }
                                }
                            }.buttonStyle(.borderedProminent)
                        } else if item.string("type") == "screen_capture" {
                            Text("Para mostrar só uma janela do navegador, escolha o método Janela e selecione o título desejado. Isso isola a imagem da janela, mas não separa o áudio das abas; adicione áudio somente quando necessário.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if item.string("type") != "dante_qrcode" { Text("Alterações aplicadas automaticamente.").font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup("JSON avançado") {
                            VStack {
                                TextEditor(text: $advanced).font(.system(.caption, design: .monospaced)).frame(height: 150)
                                Button("Aplicar JSON") {
                                    guard let data = advanced.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else { model.error = "Informe um objeto JSON válido."; return }
                                    edits.flush()
                                    if model.command("source.update", ["name": loadedSource, "settings": dictionary]) { reload() }
                                }
                            }
                        }
                    }.padding(14)
                }.id(model.selectedName)
            } else {
                ContentUnavailableView("Nenhuma fonte selecionada", systemImage: "cursorarrow", description: Text("Selecione no canvas ou na lista de fontes."))
                Spacer()
            }
        }.onAppear(perform: reload)
        .onChange(of: model.selectedName) { _, _ in reload() }
        .onChange(of: model.inspectorRevision) { _, _ in
            // The sheet's final edit must flush before its closing reload.
            if allowsSecondarySheets || model.showingProperties { edits.cancel(); reload() }
        }
        .onDisappear {
            edits.flush()
            if !allowsSecondarySheets { model.inspectorRevision += 1 }
        }
    }
    func applyChange(immediate: Bool) {
        let name = loadedSource
        guard !name.isEmpty, name == model.selectedName else { return }
        let candidate = settings
        edits.submit(immediate: immediate) {
            guard model.scenes.contains(where: { $0.array("items").contains(where: { $0.string("name") == name }) }) else { return }
            guard let engine = model.engine else { return }
            let normalized = jsonObject(copied(dante_engine_properties_with_settings(engine, name, jsonString(candidate))))
            let values = normalized.object("settings")
            if model.command("source.update", ["name": name, "settings": values, "autoPlace": true]), loadedSource == name {
                if immediate { settings = values }
                let value = model.properties(name: name)
                properties = value.array("properties")
                // Keep typed values/caret stable; only update dependent choices.
                advanced = jsonString(value.object("settings"))
            }
        }
    }
    func reload() {
        edits.flush()
        loadedSource = model.selectedName
        let value = model.properties(name: loadedSource)
        settings = value.object("settings"); properties = value.array("properties"); advanced = jsonString(settings)
    }
    func transformLabel(_ key: String) -> String { ["x":"Posição X", "y":"Posição Y", "scaleX":"Escala X", "scaleY":"Escala Y", "rotation":"Rotação", "cropLeft":"Corte esquerdo", "cropTop":"Corte superior", "cropRight":"Corte direito", "cropBottom":"Corte inferior"][key] ?? key }
}

func isCameraSource(_ type: String) -> Bool {
    type.contains("avcapture") || type.contains("av_capture")
}

struct AudioAdvancedView: View {
    @ObservedObject var model: StudioModel
    let item: [String: Any]
    var body: some View {
        DisclosureGroup("Áudio avançado") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Atraso (ms)", value: Binding<Double>(get: { item.number("syncMS") }, set: { _ = model.command("audio.set", ["name": item.string("name"), "syncMS": $0]) }), format: .number).textFieldStyle(.roundedBorder)
                Picker("Monitoramento", selection: Binding(get: { Int(item.number("monitoring")) }, set: { _ = model.command("audio.set", ["name": item.string("name"), "monitoring": $0]) })) {
                    Text("Desligado").tag(0); Text("Somente monitor").tag(1); Text("Monitor e saída").tag(2)
                }
                Text("Trilhas enviadas pela fonte").font(.caption)
                HStack {
                    ForEach(0..<6) { index in
                        Toggle("\(index + 1)", isOn: Binding(get: { Int(item.number("tracks")) & (1 << index) != 0 }, set: { enabled in
                            let mask = Int(item.number("tracks")); _ = model.command("audio.set", ["name": item.string("name"), "tracks": enabled ? mask | (1 << index) : mask & ~(1 << index)])
                        })).toggleStyle(.button).controlSize(.mini)
                    }
                }
                Text("Esta versão exporta a trilha 1. Demais trilhas permanecem configuradas no projeto.").font(.caption2).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
    }
}
