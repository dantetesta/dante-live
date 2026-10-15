import SwiftUI
import AppKit

struct StudioView: View {
    @ObservedObject var model: StudioModel
    var body: some View {
        VStack(spacing: 0) {
            topBar
            CountdownBanner(countdown: model.countdown)
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
                sceneSidebar.frame(minWidth: 170, idealWidth: 205, maxWidth: 320)
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
                    }.frame(minHeight: 150, idealHeight: 215)
                }
                InspectorView(model: model).frame(minWidth: 240, idealWidth: 290, maxWidth: 420)
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
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoCount == 0 || model.active).help("Desfazer ⌘Z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(model.redoCount == 0 || model.active).help("Refazer ⇧⌘Z")
            Button { model.showingOutput = true } label: { Image(systemName: "slider.horizontal.3") }.help("Configurações da live")

            Button {
                if model.streaming { model.confirm("Encerrar transmissão?") { _ = model.command("stream.stop", undo: false) } }
                else { model.beginLive() }
            } label: { Label(model.streaming ? "Encerrar live" : "Transmitir", systemImage: "antenna.radiowaves.left.and.right") }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    var sceneSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("CENAS").font(.caption.weight(.bold)); Spacer(); Button { model.askName(title: "Nova cena") { _ = model.command("scene.create", ["name": $0]) } } label: { Image(systemName: "plus") }.help("Criar cena") }.padding(12)
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

struct MixerView: View {
    @ObservedObject var model: StudioModel
    var channels: [[String: Any]] { model.state.array("audio").isEmpty ? model.items.filter { $0.flag("audio") } : model.state.array("audio") }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("MIXER DE ÁUDIO").font(.caption.weight(.bold)); Spacer(); Image(systemName: "waveform").foregroundStyle(.secondary) }.padding(12)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(channels, id: \.entryName) { channel in
                        VStack(spacing: 5) {
                            HStack { Text(channel.string("name")).lineLimit(1); Spacer(); Text(channel.flag("muted") ? "MUDO" : String(format: "%.1f dB", 20 * log10(max(0.00001, channel.number("volume", 1))))).font(.caption.monospaced()) }
                            Toggle("Alertar se ficar sem sinal por 30 s", isOn: Binding(get: { model.watchesMicrophone(channel) }, set: { model.setMicrophoneWatch(channel, enabled: $0) }))
                                .toggleStyle(.checkbox).font(.caption)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 2).fill(channel.number("level", -60) > -3 ? .orange : .green).frame(width: geo.size.width * min(1, max(0, (channel.number("level", -60) + 60) / 60)))
                                }
                            }.frame(height: 5).accessibilityLabel("Nível de áudio \(channel.number("level", -60)) decibéis")
                            HStack {
                                Slider(value: Binding(get: { channel.number("volume", 1) }, set: { _ = model.command("audio.set", ["name": channel.string("name"), "volume": $0], undo: false) }), in: 0...2).accessibilityLabel("Volume de \(channel.string("name"))")
                                Button { _ = model.command("audio.set", ["name": channel.string("name"), "muted": !channel.flag("muted")], undo: false) } label: { Image(systemName: channel.flag("muted") ? "speaker.slash.fill" : "speaker.wave.2") }.buttonStyle(.plain)
                            }
                        }
                    }
                    if channels.isEmpty { Text("Adicione um microfone ou uma fonte com áudio para usar o mixer.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 20) }
                }.padding(.horizontal, 12)
            }
        }
    }
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
