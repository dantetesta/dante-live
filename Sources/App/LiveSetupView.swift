import SwiftUI
import AppKit

struct LiveSetupView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var settings: LiveSettingsModel
    @StateObject private var probe = UploadProbe()
    @LegacyState private var presetName = ""
    private var obsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.obsproject.obs-studio" || $0.bundleURL?.lastPathComponent == "OBS.app" }
    }
    var body: some View {
        Form {
            Section("Qualidade da live") {
                Picker("Preset", selection: Binding(get: { settings.document.selection }, set: { settings.choose($0) })) {
                    ForEach(LiveQuality.allCases) { Text($0.title).tag($0.rawValue) }
                    Text("Personalizado • ajustes atuais").tag("custom")
                    ForEach(settings.document.presets) { Text($0.name).tag($0.id.uuidString) }
                }
                Picker("Movimento", selection: Binding(get: { settings.video.fps }, set: { settings.changeFPS($0) })) {
                    ForEach(Array(Set([24,30,60,settings.video.fps])).sorted(), id: \.self) { Text("\($0) FPS").tag($0) }
                }
                Text("\(settings.video.width) × \(settings.video.height) • \(settings.video.fps) FPS • H.264 \(settings.video.bitrate) kbps • AAC \(settings.video.audioBitrate) kbps")
                    .font(.callout.weight(.medium))
                Text("Selecionar um preset aplica os ajustes automaticamente. Personalize resolução e codificação na aba Vídeo e áudio. O enquadramento das fontes é preservado.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Minha predefinição") {
                HStack {
                    TextField("Nome do preset", text: $presetName)
                    Button("Salvar como novo preset") {
                        if settings.savePreset(name: presetName) { presetName = "" }
                    }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let selected = settings.document.presets.first(where: { $0.id.uuidString == settings.document.selection }) {
                    Button("Excluir preset “\(selected.name)”", role: .destructive) {
                        model.confirm("Excluir o preset “\(selected.name)”? Os ajustes atuais serão mantidos.") { settings.removePreset(selected.id) }
                    }
                }
                Text("Salva resolução, FPS, encoder e bitrates. Servidor e chave pertencem à conexão e não são copiados para o preset.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Capacidade da conexão") {
                HStack {
                    TextField("Upload disponível (Mbps)", value: Binding(get: { settings.document.uploadMbps }, set: { settings.setUpload($0) }), format: .number)
                    if probe.isRunning {
                        ProgressView().controlSize(.small)
                        Button("Cancelar") { probe.cancel() }
                    } else { Button("Medir upload…") { measureUpload() }.disabled(model.active || obsRunning) }
                }
                if let measured = settings.document.uploadMeasuredAt {
                    Text("Medido em \(measured.formatted(date: .abbreviated, time: .shortened)). A conexão pode variar.").font(.caption).foregroundStyle(.secondary)
                }
                if obsRunning { Text("Medição bloqueada enquanto o OBS está aberto, para proteger a live.").font(.caption).foregroundStyle(.secondary) }
                if let error = probe.error { Text(error).font(.caption).foregroundStyle(.red) }
                if let recommendation = settings.recommendation {
                    Text(recommendation.explanation).font(.caption).foregroundStyle(recommendation.uploadSufficient ? Color.secondary : Color.orange)
                    if !recommendation.uploadSufficient {
                        Text("Mantido o bitrate mínimo do preset. A conexão informada é insuficiente; confira antes de transmitir.").font(.caption).foregroundStyle(.orange)
                    }
                } else { Text("Presets personalizados mantêm seus bitrates; a medição não os substitui.").font(.caption).foregroundStyle(.secondary) }
                Link("Recomendações do YouTube", destination: URL(string: "https://support.google.com/youtube/answer/2853702?hl=pt-BR")!)
            }
        }.formStyle(.grouped)
        .onChange(of: probe.measuredMbps) { _, value in
            if let value { settings.setUpload(value, measuredAt: probe.measuredAt, immediate: true) }
        }
        .onChange(of: model.active) { _, active in if active { probe.cancel() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in if obsRunning { probe.cancel() } }
        .onDisappear { probe.cancel() }
    }
    private func measureUpload() {
        guard !model.active, !obsRunning else { return }
        let alert = NSAlert(); alert.messageText = "Medir o upload agora?"
        alert.informativeText = "O teste do macOS pode ocupar o upload por até um minuto. Não execute durante lives ou chamadas em outros aplicativos. Ele não transmite suas cenas e não mede a latência até o YouTube."
        alert.addButton(withTitle: "Medir upload"); alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn, !model.active, !obsRunning { probe.start() }
    }
}
