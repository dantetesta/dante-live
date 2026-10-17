import SwiftUI
import AppKit

/// Broadcast metadata is separate from account credentials and encoder presets.
struct LivePreparationView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var youtube: YouTubeModel
    @ObservedObject var settings: LiveSettingsModel
    @LegacyState private var showingLibrary = false
    @LegacyState private var showingSchedule = false
    private var locked: Bool { model.active || model.preparingLive || model.countdown.remaining != nil || youtube.busy }
    private func draft<T>(_ path: WritableKeyPath<YouTubeDraft, T>) -> Binding<T> {
        Binding(get: { youtube.state.draft[keyPath: path] }, set: { value in youtube.editDraft { $0[keyPath: path] = value } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prepare sua próxima live").font(.title3.bold())
                    Text("Salve para escolher depois ou agende no YouTube.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingLibrary = true } label: { Label("Minhas lives", systemImage: "rectangle.grid.2x2") }
                    .disabled(youtube.account == nil || locked)
                Button { youtube.newDraft() } label: { Label("Nova live", systemImage: "plus") }
                    .disabled(youtube.account == nil || locked)
            }
            if youtube.account == nil {
                ContentUnavailableView {
                    Label("Conecte seu canal", systemImage: "person.crop.rectangle.badge.plus")
                } description: {
                    Text("Na guia Conta YouTube, importe a configuração Google e conecte o canal onde você vai transmitir.")
                } actions: {
                    Button("Conectar YouTube") { model.outputTab = "youtube" }.buttonStyle(.borderedProminent)
                }
            } else {
                HStack {
                    Picker("Canal", selection: Binding(get: { youtube.preferences.selectedAccount ?? "" }, set: { youtube.selectAccount($0) })) {
                        ForEach(youtube.preferences.accounts) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 360)
                    Spacer()
                    Label(youtube.draftSaveStatus, systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                }.disabled(locked)
                ScrollView {
                    if youtube.state.createdBroadcast != nil || youtube.state.selectedBroadcast != nil || youtube.state.creationUncertain {
                        existingLive
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 20, alignment: .top)], alignment: .leading, spacing: 18) {
                            details
                            preview
                        }.padding(2).disabled(locked)
                    }
                }
                if let message = youtube.message {
                    Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if youtube.busy { HStack { ProgressView().controlSize(.small); Text("Preparando no YouTube…").font(.callout) } }
                if youtube.canEditDraft {
                    Divider()
                    HStack(alignment: .center, spacing: 12) {
                        Text("Salvar não inicia a live. Quando estiver pronto, use Transmitir no estúdio.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { showingSchedule = true } label: { Label("Agendar…", systemImage: "calendar.badge.plus") }
                        Button("Salvar na lista") {
                            if youtube.saveDraftForLater() {
                                settings.edit({ $0.youtubeMode = true }, immediate: true)
                                showingLibrary = true
                            }
                        }.buttonStyle(.borderedProminent)
                    }.disabled(locked || youtube.state.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onDisappear { youtube.flush() }
        .sheet(isPresented: $showingLibrary) {
            YouTubeLibraryView(youtube: youtube, forTransmission: false) { showingLibrary = false }
        }
        .sheet(isPresented: $showingSchedule) {
            LiveScheduleView(youtube: youtube) {
                settings.edit({ $0.youtubeMode = true }, immediate: true)
                showingSchedule = false
                youtube.schedule()
            }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Dados da transmissão", systemImage: "text.bubble").font(.headline)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text("Título").font(.callout.bold()); Spacer(); Text("\(youtube.state.draft.title.count)/100").font(.caption).foregroundStyle(youtube.state.draft.title.count > 100 ? .red : .secondary) }
                TextField("Ex.: Uma conversa sobre criatividade", text: draft(\.title)).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Descrição").font(.callout.bold())
                TextEditor(text: draft(\.description)).font(.body).frame(height: 110).padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.25)))
                    .accessibilityLabel("Descrição da live")
            }
            Picker("Quem pode assistir", selection: draft(\.privacy)) {
                Text("Pública").tag("public"); Text("Não listada").tag("unlisted"); Text("Privada").tag("private")
            }
            Text(youtube.state.draft.privacy == "public" ? "Qualquer pessoa pode encontrar e assistir." : youtube.state.draft.privacy == "private" ? "Acesso restrito pelas configurações do YouTube." : "Quem tiver o link poderá assistir.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Conteúdo criado para crianças", isOn: draft(\.madeForKids))
            DisclosureGroup("Categoria, palavras-chave e latência") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Categoria", selection: draft(\.category)) {
                        Text("Pessoas e blogs").tag("22"); Text("Educação").tag("27"); Text("Ciência e tecnologia").tag("28"); Text("Entretenimento").tag("24"); Text("Jogos").tag("20"); Text("Música").tag("10"); Text("Notícias e política").tag("25")
                    }
                    TextField("Palavras-chave, separadas por vírgulas", text: draft(\.tags)).textFieldStyle(.roundedBorder)
                }.padding(.top, 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("Atraso para o público", selection: draft(\.latency)) {
                    Text("Ultrabaixo • conversa com o chat").tag("ultraLow")
                    Text("Baixo • equilíbrio").tag("low")
                    Text("Normal • maior buffer / 4K").tag("normal")
                }
                Text(youtube.state.draft.latency == "ultraLow" ? "Prioriza a interação. O YouTube ainda tem alguns segundos de atraso e precisa de conexão estável." : youtube.state.draft.latency == "low" ? "Equilibra interação e tolerância a oscilações da conexão." : "Mais tolerante a oscilações, com maior atraso. Use este modo para 4K.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Os convidados recebem o retorno direto do Dante, independente desta opção.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capa e apresentação").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.teal.opacity(0.08))
                if let file = youtube.thumbnailURL(youtube.state.draft.thumbnailFile), let image = NSImage(contentsOf: file) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    VStack(spacing: 8) { Image(systemName: "photo.badge.plus").font(.largeTitle); Text("Escolha a capa da sua live").font(.callout) }.foregroundStyle(.secondary)
                }
            }.aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Escolher capa…") { youtube.chooseThumbnail() }
                if youtube.state.draft.thumbnailFile != nil { Button("Remover") { youtube.editDraft { $0.thumbnailFile = nil } } }
            }
            Text("JPEG ou PNG, até 2 MB. Prefira uma imagem horizontal em 16:9.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(youtube.state.draft.title.isEmpty ? "O título da sua live aparece aqui" : youtube.state.draft.title).font(.headline).lineLimit(3)
            Text(youtube.account?.name ?? "").foregroundStyle(.secondary)
            Label(privacyName(youtube.state.draft.privacy), systemImage: "eye").font(.callout)
            Label("Sem horário marcado", systemImage: "play.rectangle").font(.callout).foregroundStyle(.secondary)
            Text("Salve para transmitir quando quiser. Para criar um link antecipado no YouTube, escolha Agendar.").font(.callout).foregroundStyle(.secondary)
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private var existingLive: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(youtube.state.creationUncertain ? "Confira a criação no YouTube" : "Esta live já tem um registro no YouTube", systemImage: youtube.state.creationUncertain ? "exclamationmark.triangle" : "calendar.badge.checkmark").font(.headline)
            Text(youtube.selectedBroadcast?.title ?? youtube.state.draft.title).font(.title3.bold())
            if let event = youtube.selectedBroadcast { LiveCover(url: event.thumbnailURL.flatMap(URL.init(string:))); Text(event.scheduleLabel()).foregroundStyle(.secondary) }
            Text("Para preparar outra transmissão, clique em Nova live. Para mudar uma live já publicada, use o YouTube Studio; seu link será preservado.").foregroundStyle(.secondary)
            HStack {
                Button("Preparar nova live") { youtube.newDraft() }.buttonStyle(.borderedProminent)
                Link("Abrir YouTube Studio", destination: URL(string: "https://studio.youtube.com")!)
                if youtube.state.selectedBroadcast == nil, youtube.state.createdBroadcast != nil {
                    Button("Concluir agendamento") { youtube.schedule() }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)).disabled(locked)
    }
}

