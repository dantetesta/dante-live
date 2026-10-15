import SwiftUI
import AppKit

struct OutputSettingsView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    @LegacyState private var server = "rtmp://127.0.0.1:1935/live"
    @LegacyState private var key = ""
    @LegacyState private var encoder = ""
    @LegacyState private var bitrate = 14000
    @LegacyState private var audioBitrate = 128
    @LegacyState private var remember = false
    @LegacyState private var replaySeconds = 20
    @LegacyState private var width = 1920
    @LegacyState private var height = 1080
    @LegacyState private var fps = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Saídas de produção").font(.title2.bold())
            Form {
                LiveSetupView(model: model, width: $width, height: $height, fps: $fps, bitrate: $bitrate, audioBitrate: $audioBitrate, encoder: $encoder)
                Section("Vídeo do projeto") {
                    HStack { TextField("Largura", value: $width, format: .number); Text("×"); TextField("Altura", value: $height, format: .number) }
                    Picker("Quadros por segundo", selection: $fps) { Text("24 FPS").tag(24); Text("30 FPS").tag(30); Text("60 FPS").tag(60) }
                    Button("Aplicar resolução e FPS") {
                        _ = model.command("video.configure", ["width": width, "height": height, "fps": fps])
                    }.disabled(model.active)
                    Text("Altere o vídeo com as saídas paradas. As posições das fontes são preservadas.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Transmissão RTMP / RTMPS") {
                    TextField("Servidor", text: $server)
                    SecureField("Chave", text: $key)
                    Toggle("Guardar a chave no Acesso às Chaves", isOn: $remember)
                    Button("Ler chave salva") { do { key = try SecretStore.read(account: server) } catch { model.error = error.localizedDescription } }
                }
                Section("Codificação H.264") {
                    Picker("Encoder", selection: $encoder) {
                        ForEach(model.catalog.array("encoders").filter { $0.string("codec") == "h264" }, id: \.entryID) { entry in
                            Text(entry.string("name") + (entry.flag("hardware") ? " • hardware disponível" : "")).tag(entry.string("id"))
                        }
                    }
                    TextField("Bitrate (kbps)", value: $bitrate, format: .number)
                    Picker("Áudio AAC", selection: $audioBitrate) {
                        ForEach([128,160,192,256,320], id: \.self) { value in Text("\(value) kbps").tag(value) }
                    }
                    Text("Canvas atual: \(Int(model.canvasWidth)) × \(Int(model.canvasHeight)), \(Int(model.state.number("fps", 30))) FPS, SDR Rec.709. Áudio estéreo 48 kHz, trilha 1. Gravação MKV.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Replay buffer") {
                    Stepper("\(replaySeconds) segundos", value: $replaySeconds, in: 5...120, step: 5)
                    HStack {
                        if model.replaying {
                            Button("Salvar replay") { _ = model.command("replay.save", undo: false) }
                            Button("Parar buffer") { _ = model.command("replay.stop", undo: false) }
                        } else {
                            Button("Iniciar buffer…") {
                                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                                guard panel.runModal() == .OK, let url = panel.url else { return }
                                saveConfiguration()
                                _ = model.command("replay.start", ["directory": url.path, "seconds": replaySeconds, "encoder": encoder, "bitrate": bitrate, "audioBitrate": audioBitrate], undo: false)
                            }
                        }
                    }
                }
                Section("Estado real das saídas") {
                    ForEach(["recording", "stream", "replay"], id: \.self) { name in
                        let output = model.state.object("outputs").object(name)
                        HStack { Text(["recording": "Gravação", "stream": "Transmissão", "replay": "Replay"][name] ?? name); Spacer(); Text(output.flag("reconnecting") ? "Reconectando" : output.flag("stopping") ? "Finalizando" : output.flag("started") ? "Ativa" : output.flag("starting") || output.flag("active") ? "Iniciando" : "Parada") }
                        if !output.string("error").isEmpty { Text(output.string("error")).foregroundStyle(.red).font(.caption) }
                        if output.flag("active") { Text("\(Int(output.number("frames"))) quadros • \(Int(output.number("dropped"))) descartados • hardware \(output.flag("hardwareConfirmed") ? "confirmado" : "não confirmado")").font(.caption).monospacedDigit() }
                    }
                }
            }.formStyle(.grouped).frame(width: 620, height: 540)
            HStack {
                Button("Fechar") { dismiss() }; Spacer()
                Button("Gravar com estas opções…") {
                    let panel = NSSavePanel(); panel.nameFieldStringValue = "Dante-\(Int(Date().timeIntervalSince1970)).mkv"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    let path = url.pathExtension == "mkv" ? url.path : url.path + ".mkv"
                    saveConfiguration()
                    if model.command("recording.start", ["path": path, "encoder": encoder, "bitrate": bitrate, "audioBitrate": audioBitrate], undo: false) { dismiss() }
                }.disabled(model.recording)
                Button("Iniciar transmissão") {
                    model.confirm("Iniciar transmissão para este servidor?") {
                        do {
                            if remember { try SecretStore.save(key, account: server) }
                            saveConfiguration()
                            if model.command("stream.start", ["server": server, "key": key, "encoder": encoder, "bitrate": bitrate, "audioBitrate": audioBitrate], undo: false) { key = ""; dismiss() }
                        } catch { model.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(model.streaming || encoder.isEmpty)
            }
        }.padding(24).onAppear {
            let saved = model.outputConfiguration
            encoder = model.catalog.array("encoders").contains { $0.string("id") == saved.encoder } ? saved.encoder : model.catalog.string("defaultEncoder")
            bitrate = saved.bitrate; audioBitrate = saved.audioBitrate
            width = Int(model.canvasWidth); height = Int(model.canvasHeight); fps = Int(model.state.number("fps", 30))
        }
    }
    private func saveConfiguration() {
        guard (100...200000).contains(bitrate), [128,160,192,256,320].contains(audioBitrate) else { return }
        model.outputConfiguration.bitrate = bitrate
        model.outputConfiguration.audioBitrate = audioBitrate
        model.outputConfiguration.encoder = encoder
        model.outputConfiguration.save()
    }
}

struct FilterView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    @LegacyState private var type = ""
    @LegacyState private var name = ""
    @LegacyState private var selected = ""
    @LegacyState private var settings: [String: Any] = [:]
    @LegacyState private var properties: [[String: Any]] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filtros • \(model.selectedName)").font(.title2.bold())
            HStack(alignment: .top) {
                List(selection: $selected) {
                    ForEach(model.selected?.array("filters") ?? [], id: \.entryName) { filter in Text(filter.string("name")).tag(filter.string("name")) }
                }.frame(width: 190, height: 300)
                ScrollView { PropertyFields(properties: properties, settings: $settings).padding(8) }.frame(width: 340, height: 300)
            }
            HStack {
                Picker("Filtro", selection: $type) {
                    Text("Escolher…").tag("")
                    ForEach(model.catalog.array("filters"), id: \.entryID) { filter in Text(filter.string("name")).tag(filter.string("id")) }
                }
                TextField("Nome", text: $name).textFieldStyle(.roundedBorder)
                Button("Adicionar") {
                    if model.command("filter.add", ["name": model.selectedName, "type": type, "filter": name]) { selected = name; reload() }
                }.disabled(type.isEmpty || name.isEmpty)
            }
            HStack {
                Button("Remover", role: .destructive) { model.confirm("Remover este filtro?") { if model.command("filter.remove", ["name": model.selectedName, "filter": selected]) { selected = ""; properties = [] } } }.disabled(selected.isEmpty)
                Spacer(); Button("Fechar") { dismiss() }
                Button("Aplicar") { if model.command("filter.update", ["name": model.selectedName, "filter": selected, "settings": settings]) { reload() } }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
            }
        }.padding(24).onChange(of: selected) { _, _ in reload() }.onChange(of: type) { _, new in name = model.catalog.array("filters").first { $0.string("id") == new }?.string("name") ?? "Filtro" }
    }
    func reload() {
        guard let engine = model.engine, !selected.isEmpty else { return }
        let result = jsonObject(copied(dante_engine_filter_properties(engine, model.selectedName, selected)))
        settings = result.object("settings"); properties = result.array("properties")
    }
}
