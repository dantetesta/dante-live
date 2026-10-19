import SwiftUI

/// Room controls stay outside the ordinary layer list; components remain real
/// scene items and can still be selected and manipulated on the canvas.
struct ParticipantsPanel: View {
    @ObservedObject var guests: GuestModel
    @ObservedObject var studio: StudioModel
    var body: some View {
        if !guests.invites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PARTICIPANTES").font(.caption.weight(.bold))
                    Spacer()
                    Button { studio.showingGuests = true } label: { Image(systemName: "person.badge.plus") }
                        .help("Gerenciar convites").accessibilityLabel("Gerenciar convites")
                }.padding(12)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(guests.invites) { guest in
                            ParticipantCard(guests: guests, studio: studio, guest: guest)
                        }
                    }.padding(.horizontal, 10).padding(.bottom, 10)
                }
            }.frame(minHeight: 180, idealHeight: 310, maxHeight: 420)
        }
    }
}

private struct ParticipantCard: View {
    @ObservedObject var guests: GuestModel
    @ObservedObject var studio: StudioModel
    let guest: GuestInvite
    @LegacyState private var destination = ""
    @LegacyState private var showingAudio = false
    private var scene: String? { guests.scene(for: guest) }
    private var target: String { studio.scenes.contains { $0.string("name") == destination } ? destination : scene ?? studio.sceneName }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(participantColor(guest.slot))
                Text(guest.firstName).font(.callout.weight(.semibold)).lineLimit(2).help(guest.name).accessibilityLabel(guest.name)
                Spacer(minLength: 0)
            }
            Text(guest.status).font(.caption2).foregroundStyle(guest.status == "Conectado" ? Color.green : .secondary)
            Picker("Cena", selection: Binding(get: { target }, set: { destination = $0 })) {
                ForEach(studio.scenes, id: \.entryName) { Text($0.string("name")).tag($0.string("name")) }
            }.controlSize(.small)
            if scene != target || scene == nil {
                Button(scene == nil ? "Adicionar à cena" : "Mover para esta cena") {
                    let selectedTarget = target
                    let action = { guests.admit(guest.id, to: selectedTarget) }
                    if studio.active { studio.confirm("Adicionar \(guest.name) à cena \(selectedTarget)? A mudança pode aparecer na live.", action: action) }
                    else { action() }
                }.disabled(guest.peer == nil).controlSize(.small)
            }
            if let scene {
                component("Câmera", source: guest.camera, icon: "video", scene: scene, available: guest.cameraEnabled, screen: false)
                if let label = guests.item(guest.nameOverlay, in: scene) {
                    HStack {
                        Button { guests.select(guest.nameOverlay, guest: guest) } label: { Label("Nome na cena", systemImage: "textformat") }.buttonStyle(.plain)
                        Spacer()
                        Button { guests.toggleName(guest.id) } label: {
                            Image(systemName: label.flag("visible") ? "eye" : "eye.slash")
                                .foregroundStyle(label.flag("visible") ? Color.teal : .secondary)
                        }.buttonStyle(.plain).help(label.flag("visible") ? "Ocultar nome na cena" : "Mostrar nome na cena")
                            .accessibilityLabel("\(label.flag("visible") ? "Ocultar" : "Mostrar") nome de \(guest.name)")
                    }.font(.caption)
                    Text("Selecione para mover e estilizar nas Propriedades.").font(.caption2).foregroundStyle(.secondary)
                }
                component("Tela", source: guest.screen, icon: "display", scene: scene, available: guest.screenEnabled, screen: true)
                if let mic = guests.item(guest.microphone, in: scene) {
                    HStack {
                        Button { guests.select(guest.microphone, guest: guest) } label: { Label("Microfone",systemImage:"mic") }.buttonStyle(.plain)
                        Spacer()
                        Button { guests.toggleMicrophone(guest.id) } label: {
                            Image(systemName:mic.flag("muted") ? "mic.slash.fill" : "mic.fill").foregroundStyle(mic.flag("muted") ? Color.red : .green)
                        }.buttonStyle(.plain).help(mic.flag("muted") ? "Ativar microfone" : "Silenciar microfone")
                            .accessibilityLabel("\(mic.flag("muted") ? "Ativar" : "Silenciar") microfone de \(guest.name)")
                    }.font(.caption)
                    HStack(spacing: 6) {
                        Image(systemName:"speaker.wave.1").font(.caption2).foregroundStyle(.secondary)
                        Slider(value:Binding(get:{AudioBoostScale.position(for:mic.number("volume",1))},set:{_ = studio.command("audio.set",["name":guest.microphone,"volume":AudioBoostScale.volume(for:$0)],undo:false)}),in:0...1)
                            .tint(mic.number("volume",1)>1.01 ? .orange : .teal)
                            .accessibilityLabel("Volume de \(guest.name)")
                            .accessibilityValue("\(Int((mic.number("volume",1)*100).rounded())) por cento\(mic.number("volume",1)>1.01 ? ", reforço ativo" : "")")
                        VStack(alignment:.trailing,spacing:0) {
                            Text("\(Int((mic.number("volume",1)*100).rounded()))%").font(.caption2.monospacedDigit())
                            if mic.number("volume",1)>1.01 { Text("Reforço").font(.system(size:9,weight:.semibold)).foregroundStyle(.orange) }
                        }.frame(width:48,alignment:.trailing)
                    }
                    Text("100% é o nível normal; acima disso, o reforço aumenta a voz com proteção de pico. Se soar áspero, reduza.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Ouvir neste Mac",isOn:Binding(get:{mic.number("monitoring")==2},set:{_ = studio.command("audio.set",["name":guest.microphone,"monitoring":$0 ? 2 : 0],undo:false)})).font(.caption2).toggleStyle(.checkbox)
                    Button { showingAudio = true } label: { Label("Tratamento da voz", systemImage: "waveform") }.font(.caption2)
                        .popover(isPresented: $showingAudio) { GuestVoiceControls(studio: studio, guest: guest) }
                    if !guest.microphoneEnabled { Text("Microfone desligado pelo convidado").font(.caption2).foregroundStyle(.orange) }
                }
                Menu {
                    Button("Retirar desta cena") { studio.confirm("Retirar \(guest.name) da cena, mantendo a conexão?") { guests.removeFromScene(guest.id) } }
                    Button("Desconectar",role:.destructive) { studio.confirm("Desconectar \(guest.name)?") { guests.revoke(guest.id) } }
                } label: { Text("Mais opções").font(.caption2) }.menuStyle(.borderlessButton)
            }
        }.padding(10).background(participantColor(guest.slot).opacity(0.10),in:RoundedRectangle(cornerRadius:10)).overlay(alignment:.leading){RoundedRectangle(cornerRadius:2).fill(participantColor(guest.slot)).frame(width:3).padding(.vertical,10)}
    }
    private func component(_ title:String,source:String,icon:String,scene:String,available:Bool,screen:Bool)->some View {
        let item=guests.item(source,in:scene), visible=item?.flag("visible") ?? false
        return VStack(alignment:.leading,spacing:3) {
            HStack {
                Button { guests.select(source,guest:guest) } label: { Label(title,systemImage:icon) }.buttonStyle(.plain).disabled(item == nil)
                Spacer()
                Button { guests.toggleVideo(guest.id,screen:screen) } label: { Image(systemName:visible ? "eye" : "eye.slash").foregroundStyle(visible ? Color.teal : .secondary) }
                    .buttonStyle(.plain).disabled(item == nil && !available)
                    .help(visible ? "Ocultar na cena" : "Mostrar na cena").accessibilityLabel("\(visible ? "Ocultar" : "Mostrar") \(title) de \(guest.name)")
            }.font(.caption)
            if !available { Text(screen ? "Não está compartilhando" : "Desligada pelo convidado").font(.caption2).foregroundStyle(.secondary) }
            else if item?.flag("awaitingVideo") == true { Text("Aguardando imagem…").font(.caption2).foregroundStyle(.orange) }
        }
    }
}

