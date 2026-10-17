import SwiftUI
import AppKit

/// Broadcast metadata is separate from account credentials and encoder presets.
struct LivePreparationView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var youtube: YouTubeModel
    @ObservedObject var settings: LiveSettingsModel
    @LegacyState private var showingLibrary = false
    @LegacyState private var transmitAfterLibrary = false
    @LegacyState private var showingSchedule = false
    @LegacyState private var editorPage = "content"
    @FocusState private var titleFocused: Bool
    private var locked: Bool { model.active || model.preparingLive || model.countdown.remaining != nil || youtube.busy }
    private var missingTitle: Bool { youtube.state.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var titleTooLong: Bool { youtube.state.draft.title.count > 100 }
    private func draft<T>(_ path: WritableKeyPath<YouTubeDraft, T>) -> Binding<T> {
        Binding(get: { youtube.state.draft[keyPath: path] }, set: { value in youtube.editDraft { $0[keyPath: path] = value } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if youtube.account == nil {
                ContentUnavailableView {
                    Label("Conecte seu canal", systemImage: "person.crop.rectangle.badge.plus")
                } description: {
                    Text("Na guia Conta YouTube, importe a configuração Google e conecte o canal onde você vai transmitir.")
                } actions: {
                    Button("Conectar YouTube") { model.outputTab = "youtube" }.buttonStyle(.borderedProminent)
                }
            } else {
                channelBar
                GeometryReader { geometry in
                    ScrollView {
                        if youtube.state.createdBroadcast != nil || youtube.state.selectedBroadcast != nil || youtube.state.creationUncertain {
                            existingLive
                        } else {
                            // Explicit columns keep the cover from consuming half of the form.
                            // At compact widths all fields remain reachable in one scroll area.
                            if geometry.size.width >= 760 {
                                HStack(alignment: .top, spacing: 20) {
                                    editor.frame(maxWidth: .infinity)
                                    preview.frame(width: 280)
                                }
                            } else {
                                VStack(spacing: 20) { editor; preview }
                            }
                        }
                    }.scrollIndicators(.visible).disabled(locked)
                }
                if let message = youtube.message {
                    Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if youtube.busy { HStack { ProgressView().controlSize(.small); Text("Preparando no YouTube…").font(.callout) } }
                if youtube.canEditDraft { actions }
            }
        }
        .font(.system(size: 14))
        .onDisappear { youtube.flush() }
        .studioPanel(isPresented: $showingLibrary, title: "Minhas lives", onDismiss: {
            if transmitAfterLibrary { transmitAfterLibrary = false; model.transmitSelectedFromSettings() }
        }) {
            YouTubeLibraryView(youtube: youtube, forTransmission: false, onTransmit: {
                transmitAfterLibrary = true; showingLibrary = false
            }) { showingLibrary = false }
        }
        .studioPanel(isPresented: $showingSchedule, title: "Agendar live") {
            LiveScheduleView(youtube: youtube) {
                settings.edit({ $0.youtubeMode = true }, immediate: true)
                showingSchedule = false
                youtube.schedule()
            }
        }
    }
    private var channelBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { channel; Spacer(minLength: 12); libraryActions }
            VStack(alignment: .leading, spacing: 12) { channel; libraryActions }
        }.disabled(locked)
    }
    private var channel: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle.fill").font(.system(size: 22)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("CANAL DA TRANSMISSÃO").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Canal da transmissão", selection: Binding(get: { youtube.preferences.selectedAccount ?? "" }, set: { youtube.selectAccount($0) })) {
                    ForEach(youtube.preferences.accounts) { Text($0.name).tag($0.id) }
                }.labelsHidden().pickerStyle(.menu).fixedSize().frame(maxWidth: 300, alignment: .leading)
            }
        }
    }
    private var libraryActions: some View {
        HStack(spacing: 10) {
            Button { showingLibrary = true } label: { Label("Minhas lives", systemImage: "rectangle.grid.2x2") }
            Button { youtube.newDraft(); editorPage = "content"; titleFocused = true } label: { Label("Nova live", systemImage: "plus") }
        }.controlSize(.large)
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                editorTab("Conteúdo", id: "content", icon: "text.alignleft")
                editorTab("Público e interação", id: "audience", icon: "person.2")
            }.padding(4).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            if editorPage == "content" { details } else { publication }
        }
    }
    private func editorTab(_ title: String, id: String, icon: String) -> some View {
        let selected = editorPage == id
        return Button { editorPage = id } label: {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Sobre a live", subtitle: "O que seu público vai assistir?", icon: "text.alignleft")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Título da live").fontWeight(.semibold)
                    Spacer()
                    Text("\(youtube.state.draft.title.count)/100").font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(titleTooLong ? .red : .secondary)
                }
                TextField("Dê um título à sua transmissão", text: draft(\.title), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 16)).lineLimit(1...3)
                    .padding(12).frame(minHeight: 48, alignment: .leading)
                    .background(fieldBackground)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(titleFocused ? Color.accentColor : .secondary.opacity(0.25), lineWidth: titleFocused ? 2 : 1))
                    .focused($titleFocused).accessibilityLabel("Título da live")
                if titleTooLong { Text("Use até 100 caracteres no título.").font(.caption).foregroundStyle(.red) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Descrição").fontWeight(.semibold); Text("Opcional").font(.caption).foregroundStyle(.secondary) }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: draft(\.description)).font(.system(size: 14))
                        .scrollContentBackground(.hidden).padding(8).frame(height: 138)
                        .accessibilityLabel("Descrição da live")
                    if youtube.state.draft.description.isEmpty {
                        Text("Conte o assunto, inclua links e apresente seus convidados.")
                            .foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.top, 12)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.background(fieldBackground).overlay(fieldBorder)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Categoria").fontWeight(.medium)
                        Picker("Categoria", selection: draft(\.category)) {
                            Text("Pessoas e blogs").tag("22"); Text("Educação").tag("27"); Text("Ciência e tecnologia").tag("28"); Text("Entretenimento").tag("24"); Text("Jogos").tag("20"); Text("Música").tag("10"); Text("Notícias e política").tag("25")
                        }.labelsHidden().controlSize(.large)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Palavras-chave").fontWeight(.medium)
                        TextField("Ex.: tecnologia, entrevista, criatividade", text: draft(\.tags))
                            .textFieldStyle(.plain).padding(12).background(fieldBackground).overlay(fieldBorder)
                            .accessibilityLabel("Palavras-chave")
                        Text("Separe as palavras por vírgulas.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            } label: { Text("Categoria e palavras-chave").fontWeight(.medium) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground)
    }
    private var publication: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Público e interação", subtitle: "Escolha quem pode assistir e o atraso da transmissão.", icon: "person.2")
            VStack(alignment: .leading, spacing: 8) {
                Text("Quem pode assistir?").fontWeight(.semibold)
                HStack(spacing: 8) {
                    visibility("Pública", value: "public", icon: "globe")
                    visibility("Não listada", value: "unlisted", icon: "link")
                    visibility("Privada", value: "private", icon: "lock")
                }
                Text(youtube.state.draft.privacy == "public" ? "Qualquer pessoa pode encontrar e assistir." : youtube.state.draft.privacy == "private" ? "Acesso restrito pelas configurações do YouTube." : "Só quem tiver o link poderá assistir.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle(isOn: draft(\.madeForKids)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conteúdo criado para crianças").fontWeight(.medium)
                    Text("Ative se esta live for feita para o público infantil.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).controlSize(.small)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Atraso para o público").fontWeight(.semibold)
                Picker("Atraso para o público", selection: draft(\.latency)) {
                    Text("Ultrabaixo • interação com o chat").tag("ultraLow")
                    Text("Baixo • equilíbrio").tag("low")
                    Text("Normal • maior tolerância / 4K").tag("normal")
                }.labelsHidden().controlSize(.large)
                Text(youtube.state.draft.latency == "ultraLow" ? "Para conversar com o chat. Ainda há alguns segundos de atraso e a conexão precisa ser estável." : youtube.state.draft.latency == "low" ? "Equilibra interação e tolerância a oscilações da conexão." : "Mais tolerante a oscilações, com maior atraso. Use este modo para 4K.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("O retorno dos convidados é direto pelo Dante.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground)
    }
    private func visibility(_ name: String, value: String, icon: String) -> some View {
        let selected = youtube.state.draft.privacy == value
        return Button { youtube.editDraft { $0.privacy = value } } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 18))
                Text(name).font(.system(size: 12, weight: .semibold))
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.2), lineWidth: selected ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityValue(selected ? "Selecionada" : "Não selecionada")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Capa da live", subtitle: "Veja como ela vai aparecer na sua lista.", icon: "photo")
            Button { youtube.chooseThumbnail() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.07))
                    if let file = youtube.thumbnailURL(youtube.state.draft.thumbnailFile), let image = NSImage(contentsOf: file) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 28, weight: .light))
                            Text("Adicionar capa").font(.system(size: 14, weight: .semibold))
                            Text("Clique para escolher uma imagem").font(.system(size: 11))
                        }.foregroundStyle(.secondary)
                    }
                }.aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: youtube.state.draft.thumbnailFile == nil ? [5, 4] : [])))
            }.buttonStyle(.plain).accessibilityLabel(youtube.state.draft.thumbnailFile == nil ? "Adicionar capa da live" : "Trocar capa da live")
            if youtube.state.draft.thumbnailFile != nil {
                HStack {
                    Button("Trocar capa…") { youtube.chooseThumbnail() }
                    Spacer()
                    Button("Remover", role: .destructive) { youtube.editDraft { $0.thumbnailFile = nil } }
                }
            }
            Text("JPEG ou PNG • até 2 MB\nFormato recomendado: horizontal, 16:9.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Text(missingTitle ? "Sua próxima live" : youtube.state.draft.title).font(.system(size: 18, weight: .semibold)).lineLimit(3)
            Text(youtube.account?.name ?? "").font(.system(size: 13)).foregroundStyle(.secondary)
            Label(privacyName(youtube.state.draft.privacy), systemImage: "eye").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Text("Salvar guarda esta preparação no app. Agendar cria o vídeo e o link no YouTube para a data escolhida.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground)
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { saveStatus; Spacer(minLength: 12); actionButtons }
                VStack(alignment: .leading, spacing: 12) { saveStatus; actionButtons }
            }
        }
    }
    private var saveStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(youtube.draftSaveStatus, systemImage: "internaldrive").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(missingTitle ? "Preencha o título para salvar ou agendar." : "A transmissão só começa pelo botão Transmitir no estúdio.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { showingSchedule = true } label: { Label("Agendar…", systemImage: "calendar.badge.plus") }
            Button {
                if youtube.saveDraftForLater() {
                    settings.edit({ $0.youtubeMode = true }, immediate: true)
                    showingLibrary = true
                }
            } label: { Label("Salvar para transmitir", systemImage: "checkmark") }
                .buttonStyle(.borderedProminent)
        }.controlSize(.large).disabled(locked || missingTitle || titleTooLong)
    }
    private func sectionHeading(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.teal).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private var fieldBackground: some View { RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)) }
    private var fieldBorder: some View { RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.25)) }
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.12)))
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
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground).disabled(locked)
    }
}

struct LiveScheduleView: View {
    @ObservedObject var youtube: YouTubeModel
    var onSchedule: () -> Void
    @StudioDismiss private var dismiss
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
