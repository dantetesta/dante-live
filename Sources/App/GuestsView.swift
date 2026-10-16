import SwiftUI

struct GuestsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var guests: GuestModel
    @ObservedObject var studio: StudioModel
    @LegacyState private var showNetwork = false
    var body: some View {
        VStack(alignment: .leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("Traga alguém para a conversa").font(.title.bold())
                    Text("Até dois convidados pelo navegador. Você escolhe quando entram na cena.").foregroundStyle(.secondary)
                };Spacer();Image(systemName:"person.2.wave.2.fill").font(.largeTitle).foregroundStyle(.teal)
            }
            HStack(spacing:14) {
                step("1","Gere o convite","Um link pessoal para cada convidado.")
                step("2","Ele prepara os dispositivos","Nome, câmera, microfone e tela opcional.")
                step("3","Você coloca na cena","Depois controle fontes e mixer normalmente.")
            }
            ScrollView {
                VStack(spacing:12) {
                    if guests.invites.isEmpty {
                        VStack(spacing:12) { Image(systemName:"person.crop.circle.badge.plus").font(.system(size:42)).foregroundStyle(.teal);Text("Sua sala está vazia").font(.headline);Text("O convite não inicia uma transmissão.").foregroundStyle(.secondary) }.frame(maxWidth:.infinity).padding(35)
                    }
                    ForEach(guests.invites) { guest in
                        VStack(alignment:.leading,spacing:12) {
                            HStack { Image(systemName:"person.crop.circle.fill").font(.title);VStack(alignment:.leading) {Text(guest.name).font(.headline);Text(guest.status).font(.caption).foregroundStyle(.secondary)};Spacer();Button("Copiar convite") {guests.copy(guest)}.disabled(guests.link(guest)==nil) }
                            HStack {
                                Button(guest.admitted ? "Inserir nesta cena" : "Colocar na cena") {guests.admit(guest.id)}.buttonStyle(.borderedProminent).disabled(guest.peer==nil)
                                Button("Inserir tela") {guests.insertScreen(guest.id)}.disabled(guest.peer==nil)
                                Spacer();Button("Revogar convite",role:.destructive) {studio.confirm("Desconectar \(guest.name) e invalidar este convite?") {guests.revoke(guest.id)}}
                            }
                            Text("Câmera e microfone entram juntos. A tela é uma fonte separada; use o olho e o mute para controlar o que vai ao ar.").font(.caption).foregroundStyle(.secondary)
                        }.padding(16).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                    }
                }
            }.frame(minHeight:180,maxHeight:340)
            if let message=guests.message { Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            HStack { if guests.busy {ProgressView().controlSize(.small)};Button(guests.busy ? "Preparando link…" : "Convidar participante") {guests.createInvite()}.buttonStyle(.borderedProminent).disabled(guests.busy || guests.invites.count>=2);Spacer();Text(guests.hasTURN ? "TURN configurado nesta sessão" : "Conexão direta • TURN não configurado").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Conexão e privacidade",isExpanded:$showNetwork) {
                VStack(alignment:.leading,spacing:8) {
                    Text("O link temporário usa Cloudflare Quick Tunnel, um serviço de testes sem garantia de disponibilidade. O link deixa de funcionar ao encerrar a sala. A mídia usa WebRTC direto ou TURN; não passa pelo túnel HTTPS.").font(.caption)
                    Text("Algumas redes exigem TURN. Cole credenciais temporárias do seu provedor, nunca uma chave de administração. Elas ficam apenas na memória desta sessão e são entregues aos convidados autorizados.").font(.caption)
                    TextEditor(text:$guests.turnJSON).font(.system(.caption,design:.monospaced)).frame(height:65).border(Color.secondary.opacity(0.2)).accessibilityLabel("Servidores TURN em JSON").disabled(!guests.invites.isEmpty)
                    Text("Formato: [{\"urls\":[\"turns:servidor:5349\"],\"username\":\"…\",\"credential\":\"…\"}]").font(.caption2).foregroundStyle(.secondary)
                    Text("Convites valem 12 horas para a primeira entrada e aceitam um navegador. Use fones. O retorno usa as trilhas 5 e 6 para excluir a voz de cada convidado; mantenha o microfone do apresentador nessas trilhas.").font(.caption)
                }.padding(.top,8)
            }
            Divider()
            HStack { if guests.inUse { Button("Encerrar sala",role:.destructive) {studio.confirm("Desconectar todos os convidados e revogar os links?") {guests.stop()}} };Spacer();Button("Fechar") {dismiss()}.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width:850).frame(maxHeight:780)
    }
    private func step(_ number:String,_ title:String,_ detail:String)->some View {
        VStack(alignment:.leading,spacing:6){Text(number).font(.title2.bold()).foregroundStyle(.teal);Text(title).font(.callout.bold());Text(detail).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
    }
}
