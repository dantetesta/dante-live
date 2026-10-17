import SwiftUI
import AppKit

struct YouTubeSettingsView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var youtube: YouTubeModel
    @ObservedObject var settings: LiveSettingsModel
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
            Section("Preparar sua transmissão") {
                Label("Título, descrição, capa e agendamento têm uma guia própria.", systemImage: "rectangle.and.pencil.and.ellipsis")
                Button("Ir para Preparar live") { model.outputTab = "broadcast" }.buttonStyle(.borderedProminent)
                Text("Conecte seu canal aqui. Depois, prepare quantas lives quiser e escolha uma delas ao clicar em Transmitir.").font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { youtube.loadClient() }.onDisappear { youtube.flush() }
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
            if let latency = launch.latency {
                LabeledContent("Atraso no YouTube", value: latency == "ultraLow" ? "Ultrabaixo" : latency == "low" ? "Baixo" : "Normal")
                if latency == "normal" { Text("Esta live usa um buffer maior no YouTube. Para conversar com o chat com menos atraso, escolha latência Ultrabaixa ao preparar a live.").font(.caption).foregroundStyle(.secondary) }
            }
            if launch.youtubeAccount == nil {
                Text("Com RTMP manual, título, capa, visibilidade e agendamento são definidos no serviço de destino. O Dante envia para a live vinculada à sua chave.").font(.callout).foregroundStyle(.secondary)
            } else if let id = launch.broadcastID, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { Link("Esta transmissão usará o vídeo já criado", destination: url) }
            else { Text("A confirmação cria a live no YouTube com estes dados. Depois da preparação, o vídeo começa após a contagem de 3 segundos.").font(.callout).foregroundStyle(.secondary) }
            Label("Após a preparação, você verá a contagem 3, 2, 1 antes de o envio começar.", systemImage: "timer").font(.callout).foregroundStyle(.secondary)
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
