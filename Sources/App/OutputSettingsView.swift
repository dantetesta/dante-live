import SwiftUI
import AppKit

struct OutputSettingsView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var settings: LiveSettingsModel
    @Environment(\.dismiss) var dismiss
    @LegacyState private var tab = "quality"
    init(model: StudioModel) { self.model = model; settings = model.liveSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurações da live").font(.title2.bold())
                    Text("Suas alterações são salvas automaticamente neste Mac.").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title).foregroundStyle(.teal)
            }
            TabView(selection: $tab) {
                LiveSetupView(model: model, settings: settings).tabItem { Label("Qualidade", systemImage: "slider.horizontal.3") }.tag("quality")
                videoTab.tabItem { Label("Vídeo e áudio", systemImage: "video") }.tag("video")
                connectionTab.tabItem { Label("Conexão", systemImage: "network") }.tag("connection")
                statusTab.tabItem { Label("Diagnóstico", systemImage: "waveform.path.ecg") }.tag("status")
            }
            if let problem = settings.problem { Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if model.active {
                Text("Live ativa: novos ajustes ficam salvos para a próxima transmissão.").font(.caption).foregroundStyle(.orange)
            } else if settings.pendingVideo {
                Text("Resolução/FPS salvos diferem do canvas atual; serão aplicados antes de iniciar a live.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Label(settings.status, systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar") { settings.flush(); dismiss() }.keyboardShortcut(.cancelAction)

            }
        }.padding(24).frame(width: 760, height: 640)
        .onAppear { settings.loadKey() }
        .onDisappear { settings.flush() }
    }
    private var videoTab: some View {
        Form {
            Section("Resolução e movimento") {
                TextField("Largura", value: videoBinding(\.width), format: .number)
                TextField("Altura", value: videoBinding(\.height), format: .number)
                Picker("Quadros por segundo", selection: videoBinding(\.fps, immediate: true)) {
                    ForEach(Array(Set([24,30,60,settings.video.fps])).sorted(), id: \.self) { Text("\($0) FPS").tag($0) }
                }
                Text("Alterar estes campos cria um ajuste personalizado. Você pode salvá-lo com um nome na aba Qualidade.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Codificação H.264") {
                Picker("Encoder", selection: videoBinding(\.encoder, immediate: true)) {
                    if !model.catalog.array("encoders").contains(where: { $0.string("id") == settings.video.encoder }) {
                        Text("Encoder salvo indisponível • escolha outro").tag(settings.video.encoder)
                    }
                    ForEach(model.catalog.array("encoders").filter { $0.string("codec") == "h264" }, id: \.entryID) { entry in
                        Text(entry.string("name")).tag(entry.string("id"))
                    }
                }
                TextField("Bitrate de vídeo (kbps)", value: videoBinding(\.bitrate), format: .number)
                Picker("Áudio AAC", selection: videoBinding(\.audioBitrate, immediate: true)) {
                    ForEach([128,160,192,256,320], id: \.self) { Text("\($0) kbps").tag($0) }
                }
                Text("SDR Rec.709 • áudio estéreo 48 kHz. O uso efetivo do encoder de hardware é confirmado após iniciar a transmissão.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var connectionTab: some View {
        Form {
            Section("Transmissão RTMP / RTMPS") {
                TextField("Servidor", text: Binding(get: { settings.document.server }, set: { value in settings.edit({ $0.server = value }) }))
                SecureField("Chave de transmissão", text: Binding(get: { settings.key }, set: { settings.editKey($0) }))
                Toggle("Salvar chave no Acesso às Chaves", isOn: Binding(get: { settings.document.rememberKey }, set: { settings.rememberKey($0) }))
                Text(settings.document.rememberKey ? "A chave é guardada automaticamente no Acesso às Chaves. Ela não é incluída no projeto nem nos presets." : "A chave será usada apenas nesta sessão. Ao desativar, a cópia salva por esta conexão é removida do Acesso às Chaves.").font(.caption).foregroundStyle(.secondary)
                Button("Tentar ler a chave salva") { settings.loadKey() }
            }
            Section("YouTube") {
                Text("Use o servidor e a chave fornecidos pelo YouTube Studio. Título, descrição, capa, visibilidade e latência são configurados no YouTube.")
                Text("Salvar configurações não inicia a transmissão. Use Iniciar transmissão quando estiver pronto.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var statusTab: some View {
        Form {
            let output = model.state.object("outputs").object("stream")
            Section("Transmissão") {
                LabeledContent("Estado", value: output.flag("reconnecting") ? "Reconectando" : output.flag("stopping") ? "Finalizando" : output.flag("started") ? "Ao vivo" : output.flag("starting") || output.flag("active") ? "Iniciando" : "Parada")
                LabeledContent("Canvas atual", value: "\(Int(model.canvasWidth)) × \(Int(model.canvasHeight)) • \(Int(model.state.number("fps", 30))) FPS")
                if !output.string("error").isEmpty { Text(output.string("error")).foregroundStyle(.red) }
                if output.flag("active") {
                    LabeledContent("Quadros", value: "\(Int(output.number("frames")))")
                    LabeledContent("Descartados", value: "\(Int(output.number("dropped")))")
                    LabeledContent("Hardware", value: output.flag("hardwareConfirmed") ? "Confirmado" : "Não confirmado")
                }
            }
        }.formStyle(.grouped)
    }
    private func videoBinding<T>(_ path: WritableKeyPath<LiveVideoSettings, T>, immediate: Bool = false) -> Binding<T> {
        Binding(get: { settings.video[keyPath: path] }, set: { settings.editVideo(path, $0, immediate: immediate) })
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
