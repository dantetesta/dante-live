import SwiftUI
import AppKit

struct LiveSetupView: View {
    @ObservedObject var model: StudioModel
    @Binding var width: Int
    @Binding var height: Int
    @Binding var fps: Int
    @Binding var bitrate: Int
    @Binding var audioBitrate: Int
    @Binding var encoder: String
    @StateObject private var probe = UploadProbe()
    @LegacyState private var quality = LiveQuality.fullHD
    @LegacyState private var presetFPS = 30
    @LegacyState private var uploadMbps = 0.0
    @LegacyState private var uploadMeasuredAt: Date?

    private var recommendation: LiveRecommendation {
        LiveRecommendation(quality: quality, fps: presetFPS, uploadMbps: uploadMbps > 0 ? uploadMbps : nil)
    }
    private var obsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.obsproject.obs-studio" || $0.bundleURL?.lastPathComponent == "OBS.app"
        }
    }
    private var defaultEncoder: String { model.catalog.string("defaultEncoder") }
    private var hardwareAvailable: Bool {
        model.catalog.array("encoders").contains { $0.string("id") == defaultEncoder && $0.flag("hardware") }
    }
    var body: some View {
        Section("Preparar live para o YouTube") {
            Picker("Qualidade", selection: $quality) {
                ForEach(LiveQuality.allCases) { quality in Text(quality.title).tag(quality) }
            }
            Picker("Movimento", selection: $presetFPS) {
                Text("30 FPS • apresentações e câmera").tag(30)
                Text("60 FPS • movimento intenso").tag(60)
            }
            HStack {
                TextField("Upload disponível (Mbps)", value: Binding(get: { uploadMbps }, set: { uploadMbps = $0; uploadMeasuredAt = nil }), format: .number)
                if probe.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancelar medição") { probe.cancel() }
                } else {
                    Button("Medir upload…") { measureUpload() }.disabled(model.active || obsRunning)
                }
            }
            if obsRunning {
                Text("OBS aberto: medição bloqueada para proteger a live. Você pode informar um upload já conhecido.").font(.caption).foregroundStyle(.secondary)
            }
            if let measuredAt = uploadMeasuredAt {
                Text("Medido em \(measuredAt.formatted(date: .abbreviated, time: .shortened)). A conexão pode variar.").font(.caption).foregroundStyle(.secondary)
            } else if uploadMbps > 0 {
                Text("Upload informado manualmente; não medido pelo Dante Live.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = probe.error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("Proposta: \(quality.width) × \(quality.height) • \(recommendation.fps) FPS • H.264 \(recommendation.bitrate) kbps • AAC 128 kbps")
                .font(.callout.weight(.medium))
            Text(recommendation.explanation).font(.caption).foregroundStyle(recommendation.uploadSufficient ? Color.secondary : Color.orange)
            Text("Upload mínimo com margem: \(recommendation.minimumUploadMbps, specifier: "%.1f") Mbps; para o bitrate recomendado: \(recommendation.recommendedUploadMbps, specifier: "%.1f") Mbps.")
                .font(.caption).foregroundStyle(.secondary)
            Text(hardwareAvailable
                 ? "Encoder de hardware detectado. O uso efetivo será confirmado ao iniciar a saída."
                 : "Encoder por software: capacidade de renderizar este preset ainda precisa ser testada neste Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Text(quality == .ultraHD
                 ? "4K usa latência normal no YouTube. Para interação rápida, prefira 1080p."
                 : "Configure a latência no YouTube Studio. O preset do Dante não altera essa opção no serviço nem garante atraso zero.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Aplicar preset") { apply() }
                    .disabled(model.active || probe.isRunning || !recommendation.uploadSufficient || defaultEncoder.isEmpty || !uploadMbps.isFinite || uploadMbps < 0 || uploadMbps > 100_000)
                Link("Recomendações do YouTube", destination: URL(string: "https://support.google.com/youtube/answer/2853702?hl=pt-BR")!)
            }
            Text("Aplicar altera o vídeo com as saídas paradas. Fontes existentes mantêm suas posições e escalas; confira o enquadramento no preview.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            quality = LiveQuality.allCases.first { $0.width == width && $0.height == height } ?? .fullHD
            presetFPS = fps == 60 ? 60 : 30
            uploadMbps = model.outputConfiguration.uploadMbps ?? 0
            uploadMeasuredAt = model.outputConfiguration.uploadMeasuredAt
        }
        .onChange(of: probe.measuredMbps) { _, value in
            guard let value else { return }
            uploadMbps = value; uploadMeasuredAt = probe.measuredAt
        }
        .onChange(of: model.active) { _, active in if active { probe.cancel() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            if obsRunning { probe.cancel() }
        }
        .onDisappear { probe.cancel() }
    }

    private func measureUpload() {
        guard !model.active, !obsRunning else { return }
        let alert = NSAlert()
        alert.messageText = "Medir o upload agora?"
        alert.informativeText = "O teste do macOS envia dados para medir sua conexão e pode ocupar o upload por até um minuto. Não execute durante lives ou chamadas em outros aplicativos. Ele não transmite suas cenas e não mede a latência até o YouTube."
        alert.addButton(withTitle: "Medir upload"); alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn, !model.active, !obsRunning { probe.start() }
    }
    private func apply() {
        guard recommendation.uploadSufficient, !model.active else { return }
        guard model.command("video.configure", ["width": quality.width, "height": quality.height, "fps": recommendation.fps]) else { return }
        width = quality.width; height = quality.height; fps = recommendation.fps
        bitrate = recommendation.bitrate; audioBitrate = recommendation.audioBitrate; encoder = defaultEncoder
        model.outputConfiguration.bitrate = bitrate
        model.outputConfiguration.audioBitrate = audioBitrate
        model.outputConfiguration.encoder = encoder
        model.outputConfiguration.uploadMbps = uploadMbps > 0 ? uploadMbps : nil
        model.outputConfiguration.uploadMeasuredAt = uploadMeasuredAt
        model.outputConfiguration.save()
        model.notice = "Preset \(quality.title) • \(fps) FPS aplicado; confira o enquadramento"
    }
}
