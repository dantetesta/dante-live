import SwiftUI
import AppKit

@MainActor private enum ChatStylePreviews {
    static let images: [Int: NSImage] = Dictionary(uniqueKeysWithValues: ChatStyle.all.compactMap { style in
        let message=ChatMessage(["id":"preview","authorDetails":["displayName":"Marina"],"snippet":["type":"textMessageEvent","textMessageDetails":["messageText":"Boa noite, pessoal!"]]])!
        guard let bitmap=ChatRaster.render(messages:[message],featured:nil,page:0,lower:false,settings:["style":style.id,"layoutWidth":360,"layoutHeight":140,"fontSize":24,"nameSize":20]) else{return nil}
        let image=NSImage(size:NSSize(width:bitmap.pixelsWide,height:bitmap.pixelsHigh));image.addRepresentation(bitmap)
        return (style.id,image)
    })
}

struct ChatStylePicker: View {
    @Binding var settings: [String: Any]
    var lower = false
    var changed: () -> Void
    @LegacyState private var choosingFont = false
    @LegacyState private var fontSearch = ""
    @LegacyState private var installedFonts: [String] = []
    private var selected: ChatStyle { ChatStyle.selected(settings) }
    private var chosenFont: String { settings.string("font", selected.layout == 5 ? "Menlo" : "Helvetica Neue") }
    private var matchingFonts: [String] {
        installedFonts.filter { fontSearch.isEmpty || $0.localizedStandardContains(fontSearch) }
    }
    private func color(_ key: String, fallback: UInt32) -> Binding<Color> {
        Binding(get: {
            let value=settings.number(key,Double(fallback))
            return Color(nsColor:chatColor(value.isFinite ? UInt32(min(0xFFFFFF,max(0,value))) : fallback))
        }, set: { value in
            let c=NSColor(value).usingColorSpace(.deviceRGB) ?? .white
            settings[key]=(Int(c.redComponent*255)<<16)|(Int(c.greenComponent*255)<<8)|Int(c.blueComponent*255);changed()
        })
    }
    private func number(_ key:String,_ fallback:Double) -> Binding<Double> {
        Binding(get:{settings.number(key,fallback)},set:{settings[key]=$0.rounded();changed()})
    }
    private func slider(_ title:String,key:String,fallback:Double,range:ClosedRange<Double>,unit:String="px") -> some View {
        VStack(alignment:.leading,spacing:5) {
            HStack { Text(title);Spacer();Text("\(Int(settings.number(key,fallback))) \(unit)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value:number(key,fallback),in:range).accessibilityLabel(title)
        }
    }
    private var componentScale: Binding<Double> {
        Binding(get: {
            let value = settings.number("componentScale", 1)
            return value.isFinite ? min(2, max(0.5, value)) : 1
        }, set: { settings["componentScale"] = ($0 * 20).rounded() / 20; changed() })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(lower ? "Estilo do destaque" : "Estilo do chat").font(.headline)
            Label("Fora da live, o canvas mostra exemplos para você configurar. Esses exemplos não entram na transmissão.",systemImage:"eye").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:138),spacing:8)],spacing:8) {
                ForEach(ChatStyle.all) { style in
                    Button {
                        settings["style"]=style.id
                        for key in ["accent","background","ink","font","cardOpacity"] { settings[key]=nil };changed()
                    } label: {
                        VStack(alignment:.leading,spacing:0) {
                            if let image=ChatStylePreviews.images[style.id] {
                                Image(nsImage:image).resizable().scaledToFit().padding(.horizontal,5).padding(.top,7)
                            }
                            HStack { Text(style.name).font(.system(size:11,weight:.semibold));Spacer(minLength:0)
                                if selected.id == style.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.cyan) }
                            }.padding(.horizontal,10).padding(.bottom,10)
                        }.foregroundStyle(.white).background(Color(red:0.12,green:0.15,blue:0.19),in:RoundedRectangle(cornerRadius:10))
                            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(selected.id == style.id ? Color.cyan : Color.secondary.opacity(0.2),lineWidth:selected.id == style.id ? 2:1))
                    }.buttonStyle(.plain).accessibilityLabel("Estilo \(style.name)").accessibilityAddTraits(selected.id == style.id ? .isSelected : [])
                }
            }
            Divider()
            Text("Texto e espaçamento").font(.subheadline.bold())
            HStack {
                Text("Fonte")
                Button {
                    installedFonts = ChatFontCatalog.availableFamilies()
                    fontSearch = ""
                    choosingFont = true
                } label: {
                    HStack {
                        Text(chosenFont).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                }.buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.25)))
                    .popover(isPresented: $choosingFont, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fontes deste Mac").font(.headline)
                        TextField("Buscar fonte", text: $fontSearch).textFieldStyle(.roundedBorder)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(matchingFonts, id: \.self) { family in
                                    Button {
                                        settings["font"] = family
                                        changed()
                                        choosingFont = false
                                    } label: {
                                        HStack {
                                            Text(family).font(.custom(family, size: 15)).lineLimit(1)
                                            Spacer()
                                            if family == chosenFont { Image(systemName: "checkmark").foregroundStyle(.teal) }
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 5)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(height: 300)
                        Text("A escolha fica salva neste projeto. Se a fonte não existir em outro Mac, será usada a fonte do sistema.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(14).frame(width: 340)
                }
            }
            if !ChatFontCatalog.isInstalled(chosenFont) {
                Label("Fonte indisponível neste Mac; o texto usa a fonte do sistema.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            slider("Nome da pessoa",key:"nameSize",fallback:20,range:12...48)
            slider("Mensagem",key:"fontSize",fallback:24,range:14...64)
            if !lower { slider("Entre os comentários",key:"messageGap",fallback:10,range:0...48) }
            Divider()
            Text("Cores dos cartões").font(.subheadline.bold())
            ColorPicker("Destaque / Super Chat",selection:color("accent",fallback:selected.accent),supportsOpacity:false)
            ColorPicker("Fundo",selection:color("background",fallback:selected.background),supportsOpacity:false)
            ColorPicker("Texto",selection:color("ink",fallback:selected.ink),supportsOpacity:false)
            VStack(alignment:.leading,spacing:5) {
                Text("Opacidade do cartão")
                Slider(value:Binding(get:{settings.number("cardOpacity",selected.layout == 1 ? 0.65 : 0.96)},set:{settings["cardOpacity"]=$0;changed()}),in:0.15...1).accessibilityLabel("Opacidade do cartão")
            }
            Divider()
            HStack { Text("Escala geral").font(.subheadline.bold()); Spacer(); Text("\(Int(componentScale.wrappedValue * 100))%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value:componentScale,in:0.5...2,step:0.05).accessibilityLabel("Escala geral do componente")
            HStack {
                Text("Aumenta cartão, nome e texto juntos, redesenhados na nova resolução.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength:8)
                Button("100%") { componentScale.wrappedValue=1 }.disabled(componentScale.wrappedValue == 1)
            }
            Divider()
            Text("Área do componente").font(.subheadline.bold())
            let layout=ChatLayout(lower:lower,settings:settings)
            HStack {
                Text("Largura")
                TextField("Largura",value:number("layoutWidth",Double(layout.width)),format:.number).textFieldStyle(.roundedBorder)
                Text("Altura")
                TextField("Altura",value:number("layoutHeight",Double(layout.height)),format:.number).textFieldStyle(.roundedBorder)
            }
            Text("Arraste as laterais no canvas para mudar largura ou altura e reorganizar as linhas. Use Escala geral para aumentar tudo proporcionalmente. A altura mínima preserva uma linha de leitura.").font(.caption).foregroundStyle(.secondary)
            Text("Os nomes usam cores consistentes por pessoa. O destaque usa este mesmo desenho; mensagens longas ficam em páginas na fila. A aparência acompanha esta fonte nas cenas em que é reutilizada.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ChatControlView: View {
    @ObservedObject var studio: StudioModel
    @ObservedObject var chat: YouTubeChat
    @StudioDismiss private var dismiss
    @LegacyState private var section = "donations"
    @LegacyState private var query = ""
    @LegacyState private var newestFirst = true
    private var entries: [ChatMessage] { chat.entries(in: section, query: query, newestFirst: newestFirst) }
    private var featuredPages: [String] {
        guard let featured=chat.featured else{return []}
        let source = studio.selected.flatMap { $0.string("type") == "dante_superchat" ? $0 : nil }
            ?? studio.scenes.flatMap { $0.array("items") }.first { $0.string("type") == "dante_superchat" }
        return ChatRaster.pages(for:featured,settings:source.map{studio.properties(name:$0.string("name")).object("settings")} ?? [:])
    }
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
                    Picker("Mensagens", selection: $section) {
                        Text("Super Chats (\(chat.pendingDonations.count))").tag("donations")
                        Text("Conversa (\(chat.pendingMessages.count))").tag("conversation")
                        Text("Já exibidos (\(chat.displayed.count))").tag("displayed")
                    }.pickerStyle(.segmented).labelsHidden()
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Buscar por nome ou mensagem", text: $query).textFieldStyle(.roundedBorder)
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Limpar busca") }
                        Picker("Ordem", selection: $newestFirst) {
                            Text("Mais recentes").tag(true)
                            Text("Mais antigos").tag(false)
                        }.labelsHidden().frame(width: 145)
                    }
                    Text("Ocultar tira a mensagem da fila imediatamente. Se ela não foi ao ar, o histórico indica isso. Destaques retirados pelo olho da fonte entram no histórico após 30 segundos.").font(.caption).foregroundStyle(.secondary)
                    if chat.overflow > 0 {
                        Label("Fila cheia. \(chat.overflow) novos apoios não foram guardados. Consulte o YouTube Studio.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if entries.isEmpty {
                                ContentUnavailableView(!query.isEmpty ? "Nenhuma mensagem encontrada" : section == "displayed" ? "Nenhum destaque arquivado" : section == "donations" ? "Nenhum Super Chat pendente" : "Nenhum comentário pendente", systemImage: section == "displayed" ? "checkmark.bubble" : "bubble.left.and.bubble.right", description: Text(!query.isEmpty ? "Busque outro nome ou trecho da mensagem." : chat.sessionActive ? "As mensagens desta live aparecem aqui. Destaques exibidos ficam na outra aba." : "Conecte o canal e inicie uma live do YouTube."))
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
                        ScrollView { Text(featuredPages.isEmpty ? chat.featureText : featuredPages[min(chat.page,featuredPages.count-1)]).font(.system(size: 17)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 200)
                        if featuredPages.count > 1 {
                            HStack {
                                Button { chat.advance(-1,pageCount:featuredPages.count); studio.refresh() } label: { Image(systemName: "chevron.left") }.disabled(chat.page == 0).help("Página anterior")
                                Text("\(min(chat.page + 1,featuredPages.count)) de \(featuredPages.count)").monospacedDigit()
                                Button { chat.advance(1,pageCount:featuredPages.count); studio.refresh() } label: { Image(systemName: "chevron.right") }.disabled(chat.page >= featuredPages.count - 1).help("Próxima página")
                            }
                        }
                        Button("Ocultar e concluir", systemImage: "eye.slash") { chat.hide(); studio.refresh() }
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
            if chat.onAirID == message.id {
                badge("Em exibição", icon: "dot.radiowaves.left.and.right", color: .green)
            } else if chat.retiringIDs.contains(message.id) {
                badge("Exibido • aguardando arquivamento", icon: "clock", color: .orange)
            } else if chat.wasDisplayed(message.id) {
                badge(chat.hiddenBeforeAirIDs.contains(message.id) ? "Ocultado sem ir ao ar" : "Já exibido", icon: "checkmark.circle.fill", color: .purple)
            }
            Text(message.text.isEmpty ? "Apoio sem mensagem" : message.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack {
                Button(chat.featured?.id == message.id ? "Selecionado" : "Mostrar", systemImage: "eye") {
                    if !studio.items.contains(where: { $0.string("type") == "dante_superchat" }) { add("dante_superchat", base: "Destaque do YouTube") }
                    chat.show(message); studio.refresh()
                }.buttonStyle(.borderedProminent).disabled(chat.featured?.id == message.id)
                if section != "displayed" {
                    Button("Ocultar", systemImage: "eye.slash") { chat.hide(message); studio.refresh() }
                        .help("Sai da fila e vai para Já exibidos. O histórico informa se não foi ao ar.")
                } else {
                    Button("Remover do histórico", systemImage: "trash") { chat.dismiss(message.id); studio.refresh() }
                        .help("Remove somente deste Mac, sem alterar o YouTube.")
                }
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chat.featured?.id == message.id ? Color.teal : Color.secondary.opacity(0.15)))
    }
    private func badge(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
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
