import AppKit
import Security

@MainActor struct GuestInvite: Identifiable {
    let id = UUID()
    let token: String
    let slot: Int
    let created = Date()
    var name: String
    var client: String?
    var lastSeen = Date()
    var peer: DanteGuestPeer?
    var status = "Aguardando convidado"
    var negotiating = false
    var admitted = false
    var savedNames: [String] = []
    var names: [String] { let current=peer?.sourceNames ?? [];return current.count==3 ? current : savedNames }
    var camera: String { names.count==3 ? names[0] : "Convidado \(id.uuidString.prefix(6)) • câmera" }
    var screen: String { names.count==3 ? names[1] : "Convidado \(id.uuidString.prefix(6)) • tela" }
    var microphone: String { names.count==3 ? names[2] : "Convidado \(id.uuidString.prefix(6)) • microfone" }
}

@MainActor
final class GuestModel: ObservableObject {
    @Published private(set) var invites: [GuestInvite] = []
    @Published private(set) var busy = false
    @Published private(set) var publicURL: URL?
    @Published var message: String?
    @Published var turnJSON = ""
    @Published var showing = false
    private weak var studio: StudioModel?
    private var server: GuestHTTPServer?
    private var tunnel: Process?
    private var pipe: Pipe?
    private var tunnelOutput = ""
    private var timer: Timer?
    private var generation = UUID()
    var inUse: Bool { busy || !invites.isEmpty }
    var hasTURN: Bool { (try? iceServers()).map { $0.count > 1 } ?? false }
    init(studio: StudioModel) { self.studio = studio }

