import AppKit
import AVFoundation
import SwiftUI

@MainActor
struct CameraSetupView: View {
    @ObservedObject var model: StudioModel
    let sourceName: String
    @Environment(\.dismiss) private var dismiss
    @LegacyState private var devices: [CameraDeviceChoice] = []
    @LegacyState private var settings: [String: Any] = [:]
    @LegacyState private var properties: [[String: Any]] = []
    @LegacyState private var previewEnabled = false
    @LegacyState private var applying = false
    @LegacyState private var message: String?
    @LegacyState private var permissionMessage: String?
    @LegacyState private var applied = false
    @LegacyState private var sheetActive = false

    private var source: [String: Any] { model.scenes.flatMap { $0.array("items") }.first { $0.string("name") == sourceName } ?? [:] }
    private var isModern: Bool { source.string("type").hasPrefix("macos-avcapture") }
    private var isFast: Bool { source.string("type") == "macos-avcapture-fast" }
    private var selectedDevice: String { settings.string("device") }
    private var usePreset: Bool { !isFast && settings.flag("use_preset", true) }
    private var width: Int { Int(source.number("width")) }
    private var height: Int { Int(source.number("height")) }
    private var missingDevice: Bool { !selectedDevice.isEmpty && !devices.contains { $0.id == selectedDevice } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Configurar câmera", systemImage: "video").font(.title2.bold())
                Spacer()
                Text(sourceName).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 22) {
                configuration.frame(width: 300).disabled(applying)
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        Color.black
                        if previewEnabled {
                            CameraSourcePreview(model: model, sourceName: sourceName)
                            if width == 0 || height == 0 {
                                VStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Aguardando quadros da câmera…").font(.callout)
                                    Text("Se a imagem não aparecer, confira o dispositivo, a permissão e o uso por outros aplicativos.")
                                        .font(.caption).multilineTextAlignment(.center)
                                }.padding(24).foregroundStyle(.white)
                            }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "video").font(.largeTitle)
                                Text("Escolha o dispositivo e clique em Aplicar e visualizar.")
                                    .multilineTextAlignment(.center).font(.callout)
                            }.padding(30).foregroundStyle(.white.opacity(0.8))
                        }
                    }.frame(width: 460, height: 280).clipShape(RoundedRectangle(cornerRadius: 10))
                    HStack {
                        Text(previewEnabled ? "Prévia da fonte aplicada" : "Prévia ainda não iniciada").font(.caption)
                        Spacer()
                        if previewEnabled && width > 0 && height > 0 {
                            Text("\(width) × \(height)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if previewEnabled {
                        Button("Fechar prévia") { previewEnabled = false }
                            .help("Fecha somente esta prévia; a fonte continua na cena.")
                    }
                    Text("A prévia reutiliza a fonte da cena. Aplicar altera também a imagem usada na gravação ou transmissão.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if previewEnabled && !applied {
                        Text("Há alterações pendentes. A prévia mantém a configuração já aplicada.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if model.active {
                        Label("Há uma saída ativa. Alterações na câmera afetam essa saída.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            if let permissionMessage {
                Label(permissionMessage, systemImage: "lock.shield").font(.callout).fixedSize(horizontal: false, vertical: true)
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                    Button("Abrir ajustes de câmera") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
            }
            if let message { Text(message).font(.callout).foregroundStyle(applied ? Color.secondary : Color.orange) }
            Divider()
            HStack {
                Text("Selecionar opções não abre uma nova captura.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(applying ? "Aplicando…" : "Aplicar e visualizar") { apply() }
                    .buttonStyle(.borderedProminent).disabled(applying || selectedDevice.isEmpty || missingDevice)
            }
        }.padding(24).frame(width: 830)
            .onAppear(perform: load)
            .onDisappear { sheetActive = false; previewEnabled = false }
            .task(id: applied) {
                guard applied else { return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, applied, sheetActive else { return }
                // OBS may normalize device_name/FPS asynchronously after Apply.
                let current = model.properties(name: sourceName)
                settings = current.object("settings"); properties = current.array("properties")
            }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dispositivo").font(.headline)
                Spacer()
                Button { refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Atualizar lista de câmeras").accessibilityLabel("Atualizar lista de câmeras")
            }
            Picker("Dispositivo", selection: Binding(get: { selectedDevice }, set: { value in
                settings["device"] = value
                settings["device_name"] = devices.first { $0.id == value }?.name ?? ""
                settings["supported_format"] = ""
                refreshOptions()
                applied = false
            })) {
                Text("Selecionar dispositivo…").tag("")
                ForEach(devices) { Text($0.name).tag($0.id) }
                if missingDevice { Text("Dispositivo salvo indisponível").tag(selectedDevice).disabled(true) }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
            if devices.isEmpty {
                Text("Nenhuma câmera encontrada. Conecte uma câmera e atualize a lista.").font(.caption).foregroundStyle(.secondary)
            } else if missingDevice {
                Text("O dispositivo salvo não está disponível. Selecione uma câmera conectada.").font(.caption).foregroundStyle(.orange)
            }
            if !isFast {
                Toggle("Usar resolução predefinida", isOn: Binding(get: { usePreset }, set: {
                    settings["use_preset"] = $0; refreshOptions(); applied = false
                }))
            }
            if usePreset {
                optionPicker("Resolução", key: "preset")
            } else {
                optionPicker("Formato de entrada / resolução", key: "supported_format")
                fpsFields
            }
            if properties.contains(where: { $0.string("name") == "enable_audio" }) || settings["enable_audio"] != nil {
                Toggle("Incluir áudio do dispositivo", isOn: Binding(get: { settings.flag("enable_audio", true) }, set: { settings["enable_audio"] = $0; applied = false }))
            }
            if width > 0 && height > 0, let sceneItem = model.items.first(where: { $0.string("name") == sourceName }) {
                Button("Ajustar fonte ao canvas") {
                    _ = model.command("item.fit", ["scene": model.sceneName, "id": sceneItem.sceneItemID])
                }.disabled(sceneItem.flag("locked"))
            }
        }
    }

    private func optionPicker(_ title: String, key: String) -> some View {
        let choices = options(key)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: Binding(get: { settings.string(key) }, set: {
                settings[key] = $0; refreshOptions(); applied = false
            })) {
                Text("Selecionar…").tag("")
                ForEach(Array(choices.enumerated()), id: \.offset) { _, option in
                    Text(presetLabel(option.string("name"))).tag(option.string("value")).disabled(option.flag("disabled"))
                }
            }.labelsHidden().pickerStyle(.menu)
        }
    }

    private var fpsFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Taxa de quadros (FPS)").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Numerador", value: Binding(get: { Int(settings.object("frame_rate").number("numerator", 30)) }, set: {
                    var fps = settings.object("frame_rate"); fps["numerator"] = max(1, min(240_000, $0)); settings["frame_rate"] = fps; applied = false
                }), format: .number)
                Text("/")
                TextField("Denominador", value: Binding(get: { Int(settings.object("frame_rate").number("denominator", 1)) }, set: {
                    var fps = settings.object("frame_rate"); fps["denominator"] = max(1, min(10_000, $0)); settings["frame_rate"] = fps; applied = false
                }), format: .number)
            }.textFieldStyle(.roundedBorder)
            Text("Ex.: 30 / 1 ou 30000 / 1001. O valor precisa ser compatível com o formato selecionado.")
                .font(.caption2).foregroundStyle(.secondary)
            if !frameRateRanges.isEmpty {
                Text("Faixas disponíveis: " + frameRateRanges.map {
                    String(format: "%.3f–%.3f", $0.lowerBound, $0.upperBound)
                }.joined(separator: "; ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func options(_ key: String) -> [[String: Any]] {
        properties.first { $0.string("name") == key }?.array("items").filter { !$0.string("value").isEmpty } ?? []
    }
    private func presetLabel(_ label: String) -> String {
        ["High": "Alta (automática)", "Medium": "Média (automática)", "Low": "Baixa (automática)"][label] ?? label
    }
    private func refreshDevices() {
        devices = CameraDevices.discover()
        permissionMessage = CameraDevices.authorizationMessage
    }
    private func load() {
        sheetActive = true
        let value = model.properties(name: sourceName)
        settings = value.object("settings"); properties = value.array("properties")
        if settings.object("frame_rate").isEmpty { settings["frame_rate"] = ["numerator": 30, "denominator": 1] }
        refreshDevices()
        refreshOptions()
    }
    private func refreshOptions() {
        // Reviewed modern OBS callbacks enumerate lists only; no session updates.
        guard isModern, let engine = model.engine else { return }
        let value = jsonObject(copied(dante_engine_properties_with_settings(engine, sourceName, jsonString(settings))))
        properties = value.array("properties")
        if usePreset {
            let choices = options("preset").filter { !$0.flag("disabled") }
            if !choices.contains(where: { $0.string("value") == settings.string("preset") }) {
                settings["preset"] = choices.first?.string("value") ?? ""
            }
        }
    }
    private func apply() {
        applied = false; message = nil
        let key = usePreset ? "preset" : "supported_format"
        guard options(key).contains(where: { !$0.flag("disabled") && $0.string("value") == settings.string(key) }) else {
            message = "Selecione uma resolução ou formato disponível para esta câmera."; return
        }
        if !usePreset {
            let fps = settings.object("frame_rate")
            let numerator = fps.number("numerator"), denominator = fps.number("denominator")
            let rate = denominator > 0 ? numerator / denominator : 0
            guard rate.isFinite, rate > 0, frameRateRanges.contains(where: { rate >= $0.lowerBound - 0.0001 && rate <= $0.upperBound + 0.0001 }) else {
                message = "A taxa de quadros precisa estar em uma das faixas disponíveis para o formato selecionado."; return
            }
        }
        applying = true
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    applying = false; permissionMessage = CameraDevices.authorizationMessage
                    guard sheetActive else { return }
                    if granted { commit() }
                }
            }
        } else if status == .authorized {
            applying = false; commit()
        } else {
            applying = false; permissionMessage = CameraDevices.authorizationMessage
        }
    }
    private var frameRateRanges: [ClosedRange<Double>] {
        let ranges = properties.first { $0.string("name") == "frame_rate" }?.array("ranges") ?? []
        return ranges.compactMap { range in
            let lowDenominator = range.number("minDenominator"), highDenominator = range.number("maxDenominator")
            guard lowDenominator > 0, highDenominator > 0 else { return nil }
            let low = range.number("minNumerator") / lowDenominator
            let high = range.number("maxNumerator") / highDenominator
            guard low.isFinite, high.isFinite, low > 0, high >= low else { return nil }
            return low...high
        }
    }
    private func commit() {
        if model.command("source.update", ["name": sourceName, "settings": settings, "autoPlace": width == 0 || height == 0]) {
            previewEnabled = true; applied = true
            message = "Configuração aplicada à fonte. A prévia mostra os quadros recebidos pelo motor."
        } else { message = model.error ?? "Não foi possível atualizar esta câmera." }
    }
}