struct LiveScheduleView: View {
    @ObservedObject var youtube: YouTubeModel
    var onSchedule: () -> Void
    @Environment(\.dismiss) private var dismiss
    @LegacyState private var date = Date().addingTimeInterval(3600)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Quando será sua live?", systemImage: "calendar").font(.title2.bold())
            Text(youtube.state.draft.title).font(.headline).lineLimit(2)
            HStack(alignment: .top, spacing: 24) {
                ScheduleCalendar(date: $date).frame(width: 260, height: 190)
                VStack(alignment: .leading, spacing: 14) {
                    DatePicker("Horário", selection: $date, displayedComponents: .hourAndMinute)
                    Text(date.formatted(date: .complete, time: .shortened)).font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("Fuso deste Mac: \(TimeZone.current.identifier)").font(.caption).foregroundStyle(.secondary)
                    Label(privacyName(youtube.state.draft.privacy), systemImage: "eye")
                    Text(youtube.account?.name ?? "").foregroundStyle(.secondary)
                }.frame(width: 240)
            }
            Text("Agendar cria o vídeo e o link no YouTube agora. No dia escolhido, abra Transmitir e selecione esta live. O envio não começa sozinho.").font(.callout).foregroundStyle(.secondary)
            if date <= Date() { Text("Escolha uma data e hora futuras.").foregroundStyle(.red) }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Agendar no YouTube") {
                    youtube.editDraft { $0.scheduledAt = date }
                    youtube.flush()
                    onSchedule()
                }.buttonStyle(.borderedProminent).disabled(date <= Date() || !youtube.canEditDraft)
            }
        }.padding(24).frame(width: 560).background(Color(nsColor: .windowBackgroundColor))
            .onAppear { date = max(youtube.state.draft.scheduledAt, Date().addingTimeInterval(300)) }
    }
}

/// AppKit provides the native month grid while SwiftUI owns the shared date/time value.
private struct ScheduleCalendar: NSViewRepresentable {
    @Binding var date: Date
    final class Coordinator: NSObject {
        var parent: ScheduleCalendar
        init(_ parent: ScheduleCalendar) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) {
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: parent.date)
            parent.date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: sender.dateValue) ?? sender.dateValue
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let view = NSDatePicker()
        view.datePickerStyle = .clockAndCalendar
        view.drawsBackground = true
        view.backgroundColor = .controlBackgroundColor
        view.textColor = .labelColor
        view.datePickerElements = [.yearMonthDay]
        view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:))
        view.minDate = Calendar.current.startOfDay(for: Date())
        return view
    }
    func updateNSView(_ view: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        view.dateValue = date
    }
}