    static func token() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw StudioError.message("Não foi possível gerar um convite seguro.") }
        return bytes.map { String(format:"%02x",$0) }.joined()
    }
    func iceServers() throws -> [[String: Any]] {
        var ice: [[String: Any]] = [["urls":["stun:stun.cloudflare.com:3478"]]]
        if !turnJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = turnJSON.data(using: .utf8),data.count < 8192,
                  let entries = try? JSONSerialization.jsonObject(with:data) as? [[String: Any]],(1...4).contains(entries.count) else { throw StudioError.message("Informe uma lista JSON de servidores TURN com credenciais temporárias.") }
            for entry in entries {
                let urls = entry["urls"] as? [String] ?? (entry["urls"] as? String).map { [$0] } ?? []
                guard !urls.isEmpty,urls.count <= 8,urls.allSatisfy({ ($0.hasPrefix("turn:") || $0.hasPrefix("turns:")) && !$0.contains("\n") && $0.count < 1024 }),
                      let username=entry["username"] as? String,!username.isEmpty,
                      let credential=entry["credential"] as? String,!credential.isEmpty else { throw StudioError.message("Cada servidor TURN precisa de URL, usuário e credencial temporária.") }
                ice.append(["urls":urls,"username":username,"credential":credential])
            }
        }
        return ice
    }
    func createInvite() {
        guard !busy, invites.count < 2, studio?.engine != nil, studio?.updateInstalling == false else { return }
        busy=true;message=nil
        Task { @MainActor in
            defer { busy=false }
            do {
                _ = try iceServers()
                if server == nil { try await startServer() }
                if publicURL == nil { try await startTunnel() }
                try makeInvite()
            } catch { message=error.localizedDescription;if invites.isEmpty { stop() } }
        }
    }
    @discardableResult func makeInvite() throws -> GuestInvite {
        guard let slot=(0...1).first(where:{value in !invites.contains{$0.slot==value}}) else { throw StudioError.message("A sala aceita até dois convidados.") }
        let invite=GuestInvite(token:try Self.token(),slot:slot,name:"Convidado \(slot+1)");invites.append(invite)
        if timer == nil { timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } } }
        return invite
    }
    func startServer(resources: URL? = nil) async throws {
        let root = resources ?? Bundle.main.resourceURL!.appendingPathComponent("GuestWeb")
        let server = GuestHTTPServer(resources:root)
        server.api = { [weak self] path, token, payload, reply in self?.handle(path,token,payload,reply) }
        self.server=server;try await server.start()
    }
    var localURL: URL? { server.flatMap { URL(string:"http://127.0.0.1:\($0.port)") } }
    private func startTunnel() async throws {
        guard let server else { throw StudioError.message("Sala local indisponível.") }
        let executable=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cloudflared")
        guard FileManager.default.isExecutableFile(atPath:executable.path) else { throw StudioError.message("A ponte de convites não está instalada. Reinstale o aplicativo oficial.") }
        let process=Process(), output=Pipe(), id=UUID();generation=id;tunnelOutput=""
        process.executableURL=executable
        process.arguments=["tunnel","--no-autoupdate","--config","/dev/null","--protocol","http2","--grace-period","1s","--metrics","127.0.0.1:0","--management-diagnostics=false","--url","http://127.0.0.1:\(server.port)"]
        process.environment=["PATH":"/usr/bin:/bin:/usr/sbin:/sbin","TMPDIR":NSTemporaryDirectory()]
        process.standardOutput=output;process.standardError=output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data=handle.availableData
            guard !data.isEmpty else { return }
            let text=String(decoding:data,as:UTF8.self)
            Task { @MainActor in
                guard let self,self.generation==id else { return }
                self.tunnelOutput=String((self.tunnelOutput+text).suffix(4096))
                if let range=self.tunnelOutput.range(of:"https://[a-z0-9-]+\\.trycloudflare\\.com",options:.regularExpression),let url=URL(string:String(self.tunnelOutput[range])) {
                    self.publicURL=url;self.server?.publicHost=url.host
                }
            }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor in
            guard let self,self.generation==id else { return }
            self.publicURL=nil;self.message="A ponte de convites desconectou. Encerre a sala e gere novos convites para reconectar.";self.pipe?.fileHandleForReading.readabilityHandler=nil
        } }
        tunnel=process;pipe=output;try process.run()
        for _ in 0..<150 {
            if publicURL != nil { return }
            guard process.isRunning else { break }
            try await Task.sleep(for:.milliseconds(200))
        }
        throw StudioError.message("Não foi possível gerar o link público. Confira a internet e tente novamente.")
    }
    func link(_ invite: GuestInvite) -> String? { publicURL.map { $0.absoluteString+"/#"+invite.token } }
    func copy(_ invite: GuestInvite) { guard let link=link(invite) else { return };NSPasteboard.general.clearContents();NSPasteboard.general.setString(link,forType:.string);message="Convite copiado. Envie somente para a pessoa convidada." }
    func admit(_ id: UUID) {
        guard let i=invites.firstIndex(where:{$0.id==id}),invites[i].peer != nil,let studio else { return }
        let guest=invites[i]
        for name in [guest.camera,guest.microphone] {
            if !studio.items.contains(where:{$0.string("name")==name}) { guard studio.command("source.reuse",["scene":studio.sceneName,"name":name]) else { return } }
        }
        _=studio.command("audio.set",["name":guest.microphone,"muted":false,"monitoring":2],undo:false)
        invites[i].admitted=true;message="Câmera e microfone inseridos. Use fones para evitar eco. Controle volume, mute e visibilidade nas fontes e no mixer."
    }
    func insertScreen(_ id: UUID) {
        guard let guest=invites.first(where:{$0.id==id}),guest.peer != nil,let studio else { return }
        if !studio.items.contains(where:{$0.string("name")==guest.screen}) { _=studio.command("source.reuse",["scene":studio.sceneName,"name":guest.screen]) }
    }
    func revoke(_ id: UUID) {
        guard let i=invites.firstIndex(where:{$0.id==id}) else { return }
        invites[i].peer?.close();invites.remove(at:i)
    }
    func stop() {
        generation=UUID();timer?.invalidate();timer=nil
        for guest in invites { guest.peer?.close() };invites=[]
        pipe?.fileHandleForReading.readabilityHandler=nil
        tunnel?.terminationHandler=nil;if tunnel?.isRunning == true { tunnel?.terminate() }
        tunnel=nil;pipe=nil;publicURL=nil;tunnelOutput="";server?.stop();server=nil
    }
    private func refresh() {
        for i in invites.indices {
            if invites[i].peer != nil,Date().timeIntervalSince(invites[i].lastSeen)>20 {
                invites[i].savedNames=invites[i].names;invites[i].peer?.close();invites[i].peer=nil;invites[i].negotiating=false;invites[i].status="Desconectado • aguardando retorno"
            } else if let peer=invites[i].peer { invites[i].status=peer.connectionStatus }
        }
    }
    private func handle(_ path: String,_ token: String,_ payload: [String:Any],_ reply: @escaping GuestHTTPServer.Reply) {
        func respond(_ status: Int,_ object: [String:Any]) { reply(status,(try? JSONSerialization.data(withJSONObject:object)) ?? Data(),"application/json") }
        guard let i=invites.firstIndex(where:{$0.token==token}),let client=payload["client"] as? String,UUID(uuidString:client) != nil else { respond(403,["error":"Convite inválido ou revogado."]);return }
        if invites[i].client == nil {
            guard path=="/join",Date().timeIntervalSince(invites[i].created)<43_200 else { respond(410,["error":"Convite expirado. Peça outro ao apresentador."]);return }
            invites[i].client=client
        }
        guard invites[i].client==client else { respond(409,["error":"Este convite já está em uso em outro navegador."]);return }
        invites[i].lastSeen=Date()
        if path=="/leave" { invites[i].savedNames=invites[i].names;invites[i].peer?.close();invites[i].peer=nil;invites[i].negotiating=false;invites[i].status="Convidado saiu";respond(200,["ok":true]);return }
        if path=="/status" {
            if let camera=payload["camera"] as? Bool,let screen=payload["screen"] as? Bool { invites[i].peer?.setCameraEnabled(camera,screenEnabled:screen) }
            respond(200,["status":invites[i].status,"admitted":invites[i].admitted]);return
        }
        if path=="/join" {
            let name=(payload["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            guard !name.isEmpty,name.count<=60,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else { respond(400,["error":"Informe seu nome, com até 60 caracteres."]);return }
            do { let ice=try iceServers();invites[i].name=name;respond(200,["iceServers":ice,"name":name]) }
            catch { respond(503,["error":"O apresentador precisa revisar a configuração TURN."]) };return
        }
        guard path=="/offer",!invites[i].negotiating,let sdp=payload["sdp"] as? String,sdp.utf8.count<65_536,sdp.hasPrefix("v=0"),sdp.components(separatedBy:"m=").count==4 else { respond(400,["error":"Negociação inválida. Tente reconectar."]);return }
        do {
            let ice=try JSONSerialization.data(withJSONObject:iceServers())
            invites[i].savedNames=invites[i].names;invites[i].peer?.close();let guest=invites[i]
            guard let peer=DanteGuestPeer(camera:guest.camera,screen:guest.screen,microphone:guest.microphone,slot:guest.slot,iceJSON:String(decoding:ice,as:UTF8.self)) else { respond(500,["error":"O motor não conseguiu preparar as fontes."]);return }
            invites[i].peer=peer;invites[i].negotiating=true;let id=guest.id
            peer.answerOffer(sdp) { [weak self] answer,error in
                Task { @MainActor in
                guard let self,let index=self.invites.firstIndex(where:{$0.id==id}),self.invites[index].peer===peer else { respond(410,["error":"Convite encerrado."]);return }
                self.invites[index].negotiating=false
                if let answer { respond(200,["sdp":answer,"type":"answer"]) }
                else { peer.close();self.invites[index].peer=nil;respond(500,["error":error ?? "Falha ao conectar."]) }
                }
            }
        } catch { respond(503,["error":"Configuração de conexão inválida."]) }
    }
}
