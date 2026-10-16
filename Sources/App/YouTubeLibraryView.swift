import SwiftUI
import AppKit

extension YouTubeBroadcast {
    var scheduledDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: scheduledAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: scheduledAt)
    }
    func scheduleLabel(timeZone: TimeZone = .current) -> String {
        guard let date = scheduledDate else { return "Data não informada" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR"); formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, d 'de' MMM 'de' yyyy • HH:mm"
        return formatter.string(from: date)
    }
    var canTransmit: Bool { !["complete", "revoked", "live", "liveStarting"].contains(lifeCycle) }
    var statusLabel: String {
        switch lifeCycle {
        case "live", "liveStarting": "Ao vivo"
        case "complete": "Encerrada"
        case "revoked": "Indisponível"
        case "testing", "testStarting": "Em teste"
        default: "Agendada"
        }
    }
}

struct YouTubeLibraryView: View {
    @ObservedObject var youtube: YouTubeModel
    let forTransmission: Bool
    var onChoose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @LegacyState private var selection = ""
    @LegacyState private var query = ""
    @LegacyState private var showHidden = false
    private var localLives: [YouTubeSavedLive] {
        youtube.localLives.filter { query.isEmpty || $0.state.draft.title.localizedStandardContains(query) }
    }
    private var selectedLocal: YouTubeSavedLive? { youtube.localLives.first { "local:" + $0.id == selection } }
    private var events: [YouTubeBroadcast] {
        (showHidden ? youtube.broadcasts : youtube.visibleBroadcasts).filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            .sorted { ($0.scheduledDate ?? .distantFuture, $0.id) < ($1.scheduledDate ?? .distantFuture, $1.id) }
    }
    private var selectedEvent: YouTubeBroadcast? { youtube.broadcasts.first { $0.id == selection } }
    private var canContinue: Bool { !youtube.busy && youtube.account != nil && !youtube.hiddenBroadcastIDs.contains(selection) && (selectedLocal.map { youtube.canTransmitLocal($0) || !forTransmission } == true || selectedEvent?.canTransmit == true) }
    private var selectedTitle: String {
        if let local = selectedLocal { return local.state.draft.title.isEmpty ? "Preparação sem título" : local.state.draft.title }
        return selectedEvent?.title ?? "Escolha uma live"
    }
    private var initialSelection: String { youtube.state.selectedBroadcast ?? youtube.currentLiveID.map { "local:" + $0 } ?? "" }
    private var sheetSize: CGSize {
        let size = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        return CGSize(width: min(1000, size.width - 80), height: min(740, size.height - 100))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar pelo título da live", text: $query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Limpar busca") }
                Spacer()
                Button { youtube.refresh() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }.disabled(youtube.busy)
            }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 24).padding(.top, 18)
            if youtube.busy {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Atualizando lives do YouTube…") }.padding(.horizontal, 24).padding(.top, 12)
            } else if let message = youtube.message {
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 24).padding(.top, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Salvas neste Mac • sem horário marcado").font(.headline)
                        Text("\(localLives.count)").foregroundStyle(.secondary)
                    }
                    Text("Escolha uma preparação salva. O vídeo será criado no YouTube após sua confirmação. Para preparar outra, use a guia Preparar live nas configurações.").font(.callout).foregroundStyle(.secondary)
                    if localLives.isEmpty {
                        Text("Nenhuma preparação encontrada. Crie uma na guia Preparar live.").foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(localLives) { item in
                            localCard(item)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Lives criadas e agendadas").font(.headline)
                        Text("\(events.count)").foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Mostrar ocultas (\(youtube.hiddenBroadcastIDs.count))", isOn: $showHidden).toggleStyle(.checkbox)
                    }
                    Text("Use o menu ••• de uma live para ocultá-la somente neste Mac. Ela continuará no YouTube.")
                        .font(.caption).foregroundStyle(.secondary)
                    if events.isEmpty {
                        ContentUnavailableView(youtube.busy ? "Consultando o canal" : query.isEmpty ? "Nenhuma live na lista" : "Nenhuma live com esse título", systemImage: "calendar", description: Text(query.isEmpty ? "As preparações salvas neste Mac aparecem abaixo. As lives encerradas não aparecem aqui." : "Tente buscar outro título."))
                            .frame(maxWidth: .infinity).frame(height: 190)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                            ForEach(events) { event in
                                let hidden = youtube.hiddenBroadcastIDs.contains(event.id)
                                VStack(alignment: .leading, spacing: 8) {
                                    BroadcastCard(event: event, selected: selection == event.id) { selection = event.id }
                                        .disabled(youtube.busy || !event.canTransmit || hidden)
                                    HStack {
                                        if hidden { Label("Oculta neste Mac", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Menu { visibilityAction(event) } label: { Image(systemName: "ellipsis") }
                                            .menuStyle(.borderlessButton).fixedSize()
                                            .accessibilityLabel("Opções de \(event.title)")
                                    }
                                }.contextMenu { visibilityAction(event) }
                            }
                        }
                    }
                    Text("Horários no fuso deste Mac (\(TimeZone.current.identifier)). Selecionar uma live preserva o vídeo e o link já criados no YouTube.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTitle).font(.headline).lineLimit(1)
                    Text(forTransmission ? "Você ainda vai confirmar antes de entrar ao vivo." : "A seleção ficará salva para a próxima transmissão.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(forTransmission ? "Continuar" : selectedLocal != nil ? "Editar preparação" : "Usar esta seleção") {
                    guard canContinue else { return }
                    let saved = selectedLocal.map { youtube.selectLocalLive($0.id) } ?? youtube.selectBroadcast(selection)
                    if saved { onChoose() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canContinue)
            }.controlSize(.large).padding(24)
        }.frame(width: sheetSize.width, height: sheetSize.height)
            .background(Color(nsColor: .windowBackgroundColor)).tint(.teal)
            .onAppear { selection = initialSelection; youtube.refresh() }
            .onChange(of: youtube.preferences.selectedAccount) { _, _ in selection = initialSelection }
    }
    private func localCard(_ item: YouTubeSavedLive) -> some View {
        let selected = selection == "local:" + item.id
        let valid = youtube.canTransmitLocal(item)
        return Button { selection = "local:" + item.id } label: {
            VStack(alignment: .leading, spacing: 12) {
                LiveCover(url: youtube.thumbnailURL(item.state.draft.thumbnailFile)).frame(maxWidth: .infinity)
                Text(item.state.draft.title.isEmpty ? "Preparação sem título" : item.state.draft.title).font(.headline).lineLimit(2).frame(height: 42, alignment: .topLeading)
                Label(privacyName(item.state.draft.privacy), systemImage: "eye").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Label(item.state.creationUncertain ? "Conferir criação no YouTube" : valid ? "Pronta para transmitir" : "Complete os dados", systemImage: item.state.creationUncertain ? "exclamationmark.triangle" : valid ? "play.circle" : "pencil").font(.caption)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.teal.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.teal : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).disabled(youtube.busy || (forTransmission && !valid))
            .accessibilityLabel("\(item.state.draft.title.isEmpty ? "Preparação sem título" : item.state.draft.title), salva neste Mac, \(privacyName(item.state.draft.privacy))")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func visibilityAction(_ event: YouTubeBroadcast) -> some View {
        let hidden = youtube.hiddenBroadcastIDs.contains(event.id)
        return Button {
            if youtube.setBroadcastHidden(event.id, hidden: !hidden), !hidden, selection == event.id { selection = "" }
        } label: {
            Label(hidden ? "Mostrar novamente neste Mac" : "Ocultar neste Mac", systemImage: hidden ? "eye" : "eye.slash")
        }.disabled(!youtube.canOrganizeLibrary)
    }
    private var header: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(forTransmission ? "Qual live vamos transmitir?" : "Minhas lives no YouTube").font(.system(size: 25, weight: .bold))
                Text("Encontre sua live pela capa, pelo título e pelo horário.").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Canal", selection: Binding(get: { youtube.preferences.selectedAccount ?? "" }, set: { youtube.selectAccount($0) })) {
                ForEach(youtube.preferences.accounts) { Text($0.name).tag($0.id) }
            }.frame(maxWidth: 260).disabled(youtube.busy)
        }.padding(24)
    }
}

