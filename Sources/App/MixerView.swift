import SwiftUI
import AppKit

@MainActor final class AudioMeterModel: ObservableObject {
    @Published var levels: [String: Any] = [:]
    private var timer: Timer?
    func start(_ model: StudioModel) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self, weak model] _ in
            Task { @MainActor [weak self, weak model] in
                guard let self, let engine = model?.engine else { return }
                self.levels = jsonObject(copied(dante_engine_audio_levels(engine)))
            }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}

struct MixerView: View {
    @ObservedObject var model: StudioModel
    @StateObject private var meters = AudioMeterModel()
    var channels: [[String: Any]] {
        let items = model.state.array("audio").isEmpty ? model.items.filter { $0.flag("audio") } : model.state.array("audio")
        var seen = Set<String>(); return items.filter { seen.insert($0.string("name")).inserted }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("MIXER DE ÁUDIO").font(.caption.weight(.bold)); Spacer(); Text("dBFS").font(.caption2).foregroundStyle(.secondary); Image(systemName: "waveform").foregroundStyle(.secondary) }.padding(12)
            if channels.isEmpty {
                ContentUnavailableView("Adicione uma fonte de áudio", systemImage: "waveform", description: Text("Microfones e fontes com som aparecem aqui."))
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 1) {
                            ForEach(channels, id: \.entryName) { channel in
                                AudioChannelStrip(model: model, channel: channel, meters: meters)
                                    .frame(width: 156, height: max(240, geometry.size.height-12))
                            }
                        }.padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
            }
        }.onAppear { meters.start(model) }.onDisappear { meters.stop() }
    }
}

private struct AudioChannelStrip: View {
    @ObservedObject var model: StudioModel
    let channel: [String: Any]
    @ObservedObject var meters: AudioMeterModel
    private var name: String { channel.string("name") }
    private var muted: Bool { channel.flag("muted") }
    private var gain: Double { 20*log10(max(0.000001,channel.number("volume",1))) }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(muted ? Color.secondary : channel.flag("sourceActive") ? .green : .orange).frame(width: 6, height: 6)
                Text(muted ? "Silenciado" : channel.flag("sourceActive") ? "Ativo" : "Inativo").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: Binding(get: { model.watchesMicrophone(channel) }, set: { model.setMicrophoneWatch(channel, enabled: $0) })) {
                    Image(systemName: model.watchesMicrophone(channel) ? "bell.badge.fill" : "bell.slash")
                }.toggleStyle(.button).buttonStyle(.plain).help("Alertar se esta fonte ficar sem sinal por 30 segundos durante a live").accessibilityLabel("Alerta de silêncio para \(name)")
            }
            Text(model.guests.displayName(for: name)).font(.callout.weight(.semibold)).lineLimit(2).frame(height: 32).frame(maxWidth: .infinity, alignment: .leading).help(name)
            Text(channel.number("volume",1) <= 0 ? "−∞ dB" : String(format:"%.1f dB",gain)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if channel.number("volume",1)>1.01 { Text("Reforço com proteção de pico").font(.system(size:9)).foregroundStyle(.orange).lineLimit(1) }
            HStack(spacing: 10) {
                VerticalGainSlider(value: Binding(get: { max(-60,min(AudioBoostScale.maximumDecibels,gain)) }, set: { value in
                    _ = model.command("audio.set", ["name": name, "volume": value <= -60 ? 0 : pow(10,value/20)], undo: false)
                }), name: name).frame(width: 26)
                AudioLevelBars(levels: meters.levels.object(name), muted: muted).frame(width: 77)
            }.frame(maxHeight: .infinity)
            Button {
                _ = model.command("audio.set", ["name": name, "muted": !muted], undo: false)
            } label: { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.title3).foregroundStyle(muted ? Color.red : .primary).frame(maxWidth: .infinity).padding(.vertical, 4) }
                .buttonStyle(.plain).help(muted ? "Ativar áudio" : "Silenciar").accessibilityLabel("\(muted ? "Ativar" : "Silenciar") \(name)")
        }.padding(12).background(model.guests.participantSlot(for:name).map { participantColor($0).opacity(0.10) } ?? Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment:.top) { if let slot=model.guests.participantSlot(for:name) { Capsule().fill(participantColor(slot)).frame(height:3).padding(.horizontal,12) } }
    }
}

private struct AudioLevelBars: View {
    let levels: [String: Any]
    let muted: Bool
    private func values(_ key: String) -> [Double] { (levels[key] as? [Double]).flatMap { $0.isEmpty ? nil : $0 } ?? [-96,-96] }
    private func fraction(_ db: Double) -> Double { min(1,max(0,(db+60)/60)) }
    var body: some View {
        GeometryReader { geometry in
            let height = max(1,geometry.size.height-12)
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: 0, through: -60, by: -6)), id: \.self) { db in
                    HStack(spacing: 3) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 4,height: 1); Text("\(db)").font(.system(size: 9,design: .monospaced)).foregroundStyle(.secondary) }
                        .position(x: 60,y: 6+(1-fraction(Double(db)))*height)
                }
                Canvas { context, size in
                    let peaks = values("peak"), rms = values("rms"), hold = values("hold")
                    let count = max(1,min(2,peaks.count)), barWidth = count == 1 ? 34.0 : 16.0
                    for index in 0..<count {
                        let x = Double(index)*19
                        for segment in 0..<60 {
                            let rect = CGRect(x: x,y: 6+height*(1-Double(segment+1)/60),width: barWidth,height: max(1,height/60-1))
                            let db = Double(segment)-60
                            let color: Color = db >= -6 ? .red : db >= -18 ? .yellow : .green
                            let peak = muted ? -96 : peaks[index], magnitude = muted ? -96 : rms[min(index,rms.count-1)]
                            context.fill(Path(rect),with: .color(color.opacity(peak >= db ? (magnitude >= db ? 1 : 0.65) : 0.12)))
                        }
                        let held = muted ? -96 : hold[min(index,hold.count-1)]
                        if held > -60 { context.fill(Path(CGRect(x:x,y:6+height*(1-fraction(held)),width:barWidth,height:2)),with:.color(held >= -0.5 ? .red : .primary)) }
                    }
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Nível de áudio").accessibilityValue(muted ? "Silenciado" : String(format:"%.1f dBFS",values("peak").max() ?? -96))
    }
}

private struct VerticalGainSlider: NSViewRepresentable {
    @Binding var value: Double
    let name: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(frame: NSRect(x:0,y:0,width:26,height:180))
        slider.minValue = -60; slider.maxValue = AudioBoostScale.maximumDecibels; slider.isContinuous = true
        slider.target = context.coordinator; slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel("Volume de \(name)"); return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) { context.coordinator.parent = self; slider.doubleValue = value }
    final class Coordinator: NSObject {
        var parent: VerticalGainSlider
        init(_ parent: VerticalGainSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) { parent.value = slider.doubleValue }
    }
}
