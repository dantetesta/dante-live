import AppKit
import Security

private final class GuestVPSNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor struct GuestInvite: Identifiable {
    let id = UUID()
    let token: String
    let slot: Int
    let created = Date()
    var name: String
    var firstName: String { name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? name }
    var client: String?
    var lastSeen = Date()
    var peer: DanteGuestPeer?
    var status = "Aguardando convidado"
    var negotiating = false
    var negotiation: String?
    var admitted = false
    var cameraEnabled = true
    var screenEnabled = false
    var microphoneEnabled = true
    var savedNames: [String] = []
    var names: [String] { let current=peer?.sourceNames ?? [];return current.count==3 ? current : savedNames }
    var camera: String { names.count==3 ? names[0] : "\(firstName) • câmera · \(id.uuidString.prefix(6))" }
    var screen: String { names.count==3 ? names[1] : "\(firstName) • tela · \(id.uuidString.prefix(6))" }
    var microphone: String { names.count==3 ? names[2] : "\(firstName) • microfone · \(id.uuidString.prefix(6))" }
}

@MainActor
final class GuestModel: ObservableObject {
    @Published private(set) var invites: [GuestInvite] = []
    @Published private(set) var busy = false
    @Published private(set) var publicURL: URL?
    @Published var message: String?
    @Published var turnJSON = ""
    @Published var vpsAddress = UserDefaults.standard.string(forKey: "guestVPSAddress") ?? ""
    @Published var vpsPort = UserDefaults.standard.integer(forKey: "guestVPSPort") == 0 ? 443 : UserDefaults.standard.integer(forKey: "guestVPSPort")
    @Published var vpsEnabled = UserDefaults.standard.bool(forKey: "guestVPSEnabled")
    @Published var vpsStatus: String?
    @Published var showing = false
    private weak var studio: StudioModel?
    private let discoveryServers: [String]
    private var server: GuestHTTPServer?
    private var tunnel: Process?
    private var pipe: Pipe?
    private var tunnelOutput = ""
    private var timer: Timer?
    private var generation = UUID()
    private var relayTask: Task<Void,Never>?
    private let vpsSession = URLSession(configuration: .ephemeral, delegate: GuestVPSNoRedirect(), delegateQueue: nil)
    private var remoteICE: [[String: Any]] = []
    var hasVPSConfiguration: Bool { !vpsAddress.isEmpty && (try? SecretStore.read(account: "guest-vps-token"))?.isEmpty == false }
    var inUse: Bool { busy || !invites.isEmpty }
    var hasTURN: Bool { !remoteICE.isEmpty || (try? iceServers()).map { $0.count > 1 } ?? false }
    init(studio: StudioModel, discoveryServers: [String] = ["stun:stun.cloudflare.com:3478"]) {
        self.studio = studio; self.discoveryServers = discoveryServers
    }

