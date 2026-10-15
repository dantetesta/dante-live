import AppKit
import SwiftUI
import AVFoundation
import CoreGraphics

@MainActor
final class StudioModel: ObservableObject {
    @Published var state: [String: Any] = [:]
    @Published var catalog: [String: Any] = [:]
    @Published var selectedItem: Int64?
    @Published var error: String?
    @Published var notice = "Pronto para criar"
    @Published var studioMode = false
    @Published var showingAdd = false
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
    lazy var liveSettings = LiveSettingsModel(model: self)
    lazy var youtube = YouTubeModel(directory: projectDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dante Live"))
    @Published var pendingLive: LiveLaunch?
    @Published var preparingLive = false
    @Published var updateInstalling = false
    @Published var pendingUpdateMessage: String?
    var liveOperationInProgress: Bool { active || preparingLive || countdown.remaining != nil || pendingLive != nil || youtube.busy }
    private var launchTask: Task<Void, Never>?
    var engine: OpaquePointer?
    private var timer: Timer?
    private var saveTask: Task<Void, Never>?
    private var store: ProjectStore?
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private var starting = false
    private var reportedOutputFailures: [String: Int] = [:]
    private var outputStartedAt: [String: Date] = [:]
    var preserveFailedProject = false
    let projectDirectory: URL?
    init(projectDirectory: URL? = nil) { self.projectDirectory = projectDirectory }

    var scenes: [[String: Any]] { state.array("scenes") }
    var sceneName: String { state.string("selectedScene", scenes.first?.string("name") ?? "") }
    var items: [[String: Any]] { scenes.first(where: { $0.string("name") == sceneName })?.array("items") ?? [] }
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

    func start() {
        guard engine == nil, !starting else { return }
        starting = true
        defer { starting = false }
        if let projectDirectory {
            engine = dante_engine_create_with_config(Bundle.main.bundlePath, 1920, 1080, 30, projectDirectory.appendingPathComponent("engine").path)
        } else { engine = dante_engine_create(Bundle.main.bundlePath, 1920, 1080, 30) }
        guard let engine else { error = copied(dante_engine_last_error(nil)); return }
        catalog = jsonObject(copied(dante_engine_catalog(engine)))
        if !catalog.array("encoders").contains(where: { $0.string("id") == outputConfiguration.encoder }) {
            outputConfiguration.encoder = catalog.string("defaultEncoder")
        }
        do {
            store = try ProjectStore(directory: projectDirectory)
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
            }
        } catch { preserveFailedProject = true; self.error = error.localizedDescription }
        refresh()
        if scenes.isEmpty { _ = command("scene.create", ["name": "Cena principal"], undo: false) }
        _ = liveSettings
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        guard let engine else { return }
        let pending = Set(scenes.flatMap { scene in
            scene.array("items").filter { $0.flag("pendingPlacement") }.map { scene.string("name") + ":" + String($0.sceneItemID) }
        })
        state = jsonObject(copied(dante_engine_state(engine)))
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
        let uniqueAudio = Dictionary(scenes.flatMap { $0.array("items") }.filter { $0.flag("audio") }.map { ($0.string("sourceUUID", $0.string("name")), $0) }, uniquingKeysWith: { first, _ in first })
        let samples = uniqueAudio.map { id, source in
            MicrophoneSample(id: id, name: source.string("name"), enabled: liveSettings.document.microphoneAlerts && watchesMicrophone(source) && source.flag("sourceActive") && !source.flag("muted") && source.number("volume", 1) > 0 && Int(source.number("tracks", 1)) & 1 != 0 && Int(source.number("monitoring")) != 1, signalAge: source.number("signalAge", -1) >= 0 ? source.number("signalAge") : nil)
        }
        let warnings = silenceWatch.update(samples, live: state.object("outputs").object("stream").flag("started"), now: ProcessInfo.processInfo.systemUptime)
        if warnings != microphoneWarnings { microphoneWarnings = warnings }
        if let id = selectedItem, !items.contains(where: { $0.sceneItemID == id }) { selectedItem = nil }
    }
    func watchesMicrophone(_ source: [String: Any]) -> Bool {
        liveSettings.document.audioWatchOverrides[source.string("sourceUUID", source.string("name"))] ?? source.string("type").contains("coreaudio_input")
    }
    func setMicrophoneWatch(_ source: [String: Any], enabled: Bool) {
        let id = source.string("sourceUUID", source.string("name"))
        liveSettings.edit({ $0.audioWatchOverrides[id] = enabled }, immediate: true)
        refresh()
    }
    func beginLive() {
        guard !active, !preparingLive, !updateInstalling, countdown.remaining == nil else { return }
        if liveSettings.document.youtubeMode == true {
            guard liveSettings.prepareVideo() else { outputTab = "video"; showingOutput = true; return }
            preparingLive = true
            launchTask = Task { [weak self] in
                guard let self else { return }; defer { self.preparingLive = false }
                do { self.pendingLive = try await self.youtube.confirmation() }
                catch { self.youtube.message = error.localizedDescription; self.outputTab = "youtube"; self.showingOutput = true }
            }
        } else {
            liveSettings.loadKey()
            guard liveSettings.prepareStream() else { outputTab = "connection"; showingOutput = true; return }
            pendingLive = LiveLaunch(channel: liveSettings.selectedChannel?.name ?? "Conexão RTMP", title: "Live configurada no serviço de destino", thumbnailURL: nil, server: liveSettings.document.server, key: liveSettings.key)
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
                let launch = selection.youtubeAccount == nil ? selection : try await self.youtube.prepare(selection)
                try Task.checkCancellation()
                self.countdown.start { [weak self] in
                    guard let self, !self.active else { return }
                    guard self.liveSettings.video == video else { self.error = "As configurações mudaram durante a preparação. Confirme a transmissão novamente."; return }
                    if self.command("stream.start", ["server": launch.server, "key": launch.key, "encoder": video.encoder, "bitrate": video.bitrate, "audioBitrate": video.audioBitrate], undo: false) {
                        self.notice = "Conectando ao servidor…"
                        self.youtube.watchStarted(launch) { [weak self] in self?.active == true }
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func endLive() {
        if command("stream.stop", undo: false) { youtube.endActive() }
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
        guard !active, let engine, let previous = undoStack.last else { return }
        let current = copied(dante_engine_save(engine))
        if dante_engine_load(engine, previous) { undoStack.removeLast(); redoStack.append(current); updateHistory(); refresh(); inspectorRevision += 1; scheduleSave() }
        else { error = copied(dante_engine_last_error(engine)) }
    }
    func redo() {
        guard !active, let engine, let next = redoStack.last else { return }
        let current = copied(dante_engine_save(engine))
        if dante_engine_load(engine, next) { redoStack.removeLast(); undoStack.append(current); updateHistory(); refresh(); inspectorRevision += 1; scheduleSave() }
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
        guard !liveOperationInProgress else { throw StudioError.message("Finalize a live antes de atualizar.") }
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
        studioMode = value
        if !value { _ = command("scene.select", ["scene": sceneName, "studio": false], undo: false) }
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
    func removeSelected() {
        guard let selectedItem else { return }
        removeSource(id: selectedItem, scene: sceneName)
    }
    func removeSource(id: Int64, scene: String) {
        confirm("Remover a fonte desta cena?") { _ = command("source.remove", ["scene": scene, "id": id]) }
    }
    func moveSources(in scene: String, ids: [Int64], from offsets: IndexSet, to destination: Int) {
        guard scene == sceneName, ids == items.reversed().map(\.sceneItemID),
              let reordered = SourceOrder.moving(ids, from: offsets, to: destination), reordered != ids else { return }
        _ = command("scene.reorderSources", ["scene": scene, "ids": Array(reordered.reversed())])
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
        guard !active, let engine else { error = "Pare as saídas antes de abrir outra coleção."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 32 * 1024 * 1024 else { throw StudioError.message("O arquivo excede 32 MB.") }
            let text = String(decoding: data, as: UTF8.self)
            try validateNoInlineSecrets(jsonObject(text))
            let snapshot = copied(dante_engine_save(engine))
            guard dante_engine_load(engine, text) else { throw StudioError.message(copied(dante_engine_last_error(engine))) }
            preserveFailedProject = false; pushUndo(snapshot); refresh(); save(); notice = "Coleção aberta; arquivo original preservado"
        } catch { self.error = error.localizedDescription }
    }
    func requestPermission(for type: String, completion: @escaping () -> Void) {
        let media: AVMediaType? = type.contains("av_capture") || type.contains("avcapture") ? .video : type.contains("coreaudio_input") ? .audio : nil
        if let media, AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
            AVCaptureDevice.requestAccess(for: media) { [weak self] granted in Task { @MainActor in
                if granted { completion() } else { self?.error = "Permissão negada. Ative o Dante Live em Ajustes do Sistema › Privacidade e Segurança." }
            } }; return
        }
        if let media, AVCaptureDevice.authorizationStatus(for: media) != .authorized { error = "Permissão de \(media == .audio ? "microfone" : "câmera") negada. Verifique Privacidade e Segurança."; return }
        if type.contains("screen_capture") || type.contains("display_capture") || type.contains("sck") {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { error = "Autorize a gravação de tela nas configurações de privacidade do macOS."; return }
        }
        completion()
    }
    func shutdown() {
        countdown.cancel(); launchTask?.cancel(); youtube.shutdown(); liveSettings.flush()
        timer?.invalidate(); timer = nil; saveTask?.cancel(); save()
        if let engine { dante_engine_destroy(engine); self.engine = nil }
    }
}
