import AppKit
import CryptoKit
import UniformTypeIdentifiers

struct LiveLaunch: Identifiable {
    let id = UUID()
    var channel: String
    var title: String
    var thumbnailURL: URL?
    var server: String
    var key: String
    var youtubeAccount: String?
    var broadcastID: String?
    var privacy: String?
}

@MainActor final class YouTubeModel: ObservableObject {
    @Published private(set) var preferences = YouTubePreferences()
    @Published private(set) var broadcasts: [YouTubeBroadcast] = []
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var clientConfigured = false
    @Published private(set) var remoteLive = false
    private let api: YouTubeAPI
    private let vault: LiveKeyVault
    private let directory: URL
    private let prefix: String
    private let oauth = YouTubeOAuth()
    private let edits = PropertyEditQueue()
    private var writable = true
    private var operation: Task<Void, Never>?
    private var livePoll: Task<Void, Never>?
    private var activeEvent: (account: String, broadcast: String)?
    private var tokens: [String: YouTubeTokens] = [:]
    private var client: YouTubeOAuthClient?
    private var url: URL { directory.appendingPathComponent("youtube.json") }
    var account: YouTubeAccount? { preferences.accounts.first { $0.id == preferences.selectedAccount } }
    var state: YouTubeDraftState { preferences.selectedAccount.flatMap { preferences.states[$0] } ?? YouTubeDraftState() }
    var selectedBroadcast: YouTubeBroadcast? { broadcasts.first { $0.id == state.selectedBroadcast } }
    init(directory: URL, api: YouTubeAPI? = nil, vault: LiveKeyVault = .system) {
        self.directory = directory; self.api = api ?? YouTubeAPI(); self.vault = vault
        prefix = "youtube-" + SHA256.hash(data: Data(directory.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        if FileManager.default.fileExists(atPath: url.path) {
            do { preferences = try JSONDecoder().decode(YouTubePreferences.self, from: Data(contentsOf: url)) }
            catch { writable = false; message = "As configurações do YouTube não puderam ser lidas. O arquivo foi preservado." }
        }
    }
    func loadClient() {
        do {
            let raw = try vault.read(prefix + "-client")
            if !raw.isEmpty { client = try JSONDecoder().decode(YouTubeOAuthClient.self, from: Data(raw.utf8)); clientConfigured = true }
        } catch { message = "Não foi possível acessar a configuração Google no Acesso às Chaves." }
    }
    func importClient() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let value = try YouTubeOAuthClient.parse(Data(contentsOf: url))
            try vault.save(String(decoding: JSONEncoder().encode(value), as: UTF8.self), prefix + "-client")
            client = value; clientConfigured = true; tokens.removeAll(); message = "Configuração Google importada. Agora conecte seu canal."
        } catch { message = error.localizedDescription }
    }
    func connect() {
        guard !busy, writable else { return }
        loadClient()
        guard let client else { message = "Importe primeiro o JSON OAuth de computador do projeto Google Cloud do Dante Live."; return }
        run {
            let token = try await self.oauth.authorize(client: client, api: self.api)
            guard !token.refresh.isEmpty else { throw StudioError.message("O Google não forneceu acesso persistente. Conecte novamente e autorize o acesso.") }
            let json = try await self.api.call("channels", token: token.access, query: ["part":"snippet","mine":"true"])
            guard let channel = json.array("items").first, !channel.string("id").isEmpty else { throw StudioError.message("Nenhum canal do YouTube foi encontrado nessa autorização.") }
            let id = channel.string("id"); let tokenAccount = self.prefix + "-account-" + id
            try self.vault.save(String(decoding: JSONEncoder().encode(token), as: UTF8.self), tokenAccount)
            let account = YouTubeAccount(id: id, name: channel.object("snippet").string("title"), tokenAccount: tokenAccount, clientID: client.clientID)
            self.preferences.accounts.removeAll { $0.id == id }; self.preferences.accounts.append(account)
            self.preferences.selectedAccount = id
            if self.preferences.states[id] == nil { self.preferences.states[id] = YouTubeDraftState() }
            self.tokens[id] = token; try self.save()
            self.broadcasts = try await self.api.broadcasts(token: token.access)
            self.message = "Canal conectado: \(account.name)"
        }
    }
    func cancel() { oauth.cancel(); operation?.cancel() }
    var canCancel: Bool { operation != nil }
    var trackingLive: Bool { activeEvent != nil }
    func shutdown() { cancel(); livePoll?.cancel(); edits.flush() }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy, writable else { return }; busy = true; message = nil
        operation = Task { [weak self] in
            defer { self?.busy = false; self?.operation = nil }
            do { try await work() }
            catch is CancellationError { self?.message = "Operação cancelada. Se houve envio ao YouTube, atualize a lista antes de repetir." }
            catch { self?.message = error.localizedDescription }
        }
    }
    func editDraft(_ change: (inout YouTubeDraft) -> Void) {
        guard !busy, writable, let id = account?.id else { return }
        var value = state; change(&value.draft); preferences.states[id] = value
        edits.submit(immediate: false) { [weak self] in do { try self?.save() } catch { self?.message = "Não foi possível salvar o rascunho da live." } }
    }
    func flush() { edits.flush() }
    func prepareForApplicationUpdate() throws {
        guard !busy else { throw StudioError.message("Aguarde a operação do YouTube terminar antes de atualizar.") }
        edits.flush()
        // Retry persistence and propagate disk failures instead of losing an unsaved draft.
        try save()
    }
    func selectAccount(_ id: String) {
        guard !busy, writable else { return }; edits.flush()
        guard preferences.accounts.contains(where: { $0.id == id }) else { return }
        preferences.selectedAccount = id; broadcasts = []
        do { try save() } catch { message = error.localizedDescription; return }
        refresh()
    }
    func selectBroadcast(_ id: String) {
        guard !busy, writable, let account else { return }; edits.flush()
        if id.isEmpty, state.selectedBroadcast != nil { newDraft(); return }
        var value = state; value.selectedBroadcast = id.isEmpty ? nil : id
        preferences.states[account.id] = value
        do { try save() } catch { message = error.localizedDescription }
    }
    func newDraft() {
        guard !busy, writable, let account else { return }
        // Starting another draft is explicit; an uncertain previous remote creation is not retried.
        var value = YouTubeDraftState(); value.draft = state.draft
        preferences.states[account.id] = value
        do { try save(); message = "Novo rascunho. Lives já criadas continuam na lista do YouTube." } catch { message = error.localizedDescription }
    }
    func disconnect() {
        guard !busy, let account else { return }
        do {
            try vault.delete(account.tokenAccount); tokens[account.id] = nil
            preferences.accounts.removeAll { $0.id == account.id }; preferences.states[account.id] = nil
            preferences.selectedAccount = preferences.accounts.first?.id; broadcasts = []; try save()
            message = "Conta removida deste Mac. As lives no YouTube foram preservadas."
        } catch { message = "Não foi possível remover a conexão local do YouTube." }
    }
    func chooseThumbnail() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg, .png]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 2 * 1024 * 1024, NSImage(data: data) != nil,
                  data.starts(with: [0xff,0xd8]) || data.starts(with: [0x89,0x50,0x4e,0x47]) else { throw StudioError.message("Use uma capa JPEG ou PNG de até 2 MB.") }
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("thumbnails"), withIntermediateDirectories: true)
            let name = UUID().uuidString + (data.starts(with: [0xff,0xd8]) ? ".jpg" : ".png")
            try data.write(to: directory.appendingPathComponent("thumbnails/" + name), options: .atomic)
            editDraft { $0.thumbnailFile = name }; edits.flush()
        } catch { message = error.localizedDescription }
    }
    func thumbnailURL(_ file: String?) -> URL? {
        guard let file, file == URL(fileURLWithPath: file).lastPathComponent else { return nil }
        return directory.appendingPathComponent("thumbnails/" + file)
    }
    func refresh() {
        guard let account else { return }
        run { self.broadcasts = try await self.api.broadcasts(token: self.accessToken(account.id)); self.message = "Lista de lives atualizada." }
    }
    private func save() throws {
        guard writable else { throw StudioError.message("O arquivo do YouTube precisa ser recuperado antes de editar.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
    private func accessToken(_ id: String) async throws -> String {
        guard let account = preferences.accounts.first(where: { $0.id == id }) else { throw StudioError.message("Conecte o canal do YouTube.") }
        if client == nil { loadClient() }
        guard let client, client.clientID == account.clientID else { throw StudioError.message("Conecte este canal usando a configuração Google atual.") }
        var value: YouTubeTokens
        if let cached = tokens[id] { value = cached }
        else { value = try JSONDecoder().decode(YouTubeTokens.self, from: Data(vault.read(account.tokenAccount).utf8)) }
        if value.expires.timeIntervalSinceNow < 60 {
            guard !value.refresh.isEmpty else { throw YouTubeAPIError(reason: "unauthorized") }
            value = try await api.tokens(client: client, fields: ["grant_type":"refresh_token","refresh_token":value.refresh], previousRefresh: value.refresh)
            try vault.save(String(decoding: JSONEncoder().encode(value), as: UTF8.self), account.tokenAccount)
        }
        tokens[id] = value; return value.access
    }
    func schedule() {
        guard let account else { message = "Conecte o canal primeiro."; return }
        let draft = state.draft
        guard draft.scheduledAt > Date() else { message = "Escolha uma data e hora futuras para agendar."; return }
        run {
            let event = try await self.ensureCreated(account: account.id, draft: draft, scheduled: true)
            self.preferences.states[account.id]?.selectedBroadcast = event.id; try self.save()
            self.broadcasts = try await self.api.broadcasts(token: self.accessToken(account.id))
            self.message = "Live criada no YouTube. O link está pronto; selecione essa live e clique em Transmitir quando quiser começar."
        }
    }
    private func ensureCreated(account id: String, draft: YouTubeDraft, scheduled: Bool) async throws -> YouTubeBroadcast {
        try draft.validate(); edits.flush()
        var journal = preferences.states[id] ?? YouTubeDraftState()
        let token = try await accessToken(id)
        let broadcast: YouTubeBroadcast
        if let created = journal.createdBroadcast {
            guard journal.submittedDraft == nil || journal.submittedDraft == draft else { throw StudioError.message("Esta live já foi criada com os dados anteriores. Atualize a lista e selecione-a; para editar os dados, use o YouTube Studio. Crie outro rascunho somente se quiser outro vídeo.") }
            broadcast = try await api.broadcast(created, token: token)
        }
        else {
            guard !journal.creationUncertain else { throw StudioError.message("A criação anterior ficou sem confirmação. Atualize a lista e selecione a live criada; confira também o YouTube Studio antes de criar outra.") }
            journal.creationUncertain = true; journal.submittedDraft = draft; preferences.states[id] = journal; try save()
            do { broadcast = try await api.createBroadcast(draft, at: scheduled ? draft.scheduledAt : Date().addingTimeInterval(60), token: token) }
            catch let error as YouTubeAPIError where error.definitelyRejected {
                journal.creationUncertain = false; preferences.states[id] = journal; try save(); throw error
            }
            journal.createdBroadcast = broadcast.id; journal.creationUncertain = false; preferences.states[id] = journal; try save()
        }
        guard ["created","ready","testStarting","testing"].contains(broadcast.lifeCycle) else { throw StudioError.message("Essa live não está mais disponível para iniciar. Crie um novo rascunho.") }
        try await api.updateVideo(broadcast.id, draft: draft, token: token)
        if let file = thumbnailURL(draft.thumbnailFile) { try await api.thumbnail(broadcast.id, data: Data(contentsOf: file), token: token) }
        _ = try await ensureBound(broadcast, account: id, token: token)
        return try await api.broadcast(broadcast.id, token: token)
    }
    private func ensureBound(_ event: YouTubeBroadcast, account id: String, token: String) async throws -> String {
        if !event.boundStreamID.isEmpty { return event.boundStreamID }
        var journal = preferences.states[id] ?? YouTubeDraftState()
        // Do not reuse a stream journal belonging to a different broadcast.
        if journal.createdBroadcast != event.id { journal.createdBroadcast = event.id; journal.createdStream = nil; journal.streamCreationUncertain = false }
        let streamID: String
        if let existing = journal.createdStream { streamID = existing }
        else {
            guard !journal.streamCreationUncertain else { throw StudioError.message("A criação do stream ficou sem confirmação. Confira o vínculo da live no YouTube Studio e atualize a lista antes de repetir.") }
            journal.streamCreationUncertain = true; preferences.states[id] = journal; try save()
            do { streamID = try await api.createStream(title: "Dante Live • " + event.id, token: token) }
            catch let error as YouTubeAPIError where error.definitelyRejected { journal.streamCreationUncertain = false; preferences.states[id] = journal; try save(); throw error }
            journal.createdStream = streamID; journal.streamCreationUncertain = false; preferences.states[id] = journal; try save()
        }
        try await api.bind(event.id, stream: streamID, token: token)
        return streamID
    }
    func confirmation() async throws -> LiveLaunch {
        guard !busy, let account else { throw StudioError.message("Conecte e selecione um canal do YouTube.") }
        edits.flush()
        if let selected = state.selectedBroadcast {
            let event = try await api.broadcast(selected, token: accessToken(account.id))
            guard !["complete","revoked"].contains(event.lifeCycle) else { throw StudioError.message("Esta live já foi encerrada. Escolha outra live.") }
            if let index = broadcasts.firstIndex(where: { $0.id == event.id }) { broadcasts[index] = event } else { broadcasts.append(event) }
            return LiveLaunch(channel: account.name, title: event.title, thumbnailURL: event.thumbnailURL.flatMap(URL.init(string:)), server: "YouTube • RTMPS", key: "", youtubeAccount: account.id, broadcastID: event.id, privacy: event.privacy)
        }
        try state.draft.validate()
        return LiveLaunch(channel: account.name, title: state.draft.title, thumbnailURL: thumbnailURL(state.draft.thumbnailFile), server: "YouTube • RTMPS", key: "", youtubeAccount: account.id, broadcastID: nil, privacy: state.draft.privacy)
    }
    func prepare(_ launch: LiveLaunch) async throws -> LiveLaunch {
        guard !busy, let id = launch.youtubeAccount, id == account?.id else { throw StudioError.message("A seleção do canal mudou. Confirme a transmissão novamente.") }
        busy = true; defer { busy = false }
        let token = try await accessToken(id)
        let event: YouTubeBroadcast
        if let selected = launch.broadcastID { event = try await api.broadcast(selected, token: token) }
        else { event = try await ensureCreated(account: id, draft: state.draft, scheduled: false) }
        guard event.title == launch.title, event.privacy == launch.privacy else { throw StudioError.message("O título ou a visibilidade da live mudou no YouTube. Confirme a transmissão novamente.") }
        guard !["complete","revoked","live"].contains(event.lifeCycle) else { throw StudioError.message("Essa live já está em andamento ou foi encerrada. Atualize a seleção.") }
        let streamID = try await ensureBound(event, account: id, token: token)
        let connection = try await api.stream(streamID, token: token)
        guard !connection.active else { throw StudioError.message("Este stream já está recebendo vídeo. Pare o outro envio antes de iniciar pelo Dante.") }
        preferences.states[id]?.selectedBroadcast = event.id; try save()
        var prepared = launch; prepared.server = connection.server; prepared.key = connection.key; prepared.broadcastID = event.id
        return prepared
    }
    func watchStarted(_ launch: LiveLaunch, isSending: @escaping @MainActor () -> Bool) {
        guard let account = launch.youtubeAccount, let id = launch.broadcastID else { return }
        activeEvent = (account,id); message = nil; remoteLive = false; livePoll?.cancel()
        livePoll = Task { [weak self] in
            for _ in 0..<60 {
                do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() } catch { return }
                guard let self, isSending() else { return }
                do {
                    let token = try await self.accessToken(account)
                    let event = try await self.api.broadcast(id, token: token)
                    if event.lifeCycle == "live" { self.remoteLive = true; self.message = nil; return }
                    if !event.autoStart, !event.boundStreamID.isEmpty {
                        let stream = try await self.api.stream(event.boundStreamID, token: token)
                        if stream.active { try await self.api.transition(id, status: "live", token: token) }
                    }
                } catch { self.message = "Enviando vídeo, mas o YouTube não confirmou a live: \(error.localizedDescription)"; return }
            }
            self?.message = "O YouTube ainda não confirmou a live. Confira a página no YouTube Studio."
        }
    }
    func endActive() {
        livePoll?.cancel(); remoteLive = false
        guard let event = activeEvent else { return }; activeEvent = nil
        Task { [weak self] in
            guard let self else { return }
            do { try await self.api.transition(event.broadcast, status: "complete", token: self.accessToken(event.account)); self.message = "Live encerrada no YouTube." }
            catch { self.message = "O envio foi parado, mas confirme o encerramento no YouTube Studio. \(error.localizedDescription)" }
        }
    }
}
