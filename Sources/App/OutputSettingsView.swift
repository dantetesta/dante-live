import SwiftUI
import AppKit

struct OutputSettingsView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var settings: LiveSettingsModel
    @StudioDismiss var dismiss
    @LegacyState private var channelName = ""
    init(model: StudioModel) { self.model = model; settings = model.liveSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurações da live").font(.title2.bold())
                    Text(model.outputTab == "broadcast" ? "Prepare o conteúdo, escolha o público e deixe tudo pronto para transmitir." : "Suas alterações são salvas automaticamente neste Mac.").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title).foregroundStyle(.teal)
            }
            Picker("Configurações", selection: $model.outputTab) {
                Text("Preparar live").tag("broadcast")
                Text("Qualidade").tag("quality")
                Text("Vídeo e áudio").tag("video")
                Text("Conexão").tag("connection")
                Text("Conta YouTube").tag("youtube")
                Text("Diagnóstico").tag("status")
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
            Group {
                switch model.outputTab {
                case "broadcast": LivePreparationView(model: model, youtube: model.youtube, settings: settings)
                case "video": videoTab
                case "connection": connectionTab
                case "youtube": YouTubeSettingsView(model: model, youtube: model.youtube, settings: settings)
                case "status": statusTab
                default: LiveSetupView(model: model, settings: settings)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if ["quality", "video"].contains(model.outputTab) { presetContext }
            if let problem = settings.problem, !["broadcast", "youtube"].contains(model.outputTab) { Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if model.active {
                Text("Live ativa: novos ajustes ficam salvos para a próxima transmissão.").font(.caption).foregroundStyle(.orange)
            } else if settings.pendingVideo, !["broadcast", "youtube"].contains(model.outputTab) {
                Text("Resolução/FPS salvos diferem do canvas atual; serão aplicados antes de iniciar a live.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if !["broadcast", "youtube"].contains(model.outputTab) {
                    Label(settings.status, systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar") { settings.flush(); dismiss() }.keyboardShortcut(.cancelAction)

            }
        }.padding(24).frame(
            width: min(1000, (NSScreen.main?.visibleFrame.width ?? 1080) - 80),
            height: min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 80)
        ).background(Color(nsColor: .windowBackgroundColor))
        .onAppear { settings.loadKey() }
        .onDisappear { settings.flush(); model.youtube.flush() }
    }
    @ViewBuilder private var presetContext: some View {
        if settings.document.selection == "custom" {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Você personalizou esta qualidade").font(.callout.bold())
                    Text("Os ajustes já ficam salvos. Crie um preset para usar esta combinação outras vezes.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Criar preset") { _ = settings.savePreset(name: settings.suggestedPresetName) }
                    .buttonStyle(.borderedProminent).help("Salvar como \(settings.suggestedPresetName)")
            }.padding(12).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if let preset = settings.selectedPreset {
            HStack {
                Label(preset.name, systemImage: "checkmark.circle.fill").foregroundStyle(.teal).lineLimit(1)
                Spacer()
                Button("Renomear…") { model.askName(title: "Nome do preset", initial: preset.name) { settings.renamePreset(preset.id, name: $0) } }
                Button("Excluir…", role: .destructive) { model.confirm("Excluir o preset “\(preset.name)”? Seus ajustes atuais serão mantidos.") { settings.removePreset(preset.id) } }
            }.padding(12).background(.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private var videoTab: some View {
        Form {
            Section("Resolução e movimento") {
                TextField("Largura", value: videoBinding(\.width), format: .number)
                TextField("Altura", value: videoBinding(\.height), format: .number)
                Picker("Quadros por segundo", selection: videoBinding(\.fps, immediate: true)) {
                    ForEach(Array(Set([24,30,60,settings.video.fps])).sorted(), id: \.self) { Text("\($0) FPS").tag($0) }
                }
                Text("Alterar estes campos cria um ajuste personalizado. Use Criar preset para reutilizar esses ajustes.").font(.caption).foregroundStyle(.secondary)
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
            Section("Destino da transmissão") {
                Toggle("Usar conta conectada do YouTube", isOn: Binding(get: { settings.document.youtubeMode == true }, set: { value in settings.edit({ $0.youtubeMode = value }, immediate: true) }))
                Text("Para título, capa e agendamento, conecte sua conta na aba YouTube. Com RTMP manual, configure os dados da live no YouTube Studio.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Meus canais RTMP") {
                Picker("Canal", selection: Binding(get: { settings.document.selectedChannelID?.uuidString ?? "" }, set: { settings.selectChannel(UUID(uuidString: $0)) })) {
                    Text("Nova conexão / não nomeada").tag("")
                    ForEach(settings.channels) { Text($0.name).tag($0.id.uuidString) }
                }
                if let channel = settings.selectedChannel {
                    HStack {
                        Label("Canal salvo", systemImage: "checkmark.circle").foregroundStyle(.teal)
                        Spacer()
                        Button("Renomear…") { model.askName(title: "Nome do canal", initial: channel.name) { settings.renameChannel(channel.id, name: $0) } }
                        Button("Excluir…", role: .destructive) {
                            model.confirm("Excluir o canal “\(channel.name)” e sua chave salva?") { settings.deleteChannel(channel.id) }
                        }
                    }
                } else if settings.document.rememberKey {
                    HStack {
                        TextField("Nome do canal", text: $channelName, prompt: Text("Ex.: Meu canal no YouTube"))
                        Button("Salvar canal") { if settings.saveChannel(name: channelName) { channelName = "" } }
                            .disabled(channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.key.isEmpty || settings.document.server.isEmpty)
                    }
                }
                Text("Ao escolher um canal, o servidor e a chave são recuperados automaticamente. A troca só será usada na próxima transmissão.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Transmissão RTMP / RTMPS") {
                TextField("Servidor", text: Binding(get: { settings.document.server }, set: { value in settings.edit({ $0.server = value }) }))
                SecureField("Chave de transmissão", text: Binding(get: { settings.key }, set: { settings.editKey($0) }))
                Toggle("Salvar chave no Acesso às Chaves", isOn: Binding(get: { settings.document.rememberKey }, set: { settings.rememberKey($0) }))
                Text(settings.document.rememberKey ? "A chave é guardada automaticamente no Acesso às Chaves. Ela não é incluída no projeto nem nos presets." : "A chave será usada apenas nesta sessão. Ao desativar, a cópia salva por esta conexão é removida do Acesso às Chaves.").font(.caption).foregroundStyle(.secondary)
            }
            Section("YouTube") {
                Text("Use o servidor e a chave fornecidos pelo YouTube Studio. Título, descrição, capa, visibilidade e latência são configurados no YouTube.")
                Text("Salvar configurações não inicia a transmissão. Use Transmitir no estúdio quando estiver pronto.").font(.caption).foregroundStyle(.secondary)
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
    @StudioDismiss var dismiss
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
