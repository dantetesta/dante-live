import AppKit
import SwiftUI
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// A reconnecting or stopping output still belongs to the current live. Only
/// a fully idle output ends the guest room and invalidates its invitations.
struct GuestRoomStreamLifecycle {
    private var awaitingEnd = false

    mutating func stopRequested() { awaitingEnd = true }

    mutating func ended(_ output: [String: Any]) -> Bool {
        if output.flag("started") { awaitingEnd = true }
        guard awaitingEnd,
              !output.flag("busy"), !output.flag("active"),
              !output.flag("starting"), !output.flag("stopping"),
              !output.flag("reconnecting"), !output.flag("started") else { return false }
        awaitingEnd = false
        return true
    }
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var state: [String: Any] = [:]
    @Published var catalog: [String: Any] = [:]
    @Published var selectedItem: Int64? {
        didSet { if selectedItem != oldValue { framingItem = nil } }
    }
    // Editor state only, never persisted or sent to the program renderer.
    @Published var framingItem: Int64?
    @Published var error: String?
    @Published var notice = "Pronto para criar"
    @Published var studioMode = false
    @Published var showingAdd = false
    @Published var showingProfiles = false
    @Published private(set) var profiles: [ProductionProfile] = []
    @Published private(set) var selectedProfileID = "default"
    @Published var showingChat = false
    let chatRenderer = ChatOverlayRenderer()
    @Published var showingGuests = false
    @Published var showingOutput = false
    @Published var outputTab = "quality"
    @Published var showingFilters = false
    @Published var showingCamera = false
    @Published var showingProperties = false
    @Published var cameraSourceName = ""
    @Published var inspectorRevision = 0
    @Published var undoCount = 0
    @Published var redoCount = 0
    @Published var outputConfiguration = OutputConfiguration.load()
    let countdown = LiveCountdown()
    @Published var microphoneWarnings: [String] = []
    private var silenceWatch = MicrophoneSilenceWatch()
    lazy var guests = GuestModel(studio: self)
    lazy var browserTabAudio = BrowserTabAudioModel(studio: self)
    lazy var liveSettings = LiveSettingsModel(model: self)
    lazy var youtube = YouTubeModel(directory: projectDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dante Live"))
    @Published var pendingLive: LiveLaunch?
    @Published var showingLiveLibrary = false
    private var continueAfterLiveLibrary = false
    @Published var preparingLive = false
    @Published var updateInstalling = false
    @Published var pendingUpdateMessage: String?
    // An open guest room must postpone installation, but it does not prevent
    // checking whether an update exists after the stream has ended.
    var updateCheckBlocked: Bool { active || preparingLive || countdown.remaining != nil || pendingLive != nil || showingLiveLibrary || continueAfterLiveLibrary || youtube.busy }
    var liveOperationInProgress: Bool { guests.inUse || updateCheckBlocked }
    private var launchTask: Task<Void, Never>?
    var engine: OpaquePointer?
    private var timer: Timer?
    private var saveTask: Task<Void, Never>?
    private var store: ProjectStore?
    private var profileIndex: ProductionProfiles?
    private var blankProjectJSON = ""
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private var starting = false
    private var reportedOutputFailures: [String: Int] = [:]
    private var outputStartedAt: [String: Date] = [:]
    private var guestRoomStreamLifecycle = GuestRoomStreamLifecycle()
    var preserveFailedProject = false
    let projectDirectory: URL?
    let engineBundlePath: String
    init(projectDirectory: URL? = nil, engineBundlePath: String = Bundle.main.bundlePath) {
        self.projectDirectory = projectDirectory
        self.engineBundlePath = engineBundlePath
    }

    var scenes: [[String: Any]] { state.array("scenes") }
    var sceneName: String { state.string("selectedScene", scenes.first?.string("name") ?? "") }
    var items: [[String: Any]] { scenes.first(where: { $0.string("name") == sceneName })?.array("items") ?? [] }
    var listedSources: [[String:Any]] { items.filter { !guests.managedSourceNames.contains($0.string("name")) } }
    var reusableSourceNames: [String] {
        let names = Set(scenes.flatMap { $0.array("items").map { $0.string("name") } } + scenes.map { $0.string("name") })
        // A -> B is invalid if B already reaches A, including indirect nesting.
        func reachesCurrent(_ name: String, visited: Set<String>) -> Bool {
            if name == sceneName { return true }
            guard !visited.contains(name), let scene = scenes.first(where: { $0.string("name") == name }) else { return false }
            return scene.array("items").contains { reachesCurrent($0.string("name"), visited: visited.union([name])) }
        }
        return names.filter { !reachesCurrent($0, visited: []) && !guests.managedSourceNames.contains($0) }.sorted()
    }

    var selected: [String: Any]? { items.first { $0.sceneItemID == selectedItem } }
    var selectedName: String { selected?.string("name") ?? "" }
    var recording: Bool { state.flag("recording") || state.object("outputs").object("recording").flag("active") }
    var streaming: Bool { state.flag("streaming") || state.object("outputs").object("stream").flag("active") }
    var replaying: Bool { state.flag("replaying") || state.object("outputs").object("replay").flag("active") }
    var active: Bool {
        recording || streaming || replaying || ["recording", "stream", "replay"].contains {
            let output = state.object("outputs").object($0)
            return output.flag("starting") || output.flag("stopping") || output.flag("reconnecting") || output.flag("busy")
        }
    }
    var canvasWidth: Double { state.number("width", 1280) }
    var canvasHeight: Double { state.number("height", 720) }
    var selectedProfileName: String { profiles.first(where: { $0.id == selectedProfileID })?.name ?? "Meu estúdio" }
    var canSwitchProfile: Bool { engine != nil && !liveOperationInProgress && !updateInstalling && !preserveFailedProject }

    func start() {
        guard engine == nil, !starting else { return }
        starting = true
        defer { starting = false }
        if let projectDirectory {
            engine = dante_engine_create_with_config(engineBundlePath, 1920, 1080, 30, projectDirectory.appendingPathComponent("engine").path)
        } else { engine = dante_engine_create(engineBundlePath, 1920, 1080, 30) }
        guard let engine else { error = copied(dante_engine_last_error(nil)); return }
        blankProjectJSON = copied(dante_engine_save(engine))
        catalog = jsonObject(copied(dante_engine_catalog(engine)))
        if !catalog.array("encoders").contains(where: { $0.string("id") == outputConfiguration.encoder }) {
            outputConfiguration.encoder = catalog.string("defaultEncoder")
        }
        restoreProfile()
        refresh()
        if scenes.isEmpty { _ = command("scene.create", ["name": "Cena principal"], undo: false) }
        _ = liveSettings
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func restoreProfile() {
        guard let engine else { return }
        if blankProjectJSON.isEmpty { blankProjectJSON = copied(dante_engine_save(engine)) }
        do {
            let base = projectDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dante Live", isDirectory: true)
            let index = try ProductionProfiles(directory: base)
            guard let directory = index.directory(for: index.selectedID) else { throw StudioError.message("Perfil ativo não encontrado.") }
            profileIndex = index
            profiles = index.profiles
            selectedProfileID = index.selectedID
            store = try ProjectStore(directory: directory)
            if let saved = try store?.load() {
                try validateNoInlineSecrets(jsonObject(saved.json))
                if dante_engine_load(engine, saved.json) {
                    if saved.recovered { try store?.preserveRejectedCurrent() }
                    notice = saved.recovered ? "Projeto recuperado da cópia anterior" : "Projeto restaurado"
                } else if let previous = try store?.previous() {
                    try validateNoInlineSecrets(jsonObject(previous))
                    guard dante_engine_load(engine, previous) else { throw StudioError.message(copied(dante_engine_last_error(engine))) }
                    try store?.preserveRejectedCurrent()
                    notice = "Projeto recuperado; arquivo inválido preservado"
                } else { throw StudioError.message(copied(dante_engine_last_error(engine))) }
            } else if index.selectedID != "default" {
                throw StudioError.message("O projeto deste perfil está ausente. Os demais perfis foram preservados.")
            }
        } catch { preserveFailedProject = true; self.error = error.localizedDescription }
    }

    func refresh() {
        guard let engine else { return }
        let pending = Set(scenes.flatMap { scene in
            scene.array("items").filter { $0.flag("pendingPlacement") }.map { scene.string("name") + ":" + String($0.sceneItemID) }
        })
        state = jsonObject(copied(dante_engine_state(engine)))
        browserTabAudio.prune(validSources: Set(scenes.flatMap { $0.array("items") }
            .filter { $0.string("type") == "dante_browser_tab_audio" }.map { $0.string("name") }))
        let closeGuestRoom = guestRoomStreamLifecycle.ended(state.object("outputs").object("stream"))
        if !pending.isEmpty {
            let resolved = scenes.contains { scene in scene.array("items").contains { item in
                !item.flag("pendingPlacement") && pending.contains(scene.string("name") + ":" + String(item.sceneItemID))
            } }
            if resolved { scheduleSave() }
        }
        for key in ["recording", "stream", "replay"] {
            let output = state.object("outputs").object(key)
            let code = Int(output.number("code"))
            if output.flag("started"), outputStartedAt[key] == nil { outputStartedAt[key] = Date(); if key == "stream" { notice = "Ao vivo • transmissão iniciada" } }
            if !output.flag("active") { if key == "stream", outputStartedAt[key] != nil { notice = "Transmissão encerrada" }; outputStartedAt[key] = nil }
            if code != 0, reportedOutputFailures[key] != code {
                reportedOutputFailures[key] = code
                let label = ["recording": "Gravação", "stream": "Transmissão", "replay": "Replay"][key] ?? key
                let message = output.string("error")
                error = "\(label) interrompida (código \(code)). " + (message.isEmpty ? "Verifique disco, encoder e conexão nas configurações de saída." : message)
            } else if code == 0 { reportedOutputFailures[key] = nil }
        }
        let programScene = state.string("programScene")
        let programAudio = scenes.first(where: { $0.string("name") == programScene })?.array("items").filter { $0.flag("visible") && $0.flag("audio") } ?? []
        let programAudioIDs = Set(programAudio.map { $0.string("sourceUUID", $0.string("name")) })
        let uniqueAudio = Dictionary(scenes.flatMap { $0.array("items") }.filter { $0.flag("audio") }.map { ($0.string("sourceUUID", $0.string("name")), $0) }, uniquingKeysWith: { first, _ in first })
        let samples = uniqueAudio.map { id, source in
            // A disconnected input may report sourceActive=false. Keep watching
            // it while its visible scene is on air, or silence will reset the
            // timer precisely when the lapel microphone dies.
            let onAir = microphoneOnAir(source, programAudioIDs: programAudioIDs)
            return MicrophoneSample(id: id, name: source.string("name"), enabled: liveSettings.document.microphoneAlerts && watchesMicrophone(source) && onAir && !source.flag("muted") && source.number("volume", 1) > 0 && Int(source.number("tracks", 1)) & 1 != 0 && Int(source.number("monitoring")) != 1, signalAge: source.number("signalAge", -1) >= 0 ? source.number("signalAge") : nil)
        }
        let warnings = silenceWatch.update(samples, live: state.object("outputs").object("stream").flag("started"), now: ProcessInfo.processInfo.systemUptime)
        if warnings != microphoneWarnings { microphoneWarnings = warnings }
        let streamOutput = state.object("outputs").object("stream")
        if youtube.chat.sessionActive && !streaming && !streamOutput.flag("starting") && !streamOutput.flag("reconnecting") && !streamOutput.flag("busy") { youtube.chat.reset() }
        youtube.chat.updateDemand(programVisible: streaming && ProgramChatVisibility.containsActiveChat(scenes: scenes), panelOpen: showingChat)
        chatRenderer.update(studio: self)
        if let id = selectedItem, !items.contains(where: { $0.sceneItemID == id }) { selectedItem = nil }
        if closeGuestRoom {
            guests.stop()
            notice = "Transmissão encerrada • convites revogados"
        }
    }
    func watchesMicrophone(_ source: [String: Any]) -> Bool {
        liveSettings.document.audioWatchOverrides[source.string("sourceUUID", source.string("name"))] ?? source.string("type").contains("coreaudio_input")
    }
    func fitSelectedSource() {
        guard let item = selected, !item.flag("locked"), !updateInstalling else { return }
        _ = command("item.fit", ["scene": sceneName, "id": item.sceneItemID])
    }
    func setMicrophoneWatch(_ source: [String: Any], enabled: Bool) {
        let id = source.string("sourceUUID", source.string("name"))
        liveSettings.edit({ $0.audioWatchOverrides[id] = enabled }, immediate: true)
        refresh()
    }
    func beginLive() {
        guard !active, !preparingLive, !updateInstalling, countdown.remaining == nil, pendingLive == nil, !showingLiveLibrary else { return }
        if liveSettings.document.youtubeMode == true {
            guard youtube.account != nil else { outputTab = "youtube"; showingOutput = true; return }
            showingLiveLibrary = true
        } else {
            liveSettings.loadKey()
            guard liveSettings.prepareStream() else { outputTab = "connection"; showingOutput = true; return }
            let title = liveSettings.manualDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingLive = LiveLaunch(channel: liveSettings.selectedChannel?.name ?? "Conexão RTMP", title: title.isEmpty ? "Live configurada no serviço de destino" : title, thumbnailURL: liveSettings.manualCoverURL, server: liveSettings.document.server, key: liveSettings.key)
        }
    }
    func transmitSelectedFromSettings() {
        guard !active, !preparingLive, !updateInstalling, !youtube.busy, countdown.remaining == nil, pendingLive == nil else { return }
        liveSettings.edit({ $0.youtubeMode = true }, immediate: true)
        continueAfterLiveLibrary = true
        showingOutput = false
    }
    func continueFromLiveLibrary() {
        guard showingLiveLibrary, !active, !preparingLive, !updateInstalling, !youtube.busy else { return }
        continueAfterLiveLibrary = true
        showingLiveLibrary = false
    }
    func liveLibraryDismissed() {
        guard continueAfterLiveLibrary else { return }
        continueAfterLiveLibrary = false
        guard !active, !preparingLive, !updateInstalling, countdown.remaining == nil, liveSettings.document.youtubeMode == true else { return }
        guard liveSettings.prepareVideo() else { outputTab = "video"; showingOutput = true; return }
        preparingLive = true
        launchTask = Task { [weak self] in
            guard let self else { return }; defer { self.preparingLive = false }
            do { self.pendingLive = try await self.youtube.confirmation(); try Task.checkCancellation() }
            catch { self.pendingLive = nil; self.youtube.message = error.localizedDescription; self.outputTab = "broadcast"; self.showingOutput = true }
        }
    }
    func confirmLive(_ selection: LiveLaunch) {
        pendingLive = nil
        guard !active, !preparingLive, !updateInstalling, liveSettings.prepareVideo() else { return }
        preparingLive = true
        let video = liveSettings.video
        launchTask = Task { [weak self] in
            guard let self else { return }; defer { self.preparingLive = false }
            do {
                try selection.validateVideoLatency(video)
                let launch = selection.youtubeAccount == nil ? selection : try await self.youtube.prepare(selection)
                try launch.validateVideoLatency(video)
                try Task.checkCancellation()
                self.countdown.start { [weak self] in
                    guard let self, !self.active else { return }
                    guard self.liveSettings.video == video else { self.error = "As configurações mudaram durante a preparação. Confirme a transmissão novamente."; return }
                    if self.command("stream.start", ["server": launch.server, "key": launch.key, "encoder": video.encoder, "bitrate": video.bitrate, "audioBitrate": video.audioBitrate], undo: false) {
                        self.notice = "Conectando ao servidor…"
                        self.youtube.watchStarted(launch) { [weak self] in
                            guard let self else { return false }
                            let output = self.state.object("outputs").object("stream")
                            return self.streaming || output.flag("starting") || output.flag("reconnecting")
                        }
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func endLive() {
        let previousLifecycle = guestRoomStreamLifecycle
        guestRoomStreamLifecycle.stopRequested()
        if command("stream.stop", undo: false) { youtube.endActive() }
        else { guestRoomStreamLifecycle = previousLifecycle }
    }
    var streamStatus: String {
        let output = state.object("outputs").object("stream")
        if output.flag("stopping") { return "FINALIZANDO" }
        if output.flag("reconnecting") { return "RECONECTANDO" }
        if output.flag("started"), youtube.trackingLive, !youtube.remoteLive { return "ENVIANDO • AGUARDANDO YOUTUBE" }
        if output.flag("started") { return "AO VIVO \(duration("stream"))" }
        return "CONECTANDO"
    }
    func duration(_ key: String) -> String {
        guard let start = outputStartedAt[key] else { return "00:00:00" }
        let seconds = Int(Date().timeIntervalSince(start))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    @discardableResult func command(_ operation: String, _ arguments: [String: Any] = [:], undo: Bool = true) -> Bool {
        guard !operation.hasPrefix("recording."), !operation.hasPrefix("replay.") else { error = "O Dante Live é dedicado a transmissões ao vivo."; return false }
        guard let engine else { error = "O motor audiovisual não está disponível."; return false }
        guard JSONSerialization.isValidJSONObject(arguments) else { error = "Há um valor inválido nas propriedades. Informe números finitos e um objeto JSON válido."; return false }
        if operation.hasPrefix("source.") || operation.hasPrefix("filter.") {
            do { try validateNoInlineSecrets(arguments) } catch { self.error = error.localizedDescription; return false }
        }
        let snapshot = undo && !active ? copied(dante_engine_save(engine)) : nil
        guard dante_engine_command(engine, operation, jsonString(arguments)) else {
            error = copied(dante_engine_last_error(engine)); refresh(); return false
        }
        if let snapshot { pushUndo(snapshot) }
        refresh()
        if !operation.hasPrefix("stream.") && !operation.hasPrefix("recording.") && !operation.hasPrefix("replay.") { scheduleSave() }
        return true
    }

    func captureUndo() -> String? { guard let engine, !active else { return nil }; return copied(dante_engine_save(engine)) }
    func pushUndo(_ snapshot: String) {
        undoStack.append(snapshot); if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll(); updateHistory()
    }
    private func updateHistory() { undoCount = undoStack.count; redoCount = redoStack.count }
    func undo() {
        guard !active, !guests.inUse, let engine, let previous = undoStack.last else { return }
        let current = copied(dante_engine_save(engine))
        if dante_engine_load(engine, previous) { chatRenderer.invalidate(); undoStack.removeLast(); redoStack.append(current); updateHistory(); refresh(); inspectorRevision += 1; scheduleSave() }
        else { error = copied(dante_engine_last_error(engine)) }
    }
    func redo() {
        guard !active, !guests.inUse, let engine, let next = redoStack.last else { return }
        let current = copied(dante_engine_save(engine))
        if dante_engine_load(engine, next) { chatRenderer.invalidate(); redoStack.removeLast(); undoStack.append(current); updateHistory(); refresh(); inspectorRevision += 1; scheduleSave() }
        else { error = copied(dante_engine_last_error(engine)) }
    }
    private func scheduleSave() {
        guard !preserveFailedProject else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func prepareForApplicationUpdate() throws {
        refresh()
        guard !liveOperationInProgress else { throw StudioError.message("Finalize a transmissão, a preparação da live ou a sala de convidados antes de atualizar.") }
        liveSettings.flush(); try youtube.prepareForApplicationUpdate()
        if let problem = liveSettings.problem { throw StudioError.message(problem) }
        guard let engine, let store, !preserveFailedProject else { throw StudioError.message("Recupere ou exporte o projeto antes de atualizar.") }
        try store.save(copied(dante_engine_save(engine)))
    }
    func save() {
        guard let engine, !preserveFailedProject else { return }
        do { try store?.save(copied(dante_engine_save(engine))) }
        catch { self.error = "Falha ao salvar: \(error.localizedDescription)" }
    }
    private func requireProfileSwitch() throws -> OpaquePointer {
        refresh()
        guard canSwitchProfile, let engine else {
            throw StudioError.message("Para trocar de perfil, encerre a live e a sala de convidados e conclua a preparação em andamento.")
        }
        guard let store else { throw StudioError.message("O projeto atual não está disponível para salvar.") }
        saveTask?.cancel(); saveTask = nil
        try store.save(copied(dante_engine_save(engine)))
        return engine
    }
    private func finishProfileChange(_ index: ProductionProfiles, store: ProjectStore) {
        profileIndex = index
        self.store = store
        profiles = index.profiles
        selectedProfileID = index.selectedID
        selectedItem = nil
        framingItem = nil
        undoStack.removeAll(); redoStack.removeAll(); updateHistory()
        chatRenderer.invalidate()
        inspectorRevision += 1
        refresh()
        notice = "Perfil carregado: \(index.selected.name)"
    }
    func createProfile(name: String) {
        do {
            let engine = try requireProfileSwitch()
            guard var index = profileIndex else { throw StudioError.message("Catálogo de perfis indisponível.") }
            let previous = copied(dante_engine_save(engine))
            guard dante_engine_load(engine, blankProjectJSON) else { throw StudioError.message(copied(dante_engine_last_error(engine))) }
            do {
                let profile = try index.create(name: name, project: copied(dante_engine_save(engine)))
                guard let directory = index.directory(for: profile.id) else { throw StudioError.message("Pasta do perfil indisponível.") }
                finishProfileChange(index, store: try ProjectStore(directory: directory))
            } catch {
                _ = dante_engine_load(engine, previous)
                refresh()
                throw error
            }
        } catch { self.error = error.localizedDescription }
    }
    func selectProfile(_ id: String) {
        guard id != selectedProfileID else { return }
        do {
            let engine = try requireProfileSwitch()
            guard var index = profileIndex, let directory = index.directory(for: id) else { throw StudioError.message("Perfil não encontrado.") }
            let targetStore = try ProjectStore(directory: directory)
            guard let saved = try targetStore.load() else { throw StudioError.message("Este perfil não contém um projeto salvo.") }
            try validateNoInlineSecrets(jsonObject(saved.json))
            let previous = copied(dante_engine_save(engine))
            guard dante_engine_load(engine, saved.json) else { throw StudioError.message(copied(dante_engine_last_error(engine))) }
            do {
                if saved.recovered { try targetStore.preserveRejectedCurrent() }
                try index.select(id)
                finishProfileChange(index, store: targetStore)
            } catch {
                _ = dante_engine_load(engine, previous)
                refresh()
                throw error
            }
        } catch { self.error = error.localizedDescription }
    }
    func renameProfile(_ id: String, to name: String) {
        do {
            guard var index = profileIndex else { throw StudioError.message("Catálogo de perfis indisponível.") }
            try index.rename(id, to: name)
            profileIndex = index
            profiles = index.profiles
        } catch { self.error = error.localizedDescription }
    }
    func properties(name: String? = nil, type: String? = nil) -> [String: Any] {
        guard let engine else { return [:] }
        if let type { return jsonObject(copied(dante_engine_type_properties(engine, type))) }
        return jsonObject(copied(dante_engine_properties(engine, name ?? selectedName)))
    }
    func selectScene(_ name: String) {
        if command("scene.select", ["scene": name, "studio": studioMode], undo: false) { selectedItem = nil }
    }
    func take() { _ = command("scene.take", ["scene": sceneName, "duration": 300, "transition": "fade"], undo: false) }
    func setStudio(_ value: Bool) {
        if command("scene.select", ["scene": sceneName, "studio": value], undo: false) { studioMode = value }
    }
    func askName(title: String, initial: String = "", action: (String) -> Void) {
        let alert = NSAlert(); alert.messageText = title
        let input = NSTextField(string: initial); input.frame = NSRect(x: 0, y: 0, width: 280, height: 26)
        alert.accessoryView = input; alert.addButton(withTitle: "Salvar"); alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { action(name) }
        }
    }
    func confirm(_ message: String, action: () -> Void) {
        let alert = NSAlert(); alert.messageText = message
        alert.informativeText = active ? "Há uma saída ativa. Esta alteração pode afetar a transmissão." : "Esta ação altera o projeto atual."
        alert.addButton(withTitle: "Confirmar"); alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
    func confirmEndLive() {
        let alert = NSAlert()
        alert.messageText = "Encerrar a live?"
        alert.informativeText = "O Dante Live vai parar de enviar vídeo e áudio para esta transmissão. Suas cenas e configurações continuarão salvas."
        alert.addButton(withTitle: "Continuar ao vivo")
        alert.addButton(withTitle: "Encerrar live")
        if alert.runModal() == .alertSecondButtonReturn { endLive() }
    }
    func removeSelected() {
        guard let selectedItem else { return }
        removeSource(id: selectedItem, scene: sceneName)
    }
    func removeSource(id: Int64, scene: String) {
        confirm("Remover a fonte desta cena?") { _ = command("source.remove", ["scene": scene, "id": id]) }
    }
    func moveSources(in scene: String, ids: [Int64], from offsets: IndexSet, to destination: Int) {
        guard scene == sceneName, ids == listedSources.reversed().map(\.sceneItemID),
              let reordered = SourceOrder.moving(ids, from: offsets, to: destination), reordered != ids else { return }
        var ordered = reordered.makeIterator()
        let visibleIDs = Set(ids)
        let complete = items.reversed().map { visibleIDs.contains($0.sceneItemID) ? ordered.next()! : $0.sceneItemID }
        _ = command("scene.reorderSources", ["scene": scene, "ids": Array(complete.reversed())])
    }
    func exportProject() {
        guard let engine else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Dante Live.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(copied(dante_engine_save(engine)).utf8).write(to: url, options: .atomic); notice = "Projeto exportado" }
        catch { self.error = error.localizedDescription }
    }
    func importProject() {
        refresh()
        guard !active, !guests.inUse, let engine else { error = "Pare a live e encerre a sala de convidados antes de abrir outra coleção."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 32 * 1024 * 1024 else { throw StudioError.message("O arquivo excede 32 MB.") }
            let text = String(decoding: data, as: UTF8.self)
            try validateNoInlineSecrets(jsonObject(text))
            let snapshot = copied(dante_engine_save(engine))
            guard dante_engine_load(engine, text) else { throw StudioError.message(copied(dante_engine_last_error(engine))) }
            chatRenderer.invalidate(); preserveFailedProject = false; pushUndo(snapshot); refresh(); save(); notice = "Coleção aberta; arquivo original preservado"
        } catch { self.error = error.localizedDescription }
    }
    func requestPermission(for type: String, completion: @escaping () -> Void) {
        let media: AVMediaType? = type.contains("av_capture") || type.contains("avcapture") ? .video : type.contains("coreaudio_input") ? .audio : nil
        if let media {
            let status = AVCaptureDevice.authorizationStatus(for: media)
            if status == .authorized { completion(); return }
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: media) { [weak self] granted in Task { @MainActor in
                    if granted { completion() }
                    else { self?.showPermissionRecovery(media == .audio ? "Microfone" : "Câmera", pane: media == .audio ? "Privacy_Microphone" : "Privacy_Camera") }
                } }
            } else { showPermissionRecovery(media == .audio ? "Microfone" : "Câmera", pane: media == .audio ? "Privacy_Microphone" : "Privacy_Camera") }
            return
        }
        if Self.requiresScreenPermission(type) {
            // ScreenCaptureKit is the authority for modern capture. A stale CG
            // preflight must not reject working SCK authorization after an update.
            Task { @MainActor [weak self] in
                do {
                    _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    completion()
                } catch {
                    let ns = error as NSError
                    if ns.domain == SCStreamErrorDomain && ns.code == -3801 {
                        self?.showPermissionRecovery("Gravação de tela e áudio do sistema", pane:"Privacy_ScreenCapture")
                    } else {
                        self?.error = "O macOS não conseguiu preparar a captura. Tente novamente. Se você acabou de alterar a autorização de tela, reabra o Dante fora de uma live. Código: \(ns.domain) (\(ns.code))."
                    }
                }
            }
            return
        }
        completion()
    }
    static func requiresScreenPermission(_ type: String) -> Bool {
        type.contains("screen_capture") || type.contains("display_capture") || type.contains("window_capture") || type.contains("sck")
    }
    private func showPermissionRecovery(_ title: String, pane: String) {
        let alert=NSAlert();alert.messageText="Autorizar \(title)"
        alert.informativeText="Abra Ajustes do Sistema › Privacidade e Segurança › \(title) e habilite o Dante Live. Depois, tente adicionar a fonte novamente.\n\nSe já estiver habilitado, o macOS pode estar usando uma autorização de outra cópia do app. Fora de uma live, feche o Dante, remova apenas a entrada dele nessa lista e adicione novamente o Dante Live instalado em Aplicativos. Não é necessário remover as permissões de outros programas."
        alert.addButton(withTitle:"Abrir Ajustes do Sistema");alert.addButton(withTitle:"Agora não")
        if alert.runModal() == .alertFirstButtonReturn,let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?"+pane) { NSWorkspace.shared.open(url) }
    }
    func shutdown() {
        guests.stop(); browserTabAudio.stop(); countdown.cancel(); launchTask?.cancel(); youtube.shutdown(); liveSettings.flush()
        timer?.invalidate(); timer = nil; saveTask?.cancel(); save()
        if let engine { dante_engine_destroy(engine); self.engine = nil }
    }
}
