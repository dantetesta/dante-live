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
    var localLiveID: String?
    var confirmedDraft: YouTubeDraft?
    var latency: String?
    func validateVideoLatency(_ video: LiveVideoSettings) throws {
        if youtubeAccount != nil, let latency, latency != "normal", max(video.width,video.height) >= 3840 {
            throw StudioError.message("O YouTube exige latência Normal para 4K. Escolha 1080p/1440p para menor atraso ou altere a latência da live para Normal antes de transmitir.")
        }
    }
}

struct LiveShareInfo: Equatable {
    let url: URL
    let title: String
    let privacy: String
    init?(_ launch: LiveLaunch) {
        guard launch.youtubeAccount != nil, let id = launch.broadcastID, !id.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: id)]
        guard let url = components.url else { return nil }
        self.url = url; title = launch.title; privacy = launch.privacy ?? "unknown"
    }
}

@MainActor final class YouTubeModel: ObservableObject {
    @Published private(set) var preferences = YouTubePreferences()
    @Published private(set) var broadcasts: [YouTubeBroadcast] = []
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var clientConfigured = false
    @Published private(set) var remoteLive = false
    @Published private(set) var liveShare: LiveShareInfo?
    @Published private(set) var draftSaveStatus = "Alterações salvas neste Mac"
    let chat = YouTubeChat()
    let activity = YouTubeActivity()
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
    var currentLiveID: String? { account.flatMap { preferences.currentLiveIDs?[$0.id] } }
    var savedLives: [YouTubeSavedLive] {
        guard let id = account?.id else { return [] }
        var items = preferences.savedLives?[id] ?? []
        if let current = currentLiveID, let index = items.firstIndex(where: { $0.id == current }) { items[index].state = state }
        return items
    }
    var localLives: [YouTubeSavedLive] { savedLives.filter { $0.state.createdBroadcast == nil && $0.state.selectedBroadcast == nil } }
    var canEditDraft: Bool { canOrganizeLibrary && state.createdBroadcast == nil && state.selectedBroadcast == nil && !state.creationUncertain }
    func canTransmitLocal(_ live: YouTubeSavedLive) -> Bool {
        guard live.state.createdBroadcast == nil, live.state.selectedBroadcast == nil, !live.state.creationUncertain else { return false }
        do { try live.state.draft.validate(); return true } catch { return false }
    }
    private func migrateLibrary() {
        if preferences.savedLives == nil { preferences.savedLives = [:] }
        if preferences.currentLiveIDs == nil { preferences.currentLiveIDs = [:] }
        for account in preferences.accounts where preferences.currentLiveIDs?[account.id] == nil && preferences.savedLives?[account.id] == nil {
            var value = preferences.states[account.id] ?? YouTubeDraftState()
            // Older versions allowed a remote selection and an unrelated local draft
            // to occupy the same slot. Preserve both when migrating that layout.
            if let remoteID = value.selectedBroadcast, value.createdBroadcast != remoteID {
                if value.createdBroadcast != nil || value.creationUncertain || !value.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var local = value; local.selectedBroadcast = nil
                    preferences.savedLives?[account.id, default: []].append(YouTubeSavedLive(state: local))
                }
                value = YouTubeDraftState(); value.selectedBroadcast = remoteID; value.createdBroadcast = remoteID
                value.draft.title = preferences.cachedBroadcasts?[account.id]?.first(where: { $0.id == remoteID })?.title ?? "Live selecionada"
            }
            let entry = YouTubeSavedLive(state: value)
            preferences.savedLives?[account.id, default: []].append(entry)
            preferences.currentLiveIDs?[account.id] = entry.id
            preferences.states[account.id] = entry.state
        }
    }
    private func storeCurrentLive() {
        migrateLibrary()
        guard let account, let current = currentLiveID else { return }
        var items = preferences.savedLives?[account.id] ?? []
        let entry = YouTubeSavedLive(id: current, state: state)
        if let index = items.firstIndex(where: { $0.id == current }) { items[index] = entry } else { items.append(entry) }
        preferences.savedLives?[account.id] = items
    }
    @discardableResult func saveDraftForLater() -> Bool {
        guard canEditDraft else { return false }
        do {
            try state.draft.validate(); edits.flush(); try save()
            message = "Live salva neste Mac. Ela estará na lista ao clicar em Transmitir."
            return true
        } catch { message = error.localizedDescription; return false }
    }
    @discardableResult func selectLocalLive(_ id: String) -> Bool {
        guard canOrganizeLibrary, let account else { return false }
        edits.flush()
        do { try save() } catch { message = error.localizedDescription; return false }
        guard let item = savedLives.first(where: { $0.id == id }), item.state.createdBroadcast == nil, item.state.selectedBroadcast == nil else { return false }
        let previous = preferences
        preferences.currentLiveIDs?[account.id] = id
        preferences.states[account.id] = item.state
        do { try save(); message = nil; return true }
        catch { preferences = previous; message = error.localizedDescription; return false }
    }
    /// Deletes only an unpublished local preparation. No YouTube request is made.
    @discardableResult func removeLocalLive(_ id: String) -> Bool {
        guard canOrganizeLibrary, let account else { return false }
        edits.flush()
        guard localLives.contains(where: { $0.id == id }) else { return false }
        let previous = preferences
        storeCurrentLive()
        preferences.savedLives?[account.id]?.removeAll { $0.id == id }
        if currentLiveID == id {
            let next = preferences.savedLives?[account.id]?.first {
                $0.state.createdBroadcast == nil && $0.state.selectedBroadcast == nil
            }
            preferences.currentLiveIDs?[account.id] = next?.id
            preferences.states[account.id] = next?.state ?? YouTubeDraftState()
        }
        do {
            try save()
            message = "Preparação removida deste Mac. Nada foi alterado no YouTube."
            return true
        } catch {
            preferences = previous
            message = "Não foi possível remover a preparação. Seus dados foram preservados."
            return false
        }
    }
    var selectedBroadcast: YouTubeBroadcast? { broadcasts.first { $0.id == state.selectedBroadcast } }
    var hiddenBroadcastIDs: Set<String> { account.flatMap { preferences.hiddenBroadcasts?[$0.id] } ?? [] }
    var visibleBroadcasts: [YouTubeBroadcast] { broadcasts.filter { !hiddenBroadcastIDs.contains($0.id) } }
    var canOrganizeLibrary: Bool { !busy && writable && !trackingLive && account != nil }
    /// Local preferences only. Never delete, update, or transition a remote broadcast here.
    @discardableResult func setBroadcastHidden(_ id: String, hidden: Bool) -> Bool {
        guard canOrganizeLibrary, let account, !id.isEmpty else { return false }
        edits.flush()
        let previous = preferences
        var ids = hiddenBroadcastIDs
        if hidden { ids.insert(id) } else { ids.remove(id) }
        if preferences.hiddenBroadcasts == nil { preferences.hiddenBroadcasts = [:] }
        preferences.hiddenBroadcasts?[account.id] = ids
        if hidden, state.selectedBroadcast == id { preferences.states[account.id]?.selectedBroadcast = nil }
        do {
            try save()
            message = hidden ? "Live ocultada neste Mac. Nada foi alterado no YouTube." : "Live exibida novamente neste Mac."
            return true
        } catch {
            preferences = previous
            message = "Não foi possível salvar a organização da lista. Tente novamente."
            return false
        }
    }
    init(directory: URL, api: YouTubeAPI? = nil, vault: LiveKeyVault = .system) {
        self.directory = directory; self.api = api ?? YouTubeAPI(); self.vault = vault
        prefix = "youtube-" + SHA256.hash(data: Data(directory.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        if FileManager.default.fileExists(atPath: url.path) {
            do { preferences = try JSONDecoder().decode(YouTubePreferences.self, from: Data(contentsOf: url)) }
            catch { writable = false; message = "As configurações do YouTube não puderam ser lidas. O arquivo foi preservado." }
        }
        migrateLibrary()
        broadcasts = preferences.selectedAccount.flatMap { preferences.cachedBroadcasts?[$0] } ?? []
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
            self.broadcasts = self.preferences.cachedBroadcasts?[id] ?? []
            if self.preferences.states[id] == nil { self.preferences.states[id] = YouTubeDraftState() }
            self.tokens[id] = token; try self.save()
            self.broadcasts = try await self.api.broadcasts(token: token.access); try self.save()
            self.message = "Canal conectado: \(account.name)"
        }
    }
    func cancel() { oauth.cancel(); operation?.cancel() }
    var canCancel: Bool { operation != nil }
    var trackingLive: Bool { activeEvent != nil }
    func shutdown() { activity.reset(); chat.reset(); cancel(); livePoll?.cancel(); edits.flush() }
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
        guard canEditDraft, let id = account?.id else { return }
        if currentLiveID == nil { preferences.currentLiveIDs?[id] = UUID().uuidString }
        var value = state; change(&value.draft); preferences.states[id] = value
        draftSaveStatus = "Salvando alterações…"
        edits.submit(immediate: false) { [weak self] in
            do { try self?.save() }
            catch { self?.draftSaveStatus = "Não foi possível salvar. Tente novamente."; self?.message = error.localizedDescription }
        }
    }
    func flush() { edits.flush() }
    func prepareForApplicationUpdate() throws {
        guard !busy else { throw StudioError.message("Aguarde a operação do YouTube terminar antes de atualizar.") }
        edits.flush()
        // Retry persistence and propagate disk failures instead of losing an unsaved draft.
        try save()
    }
    func selectAccount(_ id: String) {
        guard canOrganizeLibrary, preferences.accounts.contains(where: { $0.id == id }) else { return }
        edits.flush()
        do { try save() } catch { message = error.localizedDescription; return }
        let previous = preferences; let previousBroadcasts = broadcasts
        preferences.selectedAccount = id
        broadcasts = preferences.cachedBroadcasts?[id] ?? []
        do { try save() } catch { preferences = previous; broadcasts = previousBroadcasts; message = error.localizedDescription; return }
        refresh()
    }
    @discardableResult func selectBroadcast(_ id: String) -> Bool {
        guard canOrganizeLibrary, let account, !hiddenBroadcastIDs.contains(id) else { return false }
        if id.isEmpty { return newDraft() }
        edits.flush()
        do { try save() } catch { message = error.localizedDescription; return false }
        let previous = preferences
        if let existing = savedLives.first(where: { $0.state.createdBroadcast == id }) {
            preferences.currentLiveIDs?[account.id] = existing.id
            var value = existing.state; value.selectedBroadcast = id
            preferences.states[account.id] = value
        } else {
            var value = YouTubeDraftState(); value.selectedBroadcast = id; value.createdBroadcast = id
            if let event = broadcasts.first(where: { $0.id == id }) {
                value.draft.title = event.title; value.draft.description = event.description; value.draft.privacy = event.privacy
            }
            preferences.currentLiveIDs?[account.id] = UUID().uuidString
            preferences.states[account.id] = value
        }
        do { try save(); return true }
        catch { preferences = previous; message = error.localizedDescription; return false }
    }
    @discardableResult func newDraft() -> Bool {
        guard canOrganizeLibrary, let account else { return false }
        edits.flush()
        do { try save() } catch { message = error.localizedDescription; return false }
        let previous = preferences
        preferences.currentLiveIDs?[account.id] = UUID().uuidString
        preferences.states[account.id] = YouTubeDraftState()
        do { try save(); message = "Nova preparação. Suas outras lives continuam salvas."; return true }
        catch { preferences = previous; message = error.localizedDescription; return false }
    }
    func disconnect() {
        guard !busy, let account else { return }
        do {
            try vault.delete(account.tokenAccount); tokens[account.id] = nil
            preferences.accounts.removeAll { $0.id == account.id }
            // Preserve channel-scoped preparations for a later reconnect.
            preferences.selectedAccount = preferences.accounts.first?.id
            broadcasts = preferences.selectedAccount.flatMap { preferences.cachedBroadcasts?[$0] } ?? []; try save()
            message = "Conta removida deste Mac. As lives no YouTube foram preservadas."
        } catch { message = "Não foi possível remover a conexão local do YouTube." }
    }
    func chooseThumbnail() {
        guard canEditDraft else { return }
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
        run {
            self.broadcasts = try await self.api.broadcasts(token: self.accessToken(account.id))
            try self.save(); self.message = "Lista de lives atualizada."
        }
    }
    private func save() throws {
        guard writable else { throw StudioError.message("O arquivo do YouTube precisa ser recuperado antes de editar.") }
        storeCurrentLive()
        if let account {
            if preferences.cachedBroadcasts == nil { preferences.cachedBroadcasts = [:] }
            preferences.cachedBroadcasts?[account.id] = broadcasts
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
        draftSaveStatus = "Alterações salvas neste Mac"
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
        guard canOrganizeLibrary, let account else { message = "Conecte o canal e aguarde a operação atual."; return }
        guard state.selectedBroadcast == nil else { message = "Esta live já está criada. Prepare outra live para fazer um novo agendamento."; return }
        let draft = state.draft
        guard state.createdBroadcast != nil || draft.scheduledAt > Date() else { message = "Escolha uma data e hora futuras para agendar."; return }
        run {
            let event = try await self.ensureCreated(account: account.id, draft: draft, scheduled: true)
            self.preferences.states[account.id]?.selectedBroadcast = event.id
            self.broadcasts.removeAll { $0.id == event.id }; self.broadcasts.append(event); try self.save()
            // Creation is already durable even if refreshing the remote list fails.
            self.broadcasts = try await self.api.broadcasts(token: self.accessToken(account.id)); try self.save()
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
            journal.createdBroadcast = broadcast.id; journal.creationUncertain = false; preferences.states[id] = journal
            broadcasts.removeAll { $0.id == broadcast.id }; broadcasts.append(broadcast); try save()
        }
        guard ["created","ready","testStarting","testing"].contains(broadcast.lifeCycle) else { throw StudioError.message("Essa live não está mais disponível para iniciar. Crie um novo rascunho.") }
        try await api.updateVideo(broadcast.id, draft: draft, token: token)
        if let file = thumbnailURL(draft.thumbnailFile) { try await api.thumbnail(broadcast.id, data: Data(contentsOf: file), token: token) }
        _ = try await ensureBound(broadcast, account: id, token: token)
        let prepared = try await api.broadcast(broadcast.id, token: token)
        preferences.states[id]?.preparationComplete = true; try save()
        return prepared
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
        busy = true; defer { busy = false }
        if let selected = state.selectedBroadcast {
            let event = try await api.broadcast(selected, token: accessToken(account.id))
            guard event.canTransmit else { throw StudioError.message("Esta live já foi encerrada. Escolha outra live.") }
            if let index = broadcasts.firstIndex(where: { $0.id == event.id }) { broadcasts[index] = event } else { broadcasts.append(event) }
            return LiveLaunch(channel: account.name, title: event.title, thumbnailURL: event.thumbnailURL.flatMap(URL.init(string:)), server: "YouTube • RTMPS", key: "", youtubeAccount: account.id, broadcastID: event.id, privacy: event.privacy, latency: event.latency)
        }
        guard state.createdBroadcast == nil, !state.creationUncertain else { throw StudioError.message("Confira a criação anterior no YouTube antes de transmitir. Atualize a lista e selecione a live correspondente.") }
        try state.draft.validate(); try save()
        return LiveLaunch(channel: account.name, title: state.draft.title, thumbnailURL: thumbnailURL(state.draft.thumbnailFile), server: "YouTube • RTMPS", key: "", youtubeAccount: account.id, broadcastID: nil, privacy: state.draft.privacy, localLiveID: currentLiveID, confirmedDraft: state.draft, latency: state.draft.latency)
    }
    func prepare(_ launch: LiveLaunch) async throws -> LiveLaunch {
        guard !busy, let id = launch.youtubeAccount, id == account?.id else { throw StudioError.message("A seleção do canal mudou. Confirme a transmissão novamente.") }
        if let selected = launch.broadcastID {
            guard state.selectedBroadcast == selected else { throw StudioError.message("A live selecionada mudou. Confirme a transmissão novamente.") }
        } else {
            guard launch.localLiveID == currentLiveID, launch.confirmedDraft == state.draft else { throw StudioError.message("Os dados da live mudaram. Confirme a transmissão novamente.") }
        }
        busy = true; defer { busy = false }
        let token = try await accessToken(id)
        let event: YouTubeBroadcast
        if let selected = launch.broadcastID {
            if state.createdBroadcast == selected, let submitted = state.submittedDraft, state.preparationComplete != true {
                event = try await ensureCreated(account: id, draft: submitted, scheduled: true)
            } else { event = try await api.broadcast(selected, token: token) }
        } else { event = try await ensureCreated(account: id, draft: state.draft, scheduled: false) }
        guard event.title == launch.title, event.privacy == launch.privacy else { throw StudioError.message("O título ou a visibilidade da live mudou no YouTube. Confirme a transmissão novamente.") }
        guard !["complete","revoked","live"].contains(event.lifeCycle) else { throw StudioError.message("Essa live já está em andamento ou foi encerrada. Atualize a seleção.") }
        let streamID = try await ensureBound(event, account: id, token: token)
        let connection = try await api.stream(streamID, token: token)
        guard !connection.active else { throw StudioError.message("Este stream já está recebendo vídeo. Pare o outro envio antes de iniciar pelo Dante.") }
        preferences.states[id]?.selectedBroadcast = event.id; try save()
        var prepared = launch; prepared.server = connection.server; prepared.key = connection.key; prepared.broadcastID = event.id
        prepared.latency = event.latency ?? launch.latency
        return prepared
    }
    func watchStarted(_ launch: LiveLaunch, isSending: @escaping @MainActor () -> Bool) {
        liveShare = LiveShareInfo(launch)
        guard let account = launch.youtubeAccount, let id = launch.broadcastID else { return }
        chat.start(broadcast: id, api: api, access: { [weak self] in
            guard let self else { throw CancellationError() }; return try await self.accessToken(account)
        }, isSending: isSending)
        activity.start(broadcast: id, api: api, access: { [weak self] in
            guard let self else { throw CancellationError() }; return try await self.accessToken(account)
        }, isSending: isSending)
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
    func reconnectChat(isSending: @escaping @MainActor () -> Bool) {
        guard let event = activeEvent else { return }
        chat.start(broadcast: event.broadcast, api: api, access: { [weak self] in
            guard let self else { throw CancellationError() }; return try await self.accessToken(event.account)
        }, isSending: isSending, preserveQueue: true)
    }
    func endActive() {
        activity.reset(); chat.reset()
        liveShare = nil
        livePoll?.cancel(); remoteLive = false
        guard let event = activeEvent else { return }; activeEvent = nil
        Task { [weak self] in
            guard let self else { return }
            do { try await self.api.transition(event.broadcast, status: "complete", token: self.accessToken(event.account)); self.message = "Live encerrada no YouTube." }
            catch { self.message = "O envio foi parado, mas confirme o encerramento no YouTube Studio. \(error.localizedDescription)" }
        }
    }
}
