import SwiftUI

struct ConnectionDiagnosisView: View {
    @ObservedObject var settings: LiveSettingsModel
    var running: Bool
    var canMeasure: Bool
    var measure: () -> Void
    var cancel: () -> Void
    @LegacyState private var details = false
    private var diagnosis: ConnectionDiagnosis {
        ConnectionDiagnosis(uploadMbps: settings.document.uploadMbps, fps: settings.video.fps, videoBitrate: settings.video.bitrate, audioBitrate: settings.video.audioBitrate)
    }
    private var color: Color {
        switch diagnosis.state { case .unknown: .secondary; case .comfortable: .green; case .limited: .orange; case .insufficient: .red }
    }
    private var icon: String {
        switch diagnosis.state { case .unknown: "wifi"; case .comfortable: "checkmark.circle.fill"; case .limited, .insufficient: "exclamationmark.triangle.fill" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: running ? "wifi" : icon).font(.title2).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 5) {
                    Text(running ? "Conferindo sua internet…" : diagnosis.title).font(.headline)
                    Text(running ? "Aguarde o teste terminar para ver a recomendação atualizada." : diagnosis.summary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .center) {
                if let upload = diagnosis.uploadMbps {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(upload, format: .number.precision(.fractionLength(1))) Mbps").font(.title2.bold()).monospacedDigit()
                        Text(settings.document.uploadMeasuredAt == nil ? "Velocidade informada por você" : "Velocidade de envio medida").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if running { ProgressView().controlSize(.small); Button("Cancelar teste", action: cancel) }
                else { Button(diagnosis.uploadMbps == nil ? "Testar minha conexão" : "Medir novamente", action: measure).disabled(!canMeasure) }
            }
            if !running, let quality = diagnosis.suggestedQuality {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECOMENDADO PARA VOCÊ").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                    Text(diagnosis.suggestionLabel).font(.title3.bold())
                    Text(diagnosis.suggestionReason).font(.callout)
                    if settings.document.selection == quality.rawValue && settings.video.fps == diagnosis.suggestedFPS {
                        Label("Você já está usando este preset", systemImage: "checkmark.circle").foregroundStyle(.teal)
                    } else {
                        Button("Usar este preset") { settings.useSuggestion(diagnosis) }.buttonStyle(.borderedProminent)
                    }
                    if diagnosis.supports4K { Text("A velocidade também comporta 4K. Escolha essa opção se precisar de mais resolução e confira o desempenho do Mac.").font(.caption).foregroundStyle(.secondary) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            if !running, diagnosis.uploadMbps != nil {
                Label(diagnosis.currentFits ? "Sua configuração atual cabe nessa velocidade." : "Sua configuração atual precisa de mais velocidade de envio.", systemImage: diagnosis.currentFits ? "checkmark" : "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(diagnosis.currentFits ? Color.secondary : Color.orange)
                Text("Velocidade suficiente é um bom começo. Oscilações da internet e o desempenho do Mac também influenciam a live.").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Detalhes e velocidade manual", isExpanded: $details) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Upload (Mbps)", value: Binding(get: { settings.document.uploadMbps }, set: { settings.setUpload($0) }), format: .number.precision(.fractionLength(0...1)))
                    if let measured = settings.document.uploadMeasuredAt { Text("Último teste: \(measured.formatted(date: .abbreviated, time: .shortened)).") }
                    Text("O Dante deixa 30% da velocidade livre para outros usos e variações. Este teste não mede o atraso até o YouTube.")
                    Link("Orientações do YouTube", destination: URL(string: "https://support.google.com/youtube/answer/2853702?hl=pt-BR")!)
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }.padding(.vertical, 6)
    }
}