    static func token() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw StudioError.message("Não foi possível gerar um convite seguro.") }
        return bytes.map { String(format:"%02x",$0) }.joined()
    }
    func iceServers() throws -> [[String: Any]] {
        var ice: [[String: Any]] = [["urls":discoveryServers]]
        if vpsEnabled { ice.append(contentsOf:remoteICE); return ice }
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
                if vpsEnabled { try await refreshVPSICE() }
                _ = try iceServers()
                if !vpsEnabled && server == nil { try await startServer() }
                if publicURL == nil { if vpsEnabled { try await startVPSBridge() } else { try await startTunnel() } }
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
    private func vpsURL(_ path: String) throws -> URL {
        let address=vpsAddress.trimmingCharacters(in:.whitespacesAndNewlines)
        let octets=address.split(separator:".",omittingEmptySubsequences:false)
        guard octets.count==4,octets.allSatisfy({ $0.count <= 3 && UInt8($0) != nil }),
              let url=URL(string:"https://\(address)\(vpsPort == 443 ? "" : ":\(vpsPort)")\(path)"),url.host==address,
              (1...65535).contains(vpsPort) else { throw StudioError.message("Informe o IPv4 público da VPS e a porta HTTPS.") }
        return url
    }
    func saveVPS(token: String) throws {
        _ = try vpsURL("/api/health")
        guard token.count >= 32,token.count <= 256,!token.contains("\n") else { throw StudioError.message("O token da VPS é inválido.") }
        try SecretStore.save(token,account:"guest-vps-token")
        UserDefaults.standard.set(vpsAddress,forKey:"guestVPSAddress")
        UserDefaults.standard.set(vpsPort,forKey:"guestVPSPort")
        UserDefaults.standard.set(true,forKey:"guestVPSEnabled")
        vpsEnabled=true;vpsStatus="Configuração salva no Acesso às Chaves. Teste a conexão antes de convidar."
    }
    func importVPSProfile(_ data: Data) throws {
        guard data.count < 4096,
              let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              value["protocol"] as? Int == 2,
              let server=value["server"] as? String,
              let url=URL(string:server),url.scheme=="https",let host=url.host,
              let token=value["connectionToken"] as? String else { throw StudioError.message("Este arquivo não é um perfil Dante Live compatível.") }
        vpsAddress=host;vpsPort=value["httpsPort"] as? Int ?? 443
        try saveVPS(token:token)
    }
    func removeVPS() throws {
        guard !inUse else { throw StudioError.message("Encerre a sala antes de remover o servidor.") }
        try SecretStore.delete(account:"guest-vps-token")
        vpsAddress="";vpsEnabled=false;remoteICE=[];vpsStatus=nil
        UserDefaults.standard.removeObject(forKey:"guestVPSAddress")
        UserDefaults.standard.set(false,forKey:"guestVPSEnabled")
    }
    private func vpsData(_ path: String) async throws -> [String:Any] {
        let token=try SecretStore.read(account:"guest-vps-token")
        guard !token.isEmpty else { throw StudioError.message("Informe o token de conexão da VPS.") }
        var request=URLRequest(url:try vpsURL(path));request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.timeoutInterval=path == "/api/poll" ? 25 : 10
        let (data,response)=try await vpsSession.data(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode==200,
              data.count < (path == "/api/poll" ? 100_000 : 8192),
              let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw StudioError.message("A VPS não respondeu com uma configuração válida.") }
        return object
    }
    func testVPS() async {
        do { let health=try await vpsData("/api/health");guard health["status"] as? String=="ready",health["protocol"] as? Int==2 else { throw StudioError.message("A versão do serviço da VPS não é compatível.") };try await refreshVPSICE();vpsStatus="Servidor conectado. TURN e ponte de convites disponíveis." }
        catch { vpsStatus="Não foi possível conectar: \(error.localizedDescription)" }
    }
    private func refreshVPSICE() async throws {
        let value=try await vpsData("/api/turn")
        guard let entries=value["iceServers"] as? [[String:Any]],entries.count==1,
              let entry=entries.first,let urls=entry["urls"] as? [String],!urls.isEmpty,
              urls.allSatisfy({$0.hasPrefix("turn:") || $0.hasPrefix("turns:")}),
              let user=entry["username"] as? String,!user.isEmpty,
              let credential=entry["credential"] as? String,!credential.isEmpty else { throw StudioError.message("A VPS não forneceu credenciais TURN válidas.") }
        remoteICE=entries
    }
    private func startVPSBridge() async throws {
        let url=try vpsURL("/")
        let (_,response)=try await vpsSession.data(from:url)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else { throw StudioError.message("A página de convidados da VPS não está disponível.") }
        publicURL=try vpsURL("")
        let id=UUID();generation=id
        relayTask=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.generation==id else { return }
                do {
                    let result=try await self.vpsData("/api/poll")
                    if let request=result["request"] as? [String:Any] { self.relay(request) }
                } catch {
                    self.vpsStatus="Ponte de convites reconectando à VPS…"
                    try? await Task.sleep(for:.seconds(2))
                }
            }
        }
    }
    private func relay(_ request: [String:Any]) {
        guard let id=request["id"] as? String,id.count==32,
              let path=request["path"] as? String,let token=request["token"] as? String,
              let payload=request["payload"] as? [String:Any] else { return }
        handle(path,token,payload) { [weak self] status,body,_ in
            Task { @MainActor in
                guard let self else { return }
                do {
                    let url=try self.vpsURL("/api/reply")
                    let secret=try SecretStore.read(account:"guest-vps-token")
                    var post=URLRequest(url:url)
                    post.httpMethod="POST";post.setValue("Bearer \(secret)",forHTTPHeaderField:"Authorization")
                    post.setValue("application/json",forHTTPHeaderField:"Content-Type")
                    post.httpBody=try JSONSerialization.data(withJSONObject:["id":id,"status":status,"body":body.base64EncodedString()])
                    post.timeoutInterval=10
                    _ = try await self.vpsSession.data(for:post)
                } catch { self.vpsStatus="Falha ao responder ao convite. A ponte tentará reconectar." }
            }
        }
    }
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
    var managedSourceNames: Set<String> {
        Set(invites.flatMap { [$0.camera, $0.screen, $0.microphone] })
    }
    func participantSlot(for source: String) -> Int? {
        invites.first { [$0.camera,$0.screen,$0.microphone].contains(source) }?.slot
    }
    func displayName(for source: String) -> String {
        guard let guest = invites.first(where: { [$0.camera,$0.screen,$0.microphone].contains(source) }) else { return source }
        return guest.firstName + " • " + (source == guest.camera ? "câmera" : source == guest.screen ? "tela" : "microfone")
    }
    func scene(for guest: GuestInvite) -> String? {
        studio?.scenes.first { scene in scene.array("items").contains { $0.string("name") == guest.camera || $0.string("name") == guest.microphone } }?.string("name")
    }
    func item(_ source: String, in scene: String) -> [String:Any]? {
        studio?.scenes.first { $0.string("name") == scene }?.array("items").first { $0.string("name") == source }
    }
    func admit(_ id: UUID, to destination: String? = nil) {
        guard let i=invites.firstIndex(where:{$0.id==id}),invites[i].peer != nil,let studio else { return }
        let guest=invites[i], target=destination ?? scene(for:guest) ?? studio.sceneName
        guard studio.scenes.contains(where:{$0.string("name")==target}) else { return }
        let oldScenes = studio.scenes
        let hadScreen = oldScenes.contains { $0.array("items").contains { $0.string("name") == guest.screen } }
        for name in [guest.camera,guest.microphone] + (hadScreen ? [guest.screen] : []) {
            if item(name,in:target) == nil {
                guard studio.command("source.reuse",["scene":target,"name":name]) else { return }
                if let inserted=item(name,in:target) {
                    if let previous=oldScenes.flatMap({$0.array("items")}).first(where:{$0.string("name")==name}) {
                        var transform:[String:Any]=["scene":target,"id":inserted.sceneItemID]
                        for key in ["x","y","scaleX","scaleY","rotation","cropLeft","cropRight","cropTop","cropBottom"] { transform[key]=previous[key] }
                        if name != guest.microphone { _=studio.command("item.transform",transform,undo:false) }
                        _=studio.command("item.visible",["scene":target,"id":inserted.sceneItemID,"value":previous.flag("visible")],undo:false)
                        _=studio.command("item.locked",["scene":target,"id":inserted.sceneItemID,"value":previous.flag("locked")],undo:false)
                    } else if name != guest.microphone {
                        _=studio.command("item.fit",["scene":target,"id":inserted.sceneItemID],undo:false)
                    }
                }
            }
        }
        // Move only after the new membership exists. Volume/mute are source state
        // and must survive scene changes and reconnects.
        for old in oldScenes where old.string("name") != target {
            for component in old.array("items") where [guest.camera,guest.microphone,guest.screen].contains(component.string("name")) {
                _=studio.command("source.remove",["scene":old.string("name"),"id":component.sceneItemID],undo:false)
            }
        }
        if !guest.admitted { _=studio.command("audio.set",["name":guest.microphone,"monitoring":2],undo:false) }
        invites[i].admitted=true;message="\(guest.name) adicionado à cena \(target). Controle câmera, tela e microfone no painel Participantes."
    }
    func insertScreen(_ id: UUID) {
        guard let guest=invites.first(where:{$0.id==id}),guest.peer != nil,let studio else { return }
        let target=scene(for:guest) ?? studio.sceneName
        if item(guest.screen,in:target) == nil {
            guard studio.command("source.reuse",["scene":target,"name":guest.screen]) else {return}
            if let added=item(guest.screen,in:target) { _=studio.command("item.fit",["scene":target,"id":added.sceneItemID],undo:false) }
        }
    }
    func toggleVideo(_ id: UUID, screen: Bool) {
        guard let guest=invites.first(where:{$0.id==id}),let studio,let target=scene(for:guest) else {return}
        let name=screen ? guest.screen : guest.camera
        if let current=item(name,in:target) {
            _=studio.command("item.visible",["scene":target,"id":current.sceneItemID,"value":!current.flag("visible")])
        } else if screen { insertScreen(id) }
    }
    func toggleMicrophone(_ id: UUID) {
        guard let guest=invites.first(where:{$0.id==id}),let target=scene(for:guest),let current=item(guest.microphone,in:target),let studio else {return}
        _=studio.command("audio.set",["name":guest.microphone,"muted":!current.flag("muted")],undo:false)
    }
    func select(_ source: String, guest: GuestInvite) {
        guard let studio,let target=scene(for:guest),let selected=item(source,in:target) else {return}
        studio.selectScene(target);studio.selectedItem=selected.sceneItemID
    }
    func removeFromScene(_ id: UUID) {
        guard let i=invites.firstIndex(where:{$0.id==id}),let studio else {return}
        let guest=invites[i]
        for scene in studio.scenes {
            for component in scene.array("items") where [guest.camera,guest.screen,guest.microphone].contains(component.string("name")) {
                _=studio.command("source.remove",["scene":scene.string("name"),"id":component.sceneItemID],undo:false)
            }
        }
        invites[i].admitted=false
    }
    func revoke(_ id: UUID) {
        guard let i=invites.firstIndex(where:{$0.id==id}) else { return }
        removeFromScene(id);invites[i].peer?.close();invites.remove(at:i)
    }
    func stop() {
        generation=UUID();timer?.invalidate();timer=nil
        for guest in invites { removeFromScene(guest.id);guest.peer?.close() };invites=[]
        pipe?.fileHandleForReading.readabilityHandler=nil
        tunnel?.terminationHandler=nil;if tunnel?.isRunning == true { tunnel?.terminate() }
        tunnel=nil;pipe=nil;publicURL=nil;tunnelOutput="";server?.stop();server=nil
        relayTask?.cancel();relayTask=nil;remoteICE=[]
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
        if path=="/leave" { invites[i].savedNames=invites[i].names;invites[i].peer?.close();invites[i].peer=nil;invites[i].negotiating=false;invites[i].negotiation=nil;invites[i].status="Convidado saiu";respond(200,["ok":true]);return }
        if path=="/ice" {
            guard let negotiation=payload["negotiation"] as? String,negotiation==invites[i].negotiation,
                  !invites[i].negotiating,let peer=invites[i].peer else { respond(409,["error":"Esta tentativa de conexão terminou. Tente reconectar."]);return }
            guard let candidates=payload["candidates"] as? [[String:Any]],candidates.count<=64,
                  candidates.allSatisfy(Self.validCandidate) else { respond(400,["error":"Dados de conexão inválidos."]);return }
            for candidate in candidates {
                peer.addRemoteCandidate(candidate["candidate"] as! String,mid:candidate["sdpMid"] as! String,line:(candidate["sdpMLineIndex"] as! NSNumber).int32Value)
            }
            if let camera=payload["camera"] as? Bool,let screen=payload["screen"] as? Bool {
                invites[i].cameraEnabled=camera;invites[i].screenEnabled=screen;invites[i].microphoneEnabled=payload["microphone"] as? Bool ?? true
                peer.setCameraEnabled(camera,screenEnabled:screen)
            }
            respond(200,["candidates":peer.localCandidates,"status":peer.connectionStatus,"admitted":invites[i].admitted]);return
        }
        if path=="/status" {
            if let camera=payload["camera"] as? Bool,let screen=payload["screen"] as? Bool { invites[i].peer?.setCameraEnabled(camera,screenEnabled:screen) }
            respond(200,["status":invites[i].status,"admitted":invites[i].admitted]);return
        }
        if path=="/join" {
            let name=(payload["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            guard !name.isEmpty,name.count<=60,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else { respond(400,["error":"Informe seu nome, com até 60 caracteres."]);return }
            do { let ice=try iceServers();invites[i].name=name;respond(200,["iceServers":ice,"name":name,"trickleICE":true]) }
            catch { respond(503,["error":"O apresentador precisa revisar a configuração TURN."]) };return
        }
        guard path=="/offer",!invites[i].negotiating,let negotiation=payload["negotiation"] as? String,UUID(uuidString:negotiation) != nil,
              let sdp=payload["sdp"] as? String,sdp.utf8.count<65_536,sdp.hasPrefix("v=0"),sdp.components(separatedBy:"m=").count==4 else { respond(400,["error":"Negociação inválida. Atualize a página do convite e tente reconectar."]);return }
        do {
            let ice=try JSONSerialization.data(withJSONObject:iceServers())
            invites[i].savedNames=invites[i].names;invites[i].peer?.close();let guest=invites[i]
            guard let peer=DanteGuestPeer(camera:guest.camera,screen:guest.screen,microphone:guest.microphone,slot:guest.slot,iceJSON:String(decoding:ice,as:UTF8.self)) else { respond(500,["error":"O motor não conseguiu preparar as fontes."]);return }
            invites[i].peer=peer;invites[i].negotiating=true;invites[i].negotiation=negotiation;let id=guest.id
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
    static func validCandidate(_ item:[String:Any]) -> Bool {
        guard let value=item["candidate"] as? String,value.hasPrefix("candidate:"),value.utf8.count<=1024,
              !value.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
              let mid=item["sdpMid"] as? String,["0","1","2"].contains(mid),
              let line=item["sdpMLineIndex"] as? NSNumber,CFGetTypeID(line) != CFBooleanGetTypeID(),
              line.doubleValue==Double(line.intValue),(0...2).contains(line.intValue) else { return false }
        return true
    }
}