@MainActor
private final class CameraSourcePreviewNSView: NSView, EngineDisplayOwner {
    private var preview: UnsafeMutableRawPointer?
    private var owner: OpaquePointer?
    private var sourceName = ""
    override var isFlipped: Bool { true }
    func attach(engine: OpaquePointer?, source: String) {
        guard owner != engine || sourceName != source else { return }
        detach(); owner = engine; sourceName = source
        if let engine {
            preview = dante_engine_source_preview_create(engine, Unmanaged.passUnretained(self).toOpaque(), source)
            resizePreview()
        }
    }
    func detach() {
        if let preview { dante_engine_preview_destroy(preview); self.preview = nil }
        owner = nil; sourceName = ""
    }
    private func resizePreview() {
        guard let preview else { return }
        let pixels = convertToBacking(bounds)
        dante_engine_preview_resize(preview, UInt32(max(1, pixels.width)), UInt32(max(1, pixels.height)))
    }
    override func layout() { super.layout(); resizePreview() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); resizePreview() }
}

@MainActor
private struct CameraSourcePreview: NSViewRepresentable {
    @ObservedObject var model: StudioModel
    let sourceName: String
    func makeNSView(context: Context) -> CameraSourcePreviewNSView { CameraSourcePreviewNSView() }
    func updateNSView(_ view: CameraSourcePreviewNSView, context: Context) { view.attach(engine: model.engine, source: sourceName) }
    static func dismantleNSView(_ view: CameraSourcePreviewNSView, coordinator: ()) { view.detach() }
}
