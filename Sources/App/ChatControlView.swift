import SwiftUI
import AppKit

struct ChatStylePicker: View {
    @Binding var settings: [String: Any]
    var changed: () -> Void
    private var selected: ChatStyle { ChatStyle.selected(settings) }
    private func color(_ key: String, fallback: UInt32) -> Binding<Color> {
        Binding(get: {
            Color(nsColor: chatColor(UInt32(min(0xFFFFFF, max(0, settings.number(key, Double(fallback)))))))
        }, set: { value in
            let c = NSColor(value).usingColorSpace(.deviceRGB) ?? .white
            settings[key] = (Int(c.redComponent * 255) << 16) | (Int(c.greenComponent * 255) << 8) | Int(c.blueComponent * 255)
            changed()
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aparência do comentário").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                ForEach(ChatStyle.all) { style in
                    Button {
                        settings["style"] = style.id; settings["accent"] = nil; settings["background"] = nil; settings["ink"] = nil
                        changed()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: chatColor(style.accent))).frame(width: style.layout == 0 ? 4 : 20, height: 15)
                                Text("Seu canal").font(.system(size: 10, weight: .bold))
                            }
                            Rectangle().fill(Color(nsColor: chatColor(style.ink)).opacity(0.45)).frame(height: 3)
                            Text(style.name).font(.system(size: 11, weight: .medium))
                        }.foregroundStyle(Color(nsColor: chatColor(style.ink))).padding(10).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                            .background(Color(nsColor: chatColor(style.background)), in: RoundedRectangle(cornerRadius: min(14, style.radius)))
                            .overlay(RoundedRectangle(cornerRadius: min(14, style.radius)).strokeBorder(selected.id == style.id ? Color.teal : Color.secondary.opacity(0.25), lineWidth: selected.id == style.id ? 3 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("Estilo \(style.name)").accessibilityAddTraits(selected.id == style.id ? .isSelected : [])
                }
            }
            ColorPicker("Cor de destaque", selection: color("accent", fallback: selected.accent), supportsOpacity: false)
            ColorPicker("Cor de fundo", selection: color("background", fallback: selected.background), supportsOpacity: false)
            ColorPicker("Cor do texto", selection: color("ink", fallback: selected.ink), supportsOpacity: false)
            Picker("Fonte", selection: Binding(get: { settings.string("font", "Helvetica Neue") }, set: { settings["font"] = $0; changed() })) {
                ForEach(["Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Trebuchet MS", "Verdana"], id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Text("Tamanho do texto")
                Slider(value: Binding(get: { settings.number("fontSize", 30) }, set: { settings["fontSize"] = $0; changed() }), in: 20...36, step: 1)
            }
            Text("Textos longos são divididos em páginas no destaque. A aparência desta fonte acompanha todas as cenas em que ela é reutilizada.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ChatControlView: View {
    @ObservedObject var studio: StudioModel
    @ObservedObject var chat: YouTubeChat
    @Environment(\.dismiss) private var dismiss
    @LegacyState private var donationsOnly = true
    private var entries: [ChatMessage] { donationsOnly ? chat.donations : chat.messages.reversed() }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("A conversa entra em cena").font(.system(size: 25, weight: .bold))
                    Text(chat.status).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if studio.youtube.trackingLive && !chat.running { Button("Reconectar chat") { studio.youtube.reconnectChat { studio.streaming } } }
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Mensagens", selection: $donationsOnly) {
                        Text("Super Chats (\(chat.donations.count))").tag(true)
                        Text("Conversa (\(chat.messages.count))").tag(false)
                    }.pickerStyle(.segmented).labelsHidden()
                    if chat.overflow > 0 {
                        Label("Fila cheia. \(chat.overflow) novos apoios não foram guardados. Consulte o YouTube Studio.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if entries.isEmpty {
                                ContentUnavailableView(donationsOnly ? "Aguardando os primeiros apoios" : "A conversa começa com sua live", systemImage: donationsOnly ? "heart.text.square" : "bubble.left.and.bubble.right", description: Text("Conecte o canal e inicie uma live do YouTube. As mensagens desta sessão aparecem aqui."))
                            }
                            ForEach(entries) { message in row(message) }
                        }.padding(2)
                    }
                }.padding(20).frame(maxWidth: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    Label("Destaque escolhido", systemImage: "text.bubble.fill").font(.headline)
                    if let featured = chat.featured {
                        Text(featured.author).font(.title3.bold())
                        if featured.paid { Text(featured.amount).font(.headline).foregroundStyle(.teal) }
                        ScrollView { Text(chat.featureText).font(.system(size: 17)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 200)
                        if featured.pages.count > 1 {
                            HStack {
                                Button { chat.advance(-1); studio.refresh() } label: { Image(systemName: "chevron.left") }.disabled(chat.page == 0).help("Página anterior")
                                Text("\(chat.page + 1) de \(featured.pages.count)").monospacedDigit()
                                Button { chat.advance(1); studio.refresh() } label: { Image(systemName: "chevron.right") }.disabled(chat.page == featured.pages.count - 1).help("Próxima página")
                            }
                        }
                        Button("Ocultar destaque", systemImage: "eye.slash") { chat.hide(); studio.refresh() }
                        Text("Permanece até você ocultar ou escolher outra mensagem. A visibilidade da fonte e a cena em programa determinam se ela vai ao ar.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Revise a mensagem e clique em Mostrar. Nada da fila de Super Chats aparece automaticamente.").foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Adicionar à cena selecionada").font(.headline)
                    Text(studio.sceneName).font(.caption).foregroundStyle(.secondary)
                    Button("Janela do chat", systemImage: "bubble.left.and.bubble.right") { add("dante_youtube_chat", base: "Chat do YouTube") }
                    Button("Destaque animado", systemImage: "text.bubble") { add("dante_superchat", base: "Destaque do YouTube") }
                    Text("Escolha entre 12 estilos nas Propriedades da fonte. Arraste e redimensione no canvas.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Label("Mensagens apenas nesta live", systemImage: "clock").font(.caption.weight(.semibold))
                    Text("A conversa e a fila são limpas ao encerrar. Seus estilos e a posição das fontes permanecem salvos.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(width: 310)
            }
        }.frame(width: min(980, (NSScreen.main?.visibleFrame.width ?? 1200) - 80), height: min(720, (NSScreen.main?.visibleFrame.height ?? 900) - 100)).background(Color(nsColor: .windowBackgroundColor)).tint(.teal)
    }
    private func row(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(message.author).font(.headline)
                Spacer()
                if message.paid { Text(message.amount).font(.headline).foregroundStyle(.teal) }
            }
            Text(message.text.isEmpty ? "Apoio sem mensagem" : message.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack {
                Button(chat.featured?.id == message.id ? "Selecionado" : "Mostrar", systemImage: "eye") {
                    if !studio.items.contains(where: { $0.string("type") == "dante_superchat" }) { add("dante_superchat", base: "Destaque do YouTube") }
                    chat.show(message); studio.refresh()
                }.buttonStyle(.borderedProminent)
                if message.paid { Button("Já exibido / remover", systemImage: "checkmark") { chat.dismiss(message.id); studio.refresh() }.help("Remove apenas desta fila. Não altera a doação no YouTube.") }
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chat.featured?.id == message.id ? Color.teal : Color.secondary.opacity(0.15)))
    }
    private func add(_ type: String, base: String) {
        let names = Set(studio.scenes.flatMap { $0.array("items").map { $0.string("name") } })
        var name = base, index = 2
        while names.contains(name) { name = "\(base) \(index)"; index += 1 }
        if studio.command("source.add", ["scene": studio.sceneName, "type": type, "name": name]) {
            if let item = studio.items.last { studio.selectedItem = item.sceneItemID }
        }
    }
}