private struct BroadcastCard: View {
    let event: YouTubeBroadcast
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    ZStack {
                        Color.teal.opacity(0.08)
                        AsyncImage(url: event.thumbnailURL.flatMap(URL.init(string:))) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Image(systemName: "play.rectangle.fill").font(.system(size: 42)).foregroundStyle(.teal.opacity(0.6)) }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                }.frame(height: 150)
                    .overlay(alignment: .topLeading) { Text(event.statusLabel).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(.regularMaterial, in: Capsule()).padding(10) }
                    .overlay(alignment: .topTrailing) { if selected { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white, .teal).padding(10) } }
                VStack(alignment: .leading, spacing: 10) {
                    Text(event.title).font(.system(size: 16, weight: .semibold)).lineLimit(2).frame(height: 42, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading)
                    Label(event.scheduleLabel(), systemImage: "calendar").font(.callout).foregroundStyle(.secondary)
                    Label(privacyName(event.privacy), systemImage: event.privacy == "public" ? "globe" : event.privacy == "private" ? "lock.fill" : "link").font(.caption).foregroundStyle(.secondary)
                }.padding(16)
            }.foregroundStyle(.primary)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.teal : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).accessibilityLabel("\(event.title), \(event.scheduleLabel()), \(privacyName(event.privacy)), \(event.statusLabel)")
            .accessibilityHint("Selecionar esta live").accessibilityAddTraits(selected ? .isSelected : [])
    }
}
