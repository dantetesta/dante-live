import SwiftUI
import UniformTypeIdentifiers

struct GuestsView: View {
    @StudioDismiss private var dismiss
    @ObservedObject var guests: GuestModel
    @ObservedObject var studio: StudioModel
    @LegacyState private var showNetwork = false
    @LegacyState private var selectedTab = 0
    @LegacyState private var vpsToken = ""
    @LegacyState private var vpsError: String?
    @LegacyState private var importVPS = false
    var body: some View {
        VStack(alignment: .leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("Traga alguém para a conversa").font(.title.bold())
                    Text("Até dois convidados pelo navegador. Você escolhe quando entram na cena.").foregroundStyle(.secondary)
                };Spacer();Image(systemName:"person.2.wave.2.fill").font(.largeTitle).foregroundStyle(.teal)
            }
            Picker("Área",selection:$selectedTab) {
                Text("Participantes").tag(0)
                Text("Servidor TURN").tag(1)
            }.pickerStyle(.segmented)
            if selectedTab == 0 {
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
            HStack { if guests.busy {ProgressView().controlSize(.small)};Button(guests.busy ? "Preparando link…" : "Convidar participante") {guests.createInvite()}.buttonStyle(.borderedProminent).disabled(guests.busy || guests.invites.count>=2);Spacer();Text(guests.vpsEnabled ? "VPS para convidados ativa" : guests.hasTURN ? "Rota alternativa configurada" : "Conexão direta automática").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Conexão e privacidade",isExpanded:$showNetwork) {
                VStack(alignment:.leading,spacing:8) {
                    Text(guests.vpsEnabled ? "O convite usa a ponte HTTPS da sua VPS. A mídia usa WebRTC direto ou o servidor TURN quando a rede exige; não passa pelo link HTTPS." : "O link temporário usa Cloudflare Quick Tunnel, um serviço de testes sem garantia de disponibilidade. O link deixa de funcionar ao encerrar a sala. A mídia usa WebRTC direto ou TURN; não passa pelo túnel HTTPS.").font(.caption)
                    Text("Algumas redes exigem TURN. Cole credenciais temporárias do seu provedor, nunca uma chave de administração. Elas ficam apenas na memória desta sessão e são entregues aos convidados autorizados.").font(.caption)
                    TextEditor(text:$guests.turnJSON).font(.system(.caption,design:.monospaced)).frame(height:65).border(Color.secondary.opacity(0.2)).accessibilityLabel("Servidores TURN em JSON").disabled(!guests.invites.isEmpty)
                    Text("Formato: [{\"urls\":[\"turns:servidor:5349\"],\"username\":\"…\",\"credential\":\"…\"}]").font(.caption2).foregroundStyle(.secondary)
                    Text("Convites valem 12 horas para a primeira entrada e aceitam um navegador. Use fones. O retorno usa as trilhas 5 e 6 para excluir a voz de cada convidado; mantenha o microfone do apresentador nessas trilhas.").font(.caption)
                }.padding(.top,8)
            }
            } else { vpsSettings }
            Divider()
            HStack { if guests.inUse { Button("Encerrar sala",role:.destructive) {studio.confirm("Desconectar todos os convidados e revogar os links?") {guests.stop()}} };Spacer();Button("Fechar") {dismiss()}.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width:850).frame(maxHeight:780)
        .fileImporter(isPresented:$importVPS,allowedContentTypes:[.json]) { result in
            do {
                let url=try result.get()
                let access=url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try guests.importVPSProfile(Data(contentsOf:url))
                vpsToken="";vpsError=nil
            } catch { vpsError=error.localizedDescription }
        }
    }
    private var vpsSettings: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Sua infraestrutura para convidados").font(.title2.bold())
                Text("Configure uma VPS própria para manter o convite em um endereço estável e oferecer TURN quando a conexão direta falhar. Você controla a máquina e o custo. O Dante Live não precisa de acesso SSH.").foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:10) {
                    Text("Servidor").font(.headline)
                    TextField("IPv4 público da VPS",text:$guests.vpsAddress)
                        .textFieldStyle(.roundedBorder).disabled(guests.inUse)
                    HStack { Text("Porta HTTPS");TextField("443",value:$guests.vpsPort,format:.number).textFieldStyle(.roundedBorder).frame(width:100).disabled(guests.inUse);Text("O TURN usa 3478 e 5349 na VPS.").font(.caption).foregroundStyle(.secondary) }
                    SecureField(guests.hasVPSConfiguration ? "Token salvo no Acesso às Chaves" : "Token de conexão gerado na VPS",text:$vpsToken)
                        .textFieldStyle(.roundedBorder).disabled(guests.inUse)
                    Text("Cole apenas o token de conexão gerado pelo instalador da VPS. Nunca informe usuário ou senha SSH aqui.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Importar perfil da VPS…") { importVPS=true }.disabled(guests.inUse)
                        Button("Salvar e usar esta VPS") {
                            do { try guests.saveVPS(token:vpsToken);vpsToken="";vpsError=nil }
                            catch { vpsError=error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(guests.inUse || vpsToken.isEmpty)
                        Button("Testar conexão") { Task { await guests.testVPS() } }.disabled(!guests.hasVPSConfiguration)
                        if guests.hasVPSConfiguration { Button("Remover configuração",role:.destructive) { do { try guests.removeVPS();vpsError=nil } catch { vpsError=error.localizedDescription } }.disabled(guests.inUse) }
                    }
                    if let status=guests.vpsStatus { Text(status).font(.callout).foregroundStyle(.secondary) }
                    if let vpsError { Text(vpsError).font(.callout).foregroundStyle(.red) }
                }.padding(16).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:8) {
                    Text("Qual VPS escolher?").font(.headline)
                    Text("Para uma live com 1 ou 2 convidados, comece com 1 vCPU e 2 GB de RAM. Tráfego, bitrate e redes podem exigir mais; monitore CPU e transferência durante um teste real. Esta versão do Dante Live aceita até 2 convidados por sala.")
                    Text("Para 3 ou mais convidados em uma versão futura, comece a avaliar 2 vCPU e 4 GB de RAM e dimensione pela transferência medida. Memória e CPU sozinhas não garantem capacidade.")
                    Link("Abrir prompt de instalação para sua IA",destination:URL(string:"https://github.com/dantetesta/dante-live/blob/main/server/PROMPT-INSTALACAO.md")!)
                    Link("Criar VPS na DigitalOcean (link de afiliado)",destination:URL(string:"https://m.do.co/c/79bcb516176d")!)
                    Text("Você também pode usar outro provedor de VPS com Ubuntu 24.04 e IPv4 público.").font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minHeight:350,maxHeight:540)
    }
    private func step(_ number:String,_ title:String,_ detail:String)->some View {
        VStack(alignment:.leading,spacing:6){Text(number).font(.title2.bold()).foregroundStyle(.teal);Text(title).font(.callout.bold());Text(detail).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
    }
}
