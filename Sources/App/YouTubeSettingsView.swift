import SwiftUI
import AppKit

struct YouTubeSettingsView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var youtube: YouTubeModel
    @ObservedObject var settings: LiveSettingsModel
    @LegacyState private var showingLibrary = false
    @LegacyState private var showingManualError = false
    @LegacyState private var manualError = ""

    private func openIntegrationManual() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Help/youtube-integration.html"),
              FileManager.default.isReadableFile(atPath: url.path) else {
            manualError = "O arquivo do manual está ausente ou não pode ser lido nesta cópia do Dante Live. Instale uma versão que inclua o manual. Você também pode acessar o tutorial em vídeo abaixo."
            showingManualError = true
            return
        }
        if !NSWorkspace.shared.open(url) {
            manualError = "O manual está incluído nesta cópia, mas o macOS não conseguiu abri-lo. Confira o aplicativo padrão para arquivos HTML ou consulte o tutorial em vídeo abaixo."
            showingManualError = true
        }
    }
    private func draft<T>(_ path: WritableKeyPath<YouTubeDraft, T>) -> Binding<T> {
        Binding(get: { youtube.state.draft[keyPath: path] }, set: { value in youtube.editDraft { $0[keyPath: path] = value } })
    }
    var body: some View {
        Form {
            Section("Conectar o YouTube") {
                Toggle("Usar YouTube ao clicar em Transmitir", isOn: Binding(get: { settings.document.youtubeMode == true }, set: { value in settings.edit({ $0.youtubeMode = value }, immediate: true) }))
                if !youtube.clientConfigured {
                    Text("Para agendar e configurar lives, importe o JSON OAuth de um aplicativo para computador com a YouTube Data API habilitada no Google Cloud.").font(.callout)
                }
                HStack {
                    Button(youtube.clientConfigured ? "Trocar configuração Google…" : "Importar configuração Google…") { youtube.importClient() }
                    Button("Conectar canal…") { youtube.connect() }.disabled(!youtube.clientConfigured)
                    Link("Configurar no Google Cloud", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                }.disabled(youtube.busy || model.active)
                Button(action: openIntegrationManual) {
                    Label("Manual de integração com YouTube", systemImage: "book.closed")
                }
                .help("Abre o passo a passo no navegador. O manual está incluído no aplicativo e pode ser consultado offline.")
                if !youtube.preferences.accounts.isEmpty {
                    Picker("Canal", selection: Binding(get: { youtube.preferences.selectedAccount ?? "" }, set: { youtube.selectAccount($0) })) {
                        ForEach(youtube.preferences.accounts) { Text($0.name).tag($0.id) }
                    }.disabled(youtube.busy || model.active)
                    Button("Desconectar deste Mac…") { model.confirm("Remover esta conta do Dante? As lives no YouTube serão preservadas.") { youtube.disconnect() } }.disabled(youtube.busy || model.active)
                }
                if youtube.busy { HStack { ProgressView().controlSize(.small); Text("Consultando o YouTube…"); if youtube.canCancel { Button("Cancelar") { youtube.cancel() } } } }
                if let message = youtube.message { Text(message).font(.callout).textSelection(.enabled) }
            }
            if youtube.account != nil {
                Section("Suas lives no YouTube") {
                    HStack(alignment: .top, spacing: 18) {
                        if let event = youtube.selectedBroadcast {
                            LiveCover(url: event.thumbnailURL.flatMap(URL.init(string:)))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.title).font(.headline)
                                Label(event.scheduleLabel(), systemImage: "calendar").font(.callout)
                                Text(privacyName(event.privacy)).foregroundStyle(.secondary)
                                if let url = event.watchURL { Link("Abrir esta live no YouTube", destination: url) }
                            }
                        } else {
                            Image(systemName: "calendar.badge.play").font(.largeTitle).foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(youtube.state.selectedBroadcast == nil ? "Prepare sua próxima live" : "Você tem uma live selecionada").font(.headline)
                                Text("Veja suas lives em cartões com capa, título e horário.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button("Ver minhas lives…") { showingLibrary = true }.buttonStyle(.borderedProminent)
                        Button("Criar outro rascunho…") { model.confirm("Criar outro rascunho? As lives já criadas continuam no YouTube.") { youtube.newDraft() } }
                    }
                    Text("No estúdio, Transmitir abre essa lista antes da confirmação. Edite lives já criadas no YouTube Studio.").font(.caption).foregroundStyle(.secondary)
                }.disabled(youtube.busy || model.active)
                if youtube.state.selectedBroadcast == nil {
                    Section("Dados da próxima live • salvos neste Mac") {
                        TextField("Título", text: draft(\.title))
                        TextField("Descrição", text: draft(\.description), axis: .vertical).lineLimit(3...6)
                        TextField("Palavras-chave separadas por vírgulas", text: draft(\.tags))
                        Picker("Visibilidade", selection: draft(\.privacy)) {
                            Text("Não listada").tag("unlisted"); Text("Privada").tag("private"); Text("Pública").tag("public")
                        }
                        Picker("Categoria", selection: draft(\.category)) {
                            Text("Pessoas e blogs").tag("22"); Text("Educação").tag("27"); Text("Ciência e tecnologia").tag("28"); Text("Entretenimento").tag("24"); Text("Jogos").tag("20"); Text("Música").tag("10"); Text("Notícias e política").tag("25")
                        }
                        Toggle("Conteúdo criado para crianças", isOn: draft(\.madeForKids))
                        Picker("Latência no YouTube", selection: draft(\.latency)) {
                            Text("Normal").tag("normal"); Text("Baixa").tag("low"); Text("Ultrabaixa").tag("ultraLow")
                        }
                        Text("Para 4K, use latência normal. A disponibilidade final depende do YouTube.").font(.caption).foregroundStyle(.secondary)
                        HStack { LiveCover(url: youtube.thumbnailURL(youtube.state.draft.thumbnailFile)); Button("Escolher capa…") { youtube.chooseThumbnail() }; if youtube.state.draft.thumbnailFile != nil { Button("Remover capa") { youtube.editDraft { $0.thumbnailFile = nil } } } }
                        Text("Sem agendar: feche as configurações e clique em Transmitir. A live será criada após sua confirmação.").font(.caption).foregroundStyle(.secondary)
                    }.disabled(youtube.busy || model.active)
                    Section("Agendar no YouTube") {
                        DatePicker("Data e hora", selection: draft(\.scheduledAt), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        Button("Criar live agendada no YouTube…") {
                            model.confirm("Criar “\(youtube.state.draft.title)” no canal \(youtube.account?.name ?? "") como \(privacyName(youtube.state.draft.privacy)) em \(youtube.state.draft.scheduledAt.formatted())? Isso cria o vídeo e o link no YouTube, sem iniciar o envio de vídeo.") { youtube.schedule() }
                        }
                        Text("O agendamento cria o link agora. O Dante não inicia sozinho na data marcada; escolha essa live e clique em Transmitir quando estiver pronto.").font(.caption).foregroundStyle(.secondary)
                    }.disabled(youtube.busy || model.active)
                }
            }
        }.formStyle(.grouped).onAppear { youtube.loadClient() }.onDisappear { youtube.flush() }
            .sheet(isPresented: $showingLibrary) {
                YouTubeLibraryView(youtube: youtube, forTransmission: false) { showingLibrary = false }
            }
            .alert("Não foi possível abrir o manual", isPresented: $showingManualError) {
                Button("Assistir ao tutorial") { NSWorkspace.shared.open(URL(string: "https://youtu.be/WHGy0IJvG5Y")!) }
                Button("OK", role: .cancel) { }
            } message: {
                Text(manualError)
            }
    }
}
func privacyName(_ value: String) -> String {
    switch value { case "public": "Pública"; case "private": "Privada"; default: "Não listada" }
}
struct LiveCover: View {
    var url: URL?
    var body: some View {
        Group {
            if let url, url.isFileURL, let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit() }
            else if let url { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "photo") } }
            else { Label("Sem capa", systemImage: "photo").foregroundStyle(.secondary) }
        }.frame(width: 160, height: 90).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
