import SwiftUI
import AppKit

private struct VisualizerAudioChoice: Identifiable {
    let id: String
    let name: String
}

struct AudioVisualizerSettingsView: View {
    @Binding var settings: [String: Any]
    let scenes: [[String: Any]]
    var onEdit: (Bool) -> Void

    private static let styles = [
        "Onda contínua", "Barras finas", "Espelho", "Cápsulas", "Órbita",
        "Halo de pontos", "Fita luminosa", "Constelação", "Colunas 3D", "Túnel 3D"
    ]

    private var audioSources: [VisualizerAudioChoice] {
        var seen = Set<String>()
        return scenes.flatMap { $0.array("items") }
            .filter { $0.flag("audio") && !$0.string("sourceUUID").isEmpty }
            .compactMap { item -> VisualizerAudioChoice? in
                let id = item.string("sourceUUID")
                guard seen.insert(id).inserted else { return nil }
                return VisualizerAudioChoice(id: id, name: item.string("name"))
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedStyle: Int { min(9, max(0, Int(settings.number("style")))) }
    private var selectedUUID: String { settings.string("audioSourceUUID") }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Visualizador de áudio", systemImage: "waveform.path").font(.headline)
            Text("O desenho reage às amostras da fonte escolhida e aparece na cena e na transmissão. Ele não acrescenta nem altera áudio.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Fonte de áudio").font(.subheadline.weight(.semibold))
                Picker("Fonte de áudio", selection: Binding(get: { selectedUUID }, set: { uuid in
                    settings["audioSourceUUID"] = uuid
                    settings["audioSourceName"] = audioSources.first { $0.id == uuid }?.name ?? ""
                    onEdit(true)
                })) {
                    Text("Escolha uma fonte…").tag("")
                    ForEach(audioSources) { item in Text(item.name).tag(item.id) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                if audioSources.isEmpty {
                    Text("Adicione um microfone, Áudio do Mac ou arquivo de mídia à cena para escolher aqui.")
                        .font(.caption).foregroundStyle(.orange)
                } else if !selectedUUID.isEmpty && !audioSources.contains(where: { $0.id == selectedUUID }) {
                    Text("A fonte escolhida não está disponível neste projeto. Selecione outra.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Estilo visual").font(.subheadline.weight(.semibold))
                Text("Amostras abaixo servem só para escolher o desenho.").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Self.styles.indices, id: \.self) { index in
                        Button {
                            settings["style"] = index
                            onEdit(true)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                VisualizerStyleThumbnail(style: index, primary: settings.number("primary", 0x48D8E8), secondary: settings.number("secondary", 0x986BFF))
                                    .frame(height: 54).frame(maxWidth: .infinity)
                                    .background(Color(red: 0.07, green: 0.09, blue: 0.14), in: RoundedRectangle(cornerRadius: 7))
                                Text(Self.styles[index]).font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                            }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedStyle == index ? Color.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selectedStyle == index ? .teal : .secondary.opacity(0.15), lineWidth: selectedStyle == index ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel(Self.styles[index])
                            .accessibilityAddTraits(selectedStyle == index ? .isSelected : [])
                    }
                }
            }

            GraphicColorPicker(title: "Cor principal", settings: $settings, key: "primary", fallback: 0x48D8E8) { onEdit(true) }
            GraphicColorPicker(title: "Cor de destaque", settings: $settings, key: "secondary", fallback: 0x986BFF) { onEdit(true) }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Sensibilidade")
                    Spacer()
                    Text(String(format: "%.1f×", settings.number("sensitivity", 1))).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { min(4, max(0.25, settings.number("sensitivity", 1))) }, set: {
                    settings["sensitivity"] = $0; onEdit(false)
                }), in: 0.25...4).accessibilityLabel("Sensibilidade")
            }
            Text("Arraste as alças no canvas para mudar largura e altura. O visualizador redesenha no tamanho escolhido, com fundo transparente. Uma fonte silenciosa mostra apenas a linha ou marcas de repouso.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VisualizerStyleThumbnail: View {
    let style: Int
    let primary: Double
    let secondary: Double

    private func color(_ raw: Double) -> Color {
        let value = Int(raw)
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }

    var body: some View {
        Canvas { context, size in
            let a = color(primary), b = color(secondary)
            let cx = size.width / 2, cy = size.height / 2
            let values: [Double] = [0.12,0.25,0.45,0.18,0.75,0.52,0.30,0.92,0.58,0.36,0.68,0.24,0.42,0.77,0.32,0.16]
            if style == 0 || style == 6 {
                var path = Path()
                for i in 0..<33 {
                    let x = CGFloat(i) / 32 * size.width
                    let y = cy + sin(Double(i)*0.65) * (6 + values[i/2]*12)
                    if i == 0 { path.move(to: CGPoint(x:x,y:y)) } else { path.addLine(to: CGPoint(x:x,y:y)) }
                }
                context.stroke(path, with: .color(a), lineWidth: style == 6 ? 4 : 2)
                if style == 6 { context.stroke(Path { $0.move(to:CGPoint(x:0,y:cy)); $0.addLine(to:CGPoint(x:size.width,y:cy)) }, with:.color(b.opacity(0.5)),lineWidth:1) }
            } else if [1,2,3,7,8].contains(style) {
                for i in values.indices {
                    let x = CGFloat(i) * size.width / CGFloat(values.count)
                    let height = CGFloat(values[i]) * size.height * (style == 2 ? 0.35 : 0.78)
                    if style == 7 {
                        for j in 0..<max(1,Int(values[i]*5)) {
                            context.fill(Path(ellipseIn:CGRect(x:x+3,y:size.height-5-CGFloat(j)*9,width:3,height:3)),with:.color(j%2==0 ? a : b))
                        }
                    } else if style == 3 {
                        for j in 0..<max(1,Int(values[i]*5)) {
                            context.fill(Path(roundedRect:CGRect(x:x+2,y:size.height-5-CGFloat(j)*9,width:4,height:5),cornerRadius:2),with:.color(a))
                        }
                    } else {
                        let rect = CGRect(x:x+2,y:style==2 ? cy-height : size.height-height-3,width:style==8 ? 5 : 4,height:style==2 ? height*2 : height)
                        context.fill(Path(roundedRect:rect,cornerRadius:style==8 ? 0 : 2),with:.color(i%4==0 ? b : a))
                        if style==8 { context.fill(Path(CGRect(x:rect.maxX,y:rect.minY+3,width:2,height:rect.height)),with:.color(b)) }
                    }
                }
            } else {
                let radius = min(size.width,size.height)*0.23
                if style==9 {
                    for i in 0..<5 {
                        let r=radius*(0.4+Double(i)*0.28)
                        context.stroke(Path(ellipseIn:CGRect(x:cx-r,y:cy-r,width:r*2,height:r*2)),with:.color((i%2==0 ? a : b).opacity(0.4+Double(i)*0.1)),lineWidth:1.5)
                    }
                } else {
                    context.stroke(Path(ellipseIn:CGRect(x:cx-radius,y:cy-radius,width:radius*2,height:radius*2)),with:.color(b.opacity(0.6)),lineWidth:1.5)
                    for i in values.indices {
                        let angle=Double(i)/Double(values.count)*Double.pi*2
                        let start=radius+2, end=start+values[i]*12
                        let x1=cx+cos(angle)*start,y1=cy+sin(angle)*start
                        let x2=cx+cos(angle)*end,y2=cy+sin(angle)*end
                        if style==4 {
                            context.stroke(Path { $0.move(to:CGPoint(x:x1,y:y1));$0.addLine(to:CGPoint(x:x2,y:y2)) },with:.color(a),lineWidth:2)
                        } else { context.fill(Path(ellipseIn:CGRect(x:x2-2,y:y2-2,width:4,height:4)),with:.color(a)) }
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}
