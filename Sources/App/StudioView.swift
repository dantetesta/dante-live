import SwiftUI
import AppKit

struct StudioView: View {
    @ObservedObject var model: StudioModel
    @AppStorage("DanteLive.showScenesSidebar") private var showScenes = true
    @AppStorage("DanteLive.showPropertiesSidebar") private var showProperties = true
    var body: some View {
        VStack(spacing: 0) {
            topBar
            CountdownBanner(countdown: model.countdown)
            YouTubeStatusBanner(youtube: model.youtube)
            if model.streaming { LiveShareBanner(youtube: model.youtube) }
            if let message = model.pendingUpdateMessage { Label(message, systemImage: "arrow.down.circle.fill").font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.orange.opacity(0.15)) }
            if !model.microphoneWarnings.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "mic.slash.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ATENÇÃO • MICROFONE SEM ÁUDIO").font(.headline)
                        Text(model.microphoneWarnings.joined(separator: ", ") + " • sem sinal há pelo menos 30 segundos. Confira bateria, conexão e dispositivo.")
                    }
                    Spacer()
                    Button { model.dismissMicrophoneWarnings() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .help("Dispensar este aviso até o sinal voltar e falhar novamente")
                        .accessibilityLabel("Fechar aviso de microfone sem áudio")
                }.padding(14).foregroundStyle(.white).background(Color.red)
                .accessibilityElement(children: .combine)
            }
            Divider()
            HSplitView {
                if showScenes { sceneSidebar.frame(minWidth: 170, idealWidth: 205, maxWidth: 320) }
                else { collapsedSidebar(title: "Mostrar cenas", icon: "sidebar.left") { showScenes = true } }
                CanvasPanelSplit {
                    VStack(spacing: 0) {
                        HStack {
                            Label(model.studioMode ? "PRÉVIA" : "CANVAS", systemImage: "rectangle.inset.filled")
                            Text(model.sceneName).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(model.canvasWidth)) × \(Int(model.canvasHeight))").monospacedDigit().foregroundStyle(.secondary)
                        }.font(.caption.weight(.semibold)).padding(12)
                        HStack(spacing: 1) {
                            CanvasView(model: model)
                            if model.studioMode { CanvasView(model: model, program: true) }
                        }
                        HStack {
                            Text(model.selectedName.isEmpty ? "Selecione uma fonte para editar" : model.guests.displayName(for:model.selectedName)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if model.studioMode {
                                Button("Corte") { _ = model.command("scene.take", ["scene": model.sceneName, "transition": "cut"], undo: false) }
                                Button("Transição") { model.take() }.keyboardShortcut(.space, modifiers: []).buttonStyle(.borderedProminent)
                            }
                        }.padding(10)
                    }.frame(minWidth: 420, maxHeight: .infinity)
                } controls: {
                    HSplitView {
                        sourcePanel.frame(minWidth: 210)
                        MixerView(model: model).frame(minWidth: 220)
                    }.frame(maxHeight: .infinity)
                }
                if showProperties { InspectorView(model: model, onCollapse: { showProperties = false }).frame(minWidth: 240, idealWidth: 290, maxWidth: 420) }
                else { collapsedSidebar(title: "Mostrar propriedades", icon: "sidebar.right") { showProperties = true } }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 1030, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
        .overlay(alignment: .bottomTrailing) {
            if model.guests.chatOpen {
                GuestRoomChatView(guests: model.guests).padding(22)
            }
        }
        .studioPanel(isPresented: $model.showingAdd, title: "Adicionar à cena", onDismiss: {
            if !model.cameraSourceName.isEmpty { model.showingCamera = true }
        }) { AddSourceView(model: model) }
        .studioPanel(isPresented: $model.showingProfiles, title: "Perfis de produção") { ProductionProfilesView(model: model) }
        .studioPanel(isPresented: $model.showingCamera, title: "Configurar câmera", onDismiss: {
            model.cameraSourceName = ""; model.inspectorRevision += 1
        }) { CameraSetupView(model: model, sourceName: model.cameraSourceName) }
        .studioPanel(item: $model.pendingLive, title: "Confirmar transmissão") { launch in LiveConfirmationView(model: model, launch: launch) }
        .studioPanel(isPresented: $model.showingLiveLibrary, title: "Minhas lives", onDismiss: { model.liveLibraryDismissed() }) {
            YouTubeLibraryView(youtube: model.youtube, forTransmission: true) { model.continueFromLiveLibrary() }
        }
        .studioPanel(isPresented: $model.showingChat, title: "Chat e destaques") { ChatControlView(studio: model, chat: model.youtube.chat) }
        .studioPanel(isPresented: $model.showingGuests, title: "Participantes") { GuestsView(guests: model.guests, studio: model) }
        .studioPanel(isPresented: $model.showingOutput, title: "Configurações da live", onDismiss: { model.liveLibraryDismissed() }) { OutputSettingsView(model: model) }
        .studioPanel(isPresented: $model.showingProperties, title: "Propriedades", onDismiss: { model.inspectorRevision += 1 }) {
            VStack(spacing: 0) {
                InspectorView(model: model)
                Divider()
                HStack { Spacer(); Button("Fechar") { model.showingProperties = false }.keyboardShortcut(.cancelAction) }.padding(14)
            }.frame(width: 480, height: 650)
        }
        .studioPanel(isPresented: $model.showingFilters, title: "Filtros") { FilterView(model: model) }
        .alert("Dante Live", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("Entendi") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    var topBar: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().interpolation(.high).scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) { Text("DANTE LIVE").font(.headline.weight(.heavy)); Text("Estúdio de produção • \(appVersion)").font(.caption2).foregroundStyle(.secondary) }
            Menu {
                ForEach(model.profiles.sorted(by: { $0.lastOpened > $1.lastOpened })) { profile in
                    Button {
                        model.selectProfile(profile.id)
                    } label: {
                        if profile.id == model.selectedProfileID { Label(profile.name, systemImage: "checkmark") }
                        else { Text(profile.name) }
                    }
                }
                Divider()
                Button("Novo perfil…", systemImage: "plus") { model.askName(title: "Novo perfil de produção") { model.createProfile(name: $0) } }
                Button("Gerenciar perfis…", systemImage: "square.stack.3d.up") { model.showingProfiles = true }
            } label: {
                Label(model.selectedProfileName, systemImage: "square.stack.3d.up")
                    .lineLimit(1)
                    .frame(maxWidth: 190)
            }
            .disabled(!model.canSwitchProfile)
            .help("Trocar o conjunto de cenas. O último perfil usado abre automaticamente.")
            Spacer()
            Toggle("Modo estúdio", isOn: Binding(get: { model.studioMode }, set: { model.setStudio($0) })).toggleStyle(.switch).controlSize(.small)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoCount == 0 || model.active || model.guests.inUse).help("Desfazer ⌘Z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(model.redoCount == 0 || model.active || model.guests.inUse).help("Refazer ⇧⌘Z")
            Button { model.showingChat = true } label: { Image(systemName: "bubble.left.and.bubble.right") }.help("Chat e Super Chats do YouTube")
            Button { model.showingGuests = true } label: { Image(systemName: "person.badge.plus") }.help("Convidar participantes")
            Button { model.guests.chatOpen.toggle() } label: {
                Label(model.guests.unreadChatCount > 0 ? "Conversa (\(model.guests.unreadChatCount))" : "Conversa", systemImage: "bubble.left.and.text.bubble.right")
            }.help("Conversar com os participantes fora da transmissão")
            Button { model.showingOutput = true } label: { Image(systemName: "slider.horizontal.3") }.help("Configurações da live")

            Button {
                if model.streaming { model.confirmEndLive() }
                else { model.beginLive() }
            } label: { Label(model.streaming ? "Encerrar live" : "Transmitir", systemImage: "antenna.radiowaves.left.and.right") }.buttonStyle(.borderedProminent).disabled(model.preparingLive || model.updateInstalling)
        }.padding(.horizontal, 16).padding(.vertical, 12)
        .overlay {
            GeometryReader { geometry in
                if geometry.size.width >= 1550 {
                    PartnerCarouselView()
                        .frame(width: 400, height: 55)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
    }
    private func collapsedSidebar(title: String, icon: String, action: @escaping () -> Void) -> some View {
        VStack { Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).help(title).accessibilityLabel(title).padding(.top, 14); Spacer() }
            .frame(width: 32).frame(maxHeight: .infinity)
    }
    var sceneSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("CENAS").font(.caption.weight(.bold)); Spacer(); Button { showScenes = false } label: { Image(systemName: "sidebar.left") }.help("Recolher cenas").accessibilityLabel("Recolher cenas"); Button { model.askName(title: "Nova cena") { _ = model.command("scene.create", ["name": $0]) } } label: { Image(systemName: "plus") }.help("Criar cena") }.padding(12)
            SceneParticipantSplit(guests: model.guests, studio: model) {
            List {
                ForEach(Array(model.scenes.enumerated()), id: \.offset) { index, scene in
                    Button { model.selectScene(scene.string("name")) } label: {
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", index + 1)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(scene.string("name")).lineLimit(2)
                            Spacer(minLength: 0)
                            if scene.string("name") == model.state.string("programScene") { Circle().fill(.red).frame(width: 6, height: 6) }
                        }.padding(.vertical, 7).padding(.horizontal, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(scene.string("name") == model.sceneName ? Color.teal.opacity(0.16) : Color.clear)
                        .contextMenu {
                            Button("Renomear") { model.askName(title: "Renomear cena", initial: scene.string("name")) { _ = model.command("scene.rename", ["scene": scene.string("name"), "name": $0]) } }
                            Button("Duplicar") { model.askName(title: "Duplicar cena", initial: scene.string("name") + " cópia") { _ = model.command("scene.duplicate", ["scene": scene.string("name"), "name": $0]) } }
                            Button("Mover para cima") { _ = model.command("scene.order", ["scene": scene.string("name"), "index": max(0, index - 1)]) }
                            Button("Mover para baixo") { _ = model.command("scene.order", ["scene": scene.string("name"), "index": min(model.scenes.count - 1, index + 1)]) }
                            Divider()
                            Button("Excluir", role: .destructive) { model.confirm("Excluir esta cena?") { _ = model.command("scene.delete", ["scene": scene.string("name")]) } }
                        }
                }
            }.listStyle(.sidebar)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Coleção de cenas", systemImage: "square.stack.3d.up").font(.caption.weight(.semibold))
                HStack { Button("Abrir…") { model.importProject() }; Button("Exportar…") { model.exportProject() } }.controlSize(.small)
                Text(model.preserveFailedProject ? "Salvamento pausado: exporte sua recuperação" : "Salvamento automático local").font(.caption2).foregroundStyle(model.preserveFailedProject ? .orange : .secondary)
            }.padding(12)
        }
    }
    var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FONTES").font(.caption.weight(.bold)); Spacer()
                Button { model.showingAdd = true } label: { Image(systemName: "plus") }.help("Adicionar fonte")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }.disabled(model.selected == nil).help("Remover fonte")
            }.padding(12)
            if model.listedSources.isEmpty { ContentUnavailableView("Sua cena começa aqui", systemImage: "rectangle.stack.badge.plus", description: Text(model.items.isEmpty ? "Adicione uma imagem, câmera, tela ou outra fonte." : "Os convidados estão no painel Participantes, abaixo das cenas.")) }
            else { SourceListView(model: model) }
        }
    }
    var statusBar: some View {
        HStack(spacing: 16) {
            Circle().fill(model.engine == nil ? Color.red : Color.green).frame(width: 6, height: 6)
            Text(model.notice).lineLimit(1)
            Spacer()
            if model.streaming { Label(model.streamStatus, systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.red).monospacedDigit() }
            Text(String(format: "%.1f FPS", model.state.object("stats").number("activeFPS"))).monospacedDigit()
            Text("Render: \(Int(model.state.object("stats").number("renderSkipped"))) perdidos").monospacedDigit()
            Text(model.state.string("backend", "libobs"))
        }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 8)
    }
}