struct LiveConfirmationView: View {
    @ObservedObject var model: StudioModel
    let launch: LiveLaunch
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tudo pronto para entrar ao vivo?").font(.title2.bold())
            HStack(spacing: 16) { LiveCover(url: launch.thumbnailURL); VStack(alignment: .leading, spacing: 6) { Text(launch.title).font(.headline); Text(launch.channel); if let privacy = launch.privacy { Text(privacyName(privacy)).foregroundStyle(.secondary) } } }
            LabeledContent("Servidor", value: launch.server)
            LabeledContent("Chave", value: "•••••••• • protegida")
            if launch.youtubeAccount == nil {
                Text("Com RTMP manual, título, capa, visibilidade e agendamento são definidos no serviço de destino. O Dante envia para a live vinculada à sua chave.").font(.callout).foregroundStyle(.secondary)
            } else if let id = launch.broadcastID, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { Link("Esta transmissão usará o vídeo já criado", destination: url) }
            else { Text("A confirmação cria a live no YouTube com estes dados. Depois da preparação, o vídeo começa após a contagem de 3 segundos.").font(.callout).foregroundStyle(.secondary) }
            HStack { Button("Cancelar") { model.pendingLive = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Confirmar e transmitir") { model.confirmLive(launch) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 560)
    }
}

struct YouTubeStatusBanner: View {
    @ObservedObject var youtube: YouTubeModel
    var body: some View {
        if let message = youtube.message, message.hasPrefix("Enviando vídeo, mas") || message.hasPrefix("O YouTube ainda") || message.hasPrefix("O envio foi parado") {
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout)
                Spacer()
                Link("Conferir no YouTube Studio", destination: URL(string: "https://studio.youtube.com")!)
            }.padding(12).background(Color.orange.opacity(0.15))
        }
    }
}
