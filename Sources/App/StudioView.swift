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
            if let message = model.pendingUpdateMessage { Label(message, systemImage: "arrow.down.circle.fill").font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.orange.opacity(0.15)) }
            if !model.microphoneWarnings.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "mic.slash.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ATENÇÃO • MICROFONE SEM ÁUDIO").font(.headline)
                        Text(model.microphoneWarnings.joined(separator: ", ") + " • sem sinal há pelo menos 30 segundos. Confira bateria, conexão e dispositivo.")
                    }
                    Spacer()
                }.padding(14).foregroundStyle(.white).background(Color.red)
                .accessibilityElement(children: .combine)
            }
            Divider()
            HSplitView {
                if showScenes { sceneSidebar.frame(minWidth: 170, idealWidth: 205, maxWidth: 320) }
                else { collapsedSidebar(title: "Mostrar cenas", icon: "sidebar.left") { showScenes = true } }
                VSplitView {
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
                            Text(model.selectedName.isEmpty ? "Selecione uma fonte para editar" : model.selectedName).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if model.studioMode {
                                Button("Corte") { _ = model.command("scene.take", ["scene": model.sceneName, "transition": "cut"], undo: false) }
                                Button("Transição") { model.take() }.keyboardShortcut(.space, modifiers: []).buttonStyle(.borderedProminent)
                            }
                        }.padding(10)
                    }.frame(minWidth: 420, minHeight: 260)
                    HSplitView {
                        sourcePanel.frame(minWidth: 210)
                        MixerView(model: model).frame(minWidth: 220)
                    }.frame(minHeight: 280, idealHeight: 330)
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
        .sheet(isPresented: $model.showingAdd, onDismiss: {
            if !model.cameraSourceName.isEmpty { model.showingCamera = true }
        }) { AddSourceView(model: model) }
        .sheet(isPresented: $model.showingCamera, onDismiss: {
            model.cameraSourceName = ""; model.inspectorRevision += 1
        }) { CameraSetupView(model: model, sourceName: model.cameraSourceName) }
        .sheet(item: $model.pendingLive) { launch in LiveConfirmationView(model: model, launch: launch) }
        .sheet(isPresented: $model.showingLiveLibrary, onDismiss: { model.liveLibraryDismissed() }) {
            YouTubeLibraryView(youtube: model.youtube, forTransmission: true) { model.continueFromLiveLibrary() }
        }
        .sheet(isPresented: $model.showingGuests) { GuestsView(guests: model.guests, studio: model) }
        .sheet(isPresented: $model.showingOutput) { OutputSettingsView(model: model) }
        .sheet(isPresented: $model.showingProperties, onDismiss: { model.inspectorRevision += 1 }) {
            VStack(spacing: 0) {
                InspectorView(model: model, allowsSecondarySheets: false)
                Divider()
                HStack { Spacer(); Button("Fechar") { model.showingProperties = false }.keyboardShortcut(.cancelAction) }.padding(14)
            }.frame(width: 480, height: 650)
        }
        .sheet(isPresented: $model.showingFilters) { FilterView(model: model) }
        .alert("Dante Live", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("Entendi") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    var topBar: some View {
        HStack(spacing: 14) {
            ZStack { RoundedRectangle(cornerRadius: 9).fill(.teal.gradient); Image(systemName: "waveform.path").foregroundStyle(.white).font(.title3.bold()) }.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) { Text("DANTE LIVE").font(.headline.weight(.heavy)); Text("Estúdio de produção • \(appVersion)").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Toggle("Modo estúdio", isOn: Binding(get: { model.studioMode }, set: { model.setStudio($0) })).toggleStyle(.switch).controlSize(.small)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoCount == 0 || model.active || model.guests.inUse).help("Desfazer ⌘Z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(model.redoCount == 0 || model.active || model.guests.inUse).help("Refazer ⇧⌘Z")
            Button { model.showingGuests = true } label: { Image(systemName: "person.badge.plus") }.help("Convidar participantes")
            Button { model.showingOutput = true } label: { Image(systemName: "slider.horizontal.3") }.help("Configurações da live")

            Button {
                if model.streaming { model.confirm("Encerrar transmissão?") { model.endLive() } }
                else { model.beginLive() }
            } label: { Label(model.streaming ? "Encerrar live" : "Transmitir", systemImage: "antenna.radiowaves.left.and.right") }.buttonStyle(.borderedProminent).disabled(model.preparingLive || model.updateInstalling)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    private func collapsedSidebar(title: String, icon: String, action: @escaping () -> Void) -> some View {
        VStack { Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).help(title).accessibilityLabel(title).padding(.top, 14); Spacer() }
            .frame(width: 32).frame(maxHeight: .infinity)
    }
    var sceneSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("CENAS").font(.caption.weight(.bold)); Spacer(); Button { showScenes = false } label: { Image(systemName: "sidebar.left") }.help("Recolher cenas").accessibilityLabel("Recolher cenas"); Button { model.askName(title: "Nova cena") { _ = model.command("scene.create", ["name": $0]) } } label: { Image(systemName: "plus") }.help("Criar cena") }.padding(12)
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
            if model.items.isEmpty { ContentUnavailableView("Sua cena começa aqui", systemImage: "rectangle.stack.badge.plus", description: Text("Adicione uma imagem, câmera, tela ou outra fonte.")) }
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