func iconForSource(_ type: String) -> String {
    if ["dante_youtube_chat", "dante_superchat"].contains(type) { return "text.bubble" }
    if type.contains("audio") { return "mic" }
    if type.contains("capture") { return type.contains("screen") || type.contains("display") || type.contains("window") ? "display" : "video" }
    if type.contains("image") { return "photo" }
    if type.contains("text") { return "textformat" }
    if type.contains("ffmpeg") { return "film" }
    return "square.on.square"
}

struct CountdownBanner: View {
    @ObservedObject var countdown: LiveCountdown
    var body: some View {
        if let remaining = countdown.remaining {
            HStack {
                Text("A live começa em \(remaining)…").font(.title2.bold()).monospacedDigit()
                Spacer()
                Button("Cancelar início") { countdown.cancel() }
            }.padding(16).background(Color.teal.opacity(0.15))
        }
    }
}

struct LiveShareBanner: View {
    @ObservedObject var youtube: YouTubeModel
    @LegacyState private var copied = false
    var body: some View {
        if let live = youtube.liveShare {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill").font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.title).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 8) {
                        Link(live.url.absoluteString, destination: live.url).lineLimit(1)
                        if live.privacy == "private" { Text("Privada • acesso restrito").foregroundStyle(.orange) }
                        else if !youtube.remoteLive { Text("Aguardando YouTube").foregroundStyle(.secondary) }
                    }.font(.caption)
                }
                Spacer(minLength: 4)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(live.url.absoluteString, forType: .string)
                } label: { Label(copied ? "Link copiado" : "Copiar link da live", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .accessibilityLabel("Copiar link da live \(live.title)")
                    .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { copied = false } } }
            }.padding(.horizontal, 16).padding(.vertical, 10).background(Color.teal.opacity(0.08))
            .onChange(of: live.url) { _, _ in copied = false }
        }
    }
}