private struct GuestVoiceControls: View {
    @ObservedObject var studio: StudioModel
    let guest: GuestInvite
    @LegacyState private var method = "rnnoise"
    @LegacyState private var strength = 30.0
    @LegacyState private var availableMethods: [String] = []
    private let filterName = "Dante • Redução de ruído"
    private var filter: [String: Any]? { studio.scenes.flatMap { $0.array("items") }.first { $0.string("name") == guest.microphone }?.array("filters").first { $0.string("name") == filterName } }
    private var isEnabled: Bool { filter?.flag("enabled") == true }
    private var available: Bool { studio.catalog.array("filters").contains { $0.string("id") == "noise_suppress_filter_v2" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Voz de \(guest.firstName)").font(.headline)
            Toggle("Reduzir ruído de fundo", isOn: Binding(get: { isEnabled }, set: { enabled in
                if filter != nil { _ = studio.command("filter.update", ["name": guest.microphone, "filter": filterName, "settings": [:], "enabled": enabled], undo: false) }
                else if enabled { _ = studio.command("filter.add", ["name": guest.microphone, "type": "noise_suppress_filter_v2", "filter": filterName, "settings": values], undo: false) }
                reload()
            })).disabled(!available)
            if available {
                if availableMethods.count > 1 {
                    Picker("Tratamento", selection: Binding(get: { method }, set: { method = $0; apply() })) {
                        ForEach(availableMethods, id: \.self) { value in Text(value == "rnnoise" ? "Automático • voz" : "Manual • intensidade").tag(value) }
                    }.disabled(!isEnabled)
                }
                if method == "speex" {
                    HStack { Text("Redução"); Spacer(); Text("\(Int(strength)) dB").monospacedDigit() }
                    Slider(value: $strength, in: 0...60, step: 1, onEditingChanged: { editing in if !editing { apply() } })
                        .disabled(!isEnabled).accessibilityLabel("Intensidade da redução de ruído")
                }
                Text(method == "rnnoise" ? "Diminui ruídos contínuos, como ventilador. O modo automático não tem ajuste de intensidade." : "Aumente aos poucos. Uma redução muito forte pode cortar partes da voz.").font(.caption).foregroundStyle(.secondary)
                Text("O ajuste vale para a live e para os outros participantes. Desative para comparar.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Redução de ruído indisponível neste motor.").font(.caption).foregroundStyle(.secondary) }
        }.padding(18).frame(width: 300).onAppear { reload() }
    }
    private var values: [String: Any] { ["method": method, "suppress_level": -Int(strength)] }
    private func apply() {
        guard filter != nil else { return }
        _ = studio.command("filter.update", ["name": guest.microphone, "filter": filterName, "settings": values], undo: false)
        reload()
    }
    private func reload() {
        guard let engine = studio.engine else { return }
        let result = filter == nil
            ? jsonObject(copied(dante_engine_type_properties(engine, "noise_suppress_filter_v2")))
            : jsonObject(copied(dante_engine_filter_properties(engine, guest.microphone, filterName)))
        let settings = result.object("settings")
        method = settings.string("method", "rnnoise"); strength = min(60, max(0, -settings.number("suppress_level", -30)))
        let properties = result.array("properties")
        availableMethods = properties.first { $0.string("name") == "method" }?.array("items").compactMap { $0["value"] as? String } ?? []
    }
}

struct SceneParticipantSplit<Content: View>: View {
    @ObservedObject var guests: GuestModel
    let studio: StudioModel
    @ViewBuilder let scenes: () -> Content
    var body: some View {
        if guests.invites.isEmpty { scenes() }
        else {
            VSplitView {
                scenes().frame(minHeight: 100)
                ParticipantsPanel(guests: guests, studio: studio)
            }
        }
    }
}

func participantColor(_ slot: Int) -> Color { slot % 2 == 0 ? .blue : .pink }
