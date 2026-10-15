import Foundation
import Combine

struct LiveVideoSettings: Codable, Equatable {
    var width = 1920
    var height = 1080
    var fps = 30
    var bitrate = 14000
    var audioBitrate = 128
    var encoder = ""
    func validate() throws {
        guard (16...8192).contains(width), (16...8192).contains(height), width % 2 == 0, height % 2 == 0,
              (1...120).contains(fps), (100...200000).contains(bitrate), [128,160,192,256,320].contains(audioBitrate),
              encoder.count < 512 else { throw StudioError.message("Use dimensões pares entre 16 e 8192, FPS entre 1 e 120 e bitrate entre 100 e 200.000 kbps.") }
    }
}
struct NamedLivePreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var video: LiveVideoSettings
}
struct SavedLiveChannel: Codable, Identifiable {
    var id = UUID()
    var name: String
    var server: String
    var keyAccount: String
}
struct LiveSettingsDocument: Codable {
    var version = 1
    var video = LiveVideoSettings()
    var server = ""
    var rememberKey = true
    var keyAccount = "live-\(UUID().uuidString)"
    var uploadMbps = 0.0
    var uploadMeasuredAt: Date?
    var selection = "custom"
    var presets: [NamedLivePreset] = []
    var channels: [SavedLiveChannel]?
    var selectedChannelID: UUID?
    var youtubeMode: Bool?
    var microphoneAlerts = true
    var audioWatchOverrides: [String: Bool] = [:]
    func validate() throws {
        try video.validate()
        guard version == 1, uploadMbps.isFinite, (0...100_000).contains(uploadMbps), presets.count <= 100,
              Set(presets.map(\.id)).count == presets.count,
              keyAccount.hasPrefix("live-"), UUID(uuidString: String(keyAccount.dropFirst(5))) != nil else {
            throw StudioError.message("Configurações da live inválidas ou incompatíveis.")
        }
        if !server.isEmpty {
            guard let url = URLComponents(string: server), ["rtmp", "rtmps"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw StudioError.message("Informe um servidor RTMP/RTMPS sem usuário, senha ou parâmetros. Use o campo Chave para a credencial.")
            }
        }
        let savedChannels = channels ?? []
        guard savedChannels.count <= 100, Set(savedChannels.map(\.id)).count == savedChannels.count,
              Set(savedChannels.map(\.keyAccount)).count == savedChannels.count else { throw StudioError.message("Lista de canais inválida.") }
        for channel in savedChannels {
            guard !channel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, channel.name.count <= 80,
                  channel.keyAccount.hasPrefix("live-"), UUID(uuidString: String(channel.keyAccount.dropFirst(5))) != nil,
                  let url = URLComponents(string: channel.server), ["rtmp", "rtmps"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw StudioError.message("Nome ou conexão do canal inválidos.")
            }
        }
        if let selectedChannelID {
            guard savedChannels.contains(where: { $0.id == selectedChannelID && $0.keyAccount == keyAccount }) else { throw StudioError.message("O canal selecionado não corresponde à chave salva.") }
        }
        for preset in presets {
            guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, preset.name.count <= 80 else { throw StudioError.message("O nome do preset deve ter entre 1 e 80 caracteres.") }
            try preset.video.validate()
        }
    }
}
struct LiveSettingsStore {
    let url: URL
    func load() throws -> LiveSettingsDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(LiveSettingsDocument.self, from: Data(contentsOf: url))
        try value.validate(); return value
    }
    func save(_ value: LiveSettingsDocument) throws {
        try value.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

struct LiveKeyVault {
    var read: (String) throws -> String
    var save: (String, String) throws -> Void
    var delete: (String) throws -> Void
    static var system: Self { Self(read: { try SecretStore.read(account: $0) }, save: { try SecretStore.save($0, account: $1) }, delete: { try SecretStore.delete(account: $0) }) }
}

@MainActor final class LiveSettingsModel: ObservableObject {
    @Published private(set) var document: LiveSettingsDocument
    @Published private(set) var key = ""
    @Published private(set) var status = "Configurações salvas automaticamente"
    @Published private(set) var problem: String?
    private weak var model: StudioModel?
    private let store: LiveSettingsStore
    private let vault: LiveKeyVault
    private let queue = PropertyEditQueue()
    private var keyDirty = false
    private var readOnly = false
    private var loadedKey = false

    init(model: StudioModel, store: LiveSettingsStore? = nil, vault: LiveKeyVault = .system) {
        self.model = model; self.vault = vault
        let directory = model.projectDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dante Live")
        self.store = store ?? LiveSettingsStore(url: directory.appendingPathComponent("live-settings.json"))
        var initial = LiveSettingsDocument()
        initial.video = LiveVideoSettings(width: Int(model.canvasWidth), height: Int(model.canvasHeight), fps: Int(model.state.number("fps", 30)), bitrate: model.outputConfiguration.bitrate, audioBitrate: model.outputConfiguration.audioBitrate, encoder: model.outputConfiguration.encoder)
        initial.uploadMbps = model.outputConfiguration.uploadMbps ?? 0
        initial.uploadMeasuredAt = model.outputConfiguration.uploadMeasuredAt
        do { document = try self.store.load() ?? initial }
        catch { document = initial; readOnly = true; problem = "Não foi possível ler as configurações. O arquivo foi preservado; restaure-o antes de editar." }
        syncOutputConfiguration()
    }
    var video: LiveVideoSettings { document.video }
    var pendingVideo: Bool {
        guard let model else { return false }
        return Int(model.canvasWidth) != video.width || Int(model.canvasHeight) != video.height || Int(model.state.number("fps")) != video.fps
    }
    var selectedQuality: LiveQuality? { LiveQuality(rawValue: document.selection) }
    var recommendation: LiveRecommendation? { selectedQuality.map { LiveRecommendation(quality: $0, fps: video.fps, uploadMbps: document.uploadMbps > 0 ? document.uploadMbps : nil) } }

    func edit(_ change: (inout LiveSettingsDocument) -> Void, immediate: Bool = false, custom: Bool = false) {
        guard !readOnly else { return }
        change(&document)
        if custom { document.selection = "custom" }
        status = "Salvando…"
        queue.submit(immediate: immediate) { [weak self] in _ = self?.commit() }
    }
    func editVideo<T>(_ path: WritableKeyPath<LiveVideoSettings, T>, _ value: T, immediate: Bool = false) {
        edit({ $0.video[keyPath: path] = value }, immediate: immediate, custom: true)
    }
    func choose(_ selection: String) {
        if let quality = LiveQuality(rawValue: selection) {
            let r = LiveRecommendation(quality: quality, fps: video.fps, uploadMbps: document.uploadMbps > 0 ? document.uploadMbps : nil)
            edit({ d in
                d.selection = selection
                d.video = LiveVideoSettings(width: quality.width, height: quality.height, fps: r.fps, bitrate: max(r.minimumBitrate, r.bitrate), audioBitrate: r.audioBitrate, encoder: model?.catalog.string("defaultEncoder") ?? "")
            }, immediate: true)
        } else if let preset = document.presets.first(where: { $0.id.uuidString == selection }) {
            edit({ $0.selection = selection; $0.video = preset.video }, immediate: true)
        } else { edit({ $0.selection = "custom" }, immediate: true) }
    }
    func changeFPS(_ fps: Int) {
        if let quality = selectedQuality, [30,60].contains(fps) {
            document.video.fps = fps; choose(quality.rawValue)
        } else { editVideo(\.fps, fps, immediate: true) }
    }
    func setUpload(_ value: Double, measuredAt: Date? = nil, immediate: Bool = false) {
        edit({ d in
            d.uploadMbps = value; d.uploadMeasuredAt = measuredAt
            if let quality = LiveQuality(rawValue: d.selection) {
                let r = LiveRecommendation(quality: quality, fps: d.video.fps, uploadMbps: value > 0 ? value : nil)
                d.video.bitrate = max(r.minimumBitrate, r.bitrate)
            }
        }, immediate: immediate)
    }
    @discardableResult func savePreset(name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { problem = "Digite um nome de 1 a 80 caracteres."; return false }
        guard document.presets.count < 100 else { problem = "Limite de 100 presets atingido."; return false }
        guard !document.presets.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            problem = "Já existe um preset com esse nome. Escolha outro nome."; return false
        }
        queue.cancel()
        let previous = document
        let preset = NamedLivePreset(name: name, video: video)
        document.presets.append(preset); document.selection = preset.id.uuidString
        if commit() { return true }
        document = previous; return false
    }
    var suggestedPresetName: String {
        var index = 1
        while document.presets.contains(where: { $0.name.compare("Preset personalizado \(index)", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) { index += 1 }
        return "Preset personalizado \(index)"
    }
    var selectedPreset: NamedLivePreset? { document.presets.first { $0.id.uuidString == document.selection } }
    func renamePreset(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !document.presets.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { problem = "Escolha um nome único de até 80 caracteres."; return }
        edit({ d in if let index = d.presets.firstIndex(where: { $0.id == id }) { d.presets[index].name = name } }, immediate: true)
    }
    func useSuggestion(_ diagnosis: ConnectionDiagnosis) {
        guard !readOnly, let quality = diagnosis.suggestedQuality else { return }
        document.video.fps = diagnosis.suggestedFPS; choose(quality.rawValue)
    }
    var channels: [SavedLiveChannel] { document.channels ?? [] }
    var selectedChannel: SavedLiveChannel? { channels.first { $0.id == document.selectedChannelID } }
    @discardableResult func saveChannel(name: String) -> Bool {
        guard !readOnly else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, channels.count < 100,
              !channels.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { problem = "Escolha um nome único de até 80 caracteres para o canal."; return false }
        loadKey()
        guard !key.isEmpty, !document.server.isEmpty, document.rememberKey else { problem = "Informe servidor e chave e ative Salvar chave para guardar este canal."; return false }
        queue.cancel()
        guard commit() else { return false }
        let previous = document
        let channel = SavedLiveChannel(name: name, server: document.server, keyAccount: "live-\(UUID().uuidString)")
        document.channels = channels + [channel]; document.selectedChannelID = channel.id; document.keyAccount = channel.keyAccount
        keyDirty = true
        guard commit() else {
            document = previous; keyDirty = false
            try? vault.delete(channel.keyAccount)
            return false
        }
        if !(previous.channels ?? []).contains(where: { $0.keyAccount == previous.keyAccount }) {
            do { try vault.delete(previous.keyAccount) }
            catch { problem = "Canal salvo. Não foi possível remover a chave antiga sem nome do Acesso às Chaves." }
        }
        status = "Canal “\(name)” salvo"
        return true
    }
    func selectChannel(_ id: UUID?) {
        guard !readOnly else { return }
        queue.cancel()
        guard commit() else { return }
        let previous = document; let previousKey = key
        do {
            if let id {
                guard let channel = channels.first(where: { $0.id == id }) else { return }
                let savedKey = try vault.read(channel.keyAccount)
                document.selectedChannelID = id; document.server = channel.server; document.keyAccount = channel.keyAccount; document.rememberKey = true
                key = savedKey
            } else {
                document.selectedChannelID = nil; document.server = ""; document.keyAccount = "live-\(UUID().uuidString)"; document.rememberKey = true; key = ""
            }
            loadedKey = true; keyDirty = false
            if !commit() { document = previous; key = previousKey; return }
            if id != nil && key.isEmpty { problem = "Este canal está sem chave salva. Digite a chave de transmissão." }
        } catch { problem = "Não foi possível acessar a chave desse canal. A conexão anterior foi mantida." }
    }
    func renameChannel(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !channels.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { problem = "Escolha um nome único de até 80 caracteres."; return }
        edit({ d in if let index = d.channels?.firstIndex(where: { $0.id == id }) { d.channels?[index].name = name } }, immediate: true)
    }
    func deleteChannel(_ id: UUID) {
        guard !readOnly, let channel = channels.first(where: { $0.id == id }) else { return }
        queue.cancel()
        guard commit() else { return }
        let previous = document; let previousKey = key
        document.channels = channels.filter { $0.id != id }
        if document.selectedChannelID == id {
            document.selectedChannelID = nil; document.server = ""; document.keyAccount = "live-\(UUID().uuidString)"; key = ""; keyDirty = false
        }
        guard commit() else { document = previous; key = previousKey; return }
        do { try vault.delete(channel.keyAccount) }
        catch { problem = "Canal removido da lista, mas sua chave não pôde ser apagada do Acesso às Chaves." }
    }
    func removePreset(_ id: UUID) {
        edit({ d in d.presets.removeAll { $0.id == id }; if d.selection == id.uuidString { d.selection = "custom" } }, immediate: true)
    }
    func loadKey() {
        guard !loadedKey else { return }; loadedKey = true
        guard document.rememberKey else { return }
        do { key = try vault.read(document.keyAccount) }
        catch { problem = "Não foi possível ler a chave no Acesso às Chaves. Tente novamente ou digite a chave."; loadedKey = false }
    }
    func editKey(_ value: String) {
        guard !readOnly else { return }
        loadedKey = true; key = value; keyDirty = true
        edit({ _ in })
    }
    func rememberKey(_ enabled: Bool) {
        if enabled && !loadedKey { loadKey() }
        keyDirty = true
        edit({ $0.rememberKey = enabled }, immediate: true)
    }
    func flush() { queue.flush() }
    private func syncOutputConfiguration() {
        model?.outputConfiguration.bitrate = video.bitrate
        model?.outputConfiguration.audioBitrate = video.audioBitrate
        model?.outputConfiguration.encoder = video.encoder
        model?.outputConfiguration.uploadMbps = document.uploadMbps > 0 ? document.uploadMbps : nil
        model?.outputConfiguration.uploadMeasuredAt = document.uploadMeasuredAt
    }
    @discardableResult private func commit() -> Bool {
        guard !readOnly else { return false }
        do {
            if let id = document.selectedChannelID, let index = document.channels?.firstIndex(where: { $0.id == id }) {
                document.channels?[index].server = document.server
            }
            try document.validate()
            if keyDirty {
                if document.rememberKey { try vault.save(key, document.keyAccount) }
                else { try vault.delete(document.keyAccount) }
                keyDirty = false
            }
            try store.save(document)
            problem = nil; syncOutputConfiguration()
            status = model?.active == true ? "Salvo para a próxima live; a transmissão atual não foi alterada" : "Configurações salvas"
            if model?.active == false { _ = applyVideo() }
            return true
        } catch { problem = "Não salvo: \(error.localizedDescription)"; status = "Alterações pendentes"; return false }
    }
    @discardableResult private func applyVideo() -> Bool {
        guard let model else { return false }
        if !pendingVideo { return true }
        guard !model.active else { return false }
        if model.command("video.configure", ["width": video.width, "height": video.height, "fps": video.fps]) { model.save(); return true }
        problem = "Configuração salva, mas o vídeo não foi aplicado. \(model.error ?? "Tente novamente antes de iniciar a live.")"
        return false
    }
    func prepareStream() -> Bool {
        guard prepareVideo() else { return false }
        guard !document.server.isEmpty, !key.isEmpty else { problem = "Informe o servidor e a chave de transmissão."; return false }
        return true
    }
    func prepareVideo() -> Bool {
        queue.cancel()
        guard commit(), applyVideo(), let model else { return false }
        guard model.catalog.array("encoders").contains(where: { $0.string("id") == video.encoder && $0.string("codec") == "h264" }) else {
            problem = "O encoder salvo não está disponível neste Mac. Escolha um encoder na aba Vídeo e áudio."; return false
        }
        return true
    }
}
