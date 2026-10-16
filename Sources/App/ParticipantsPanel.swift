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
                        Slider(value:Binding(get:{mic.number("volume",1)},set:{_ = studio.command("audio.set",["name":guest.microphone,"volume":$0],undo:false)}),in:0...2)
                            .accessibilityLabel("Volume de \(guest.name)")
                        Text("\(Int(mic.number("volume",1)*100))%").font(.caption2.monospacedDigit()).frame(width:34)
                    }
                    Toggle("Ouvir neste Mac",isOn:Binding(get:{mic.number("monitoring")==2},set:{_ = studio.command("audio.set",["name":guest.microphone,"monitoring":$0 ? 2 : 0],undo:false)})).font(.caption2).toggleStyle(.checkbox)
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
