import AppKit
import SwiftUI
let appVersion = "Chat QA"
@main struct ChatQA {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        try await runYouTubeChatTests()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/chat-qa")
        let fixture = directory.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try await runYouTubeTests(directory: fixture)
        let studio = StudioModel(projectDirectory: fixture)
        studio.youtube = YouTubeModel(directory: fixture, api: YouTubeAPI { _ in throw URLError(.notConnectedToInternet) }, vault: LiveKeyVault(read: { _ in "" }, save: { _,_ in }, delete: { _ in }))
        let chat = studio.youtube.chat
        let examples: [[String: Any]] = [
            ["id": "one", "authorDetails": ["displayName": "Marina • Canal Criativo"], "snippet": ["type": "superChatEvent", "superChatDetails": ["amountDisplayString": "R$ 25,00", "userComment": "Adorei a conversa! Como você organiza as ideias antes de começar uma transmissão? Obrigada por compartilhar sua experiência com a gente. 💛"]]],
            ["id": "two", "authorDetails": ["displayName": "João"], "snippet": ["type": "superChatEvent", "superChatDetails": ["amountDisplayString": "R$ 10,00", "userComment": "Qual câmera você recomenda para quem está começando?"]]],
            ["id": "three", "authorDetails": ["displayName": "Ana"], "snippet": ["type": "textMessageEvent", "textMessageDetails": ["messageText": "Muito bom acompanhar vocês ao vivo!"]]]
        ]
        chat.ingest(examples); chat.show(chat.donations[0])
        for style in ChatStyle.all {
            let bitmap = ChatRaster.render(messages: chat.messages, featured: chat.featured, page: 0, lower: true, settings: ["style": style.id])!
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("style-\(style.id).png"))
        }
        let feed = ChatRaster.render(messages: Array(repeating: chat.messages[0], count: 4), featured: nil, page: 0, lower: false, settings: [:])!
        try feed.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("chat-feed.png"))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 980, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        for dark in [true, false] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let hosting = NSHostingView(rootView: ChatControlView(studio: studio, chat: chat).environment(\.colorScheme, dark ? .dark : .light))
            window.contentView = hosting; window.setContentSize(hosting.fittingSize); window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(200))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(dark ? "panel-dark.png" : "panel-light.png"))
        }
        let gallery = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
            Text("12 estilos de comentário").font(.title.bold())
            Text("Prévia com dados fictícios • cor e fonte personalizáveis").foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(ChatStyle.all) { style in
                    VStack(alignment: .leading, spacing: 4) {
                        Image(nsImage: NSImage(contentsOf: directory.appendingPathComponent("style-\(style.id).png"))!).resizable().scaledToFit()
                        Text(style.name).font(.caption.weight(.semibold))
                    }
                }
            }
        }.padding(24).frame(width: 1000).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = gallery; window.setContentSize(gallery.fittingSize)
        try await Task.sleep(for: .milliseconds(200)); gallery.layoutSubtreeIfNeeded()
        let galleryBitmap = gallery.bitmapImageRepForCachingDisplay(in: gallery.bounds)!
        gallery.cacheDisplay(in: gallery.bounds, to: galleryBitmap)
        try galleryBitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("12-styles.png"))
        window.close()
        // Isolated engine, no devices or network outputs. Verify actual native source and serialization.
        guard let engine = dante_engine_create_with_config(CommandLine.arguments[1], 1280, 720, 30, fixture.appendingPathComponent("engine").path) else { fatalError(copied(dante_engine_last_error(nil))) }
        studio.engine = engine; studio.refresh()
        precondition(studio.command("source.add", ["scene": studio.sceneName, "name": "Approved message QA", "type": "dante_superchat"]))
        studio.refresh()
        precondition(studio.command("source.update", ["name": "Approved message QA", "settings": ["style": 4, "font": "Georgia", "accent": 0xA044CC]]))
        precondition(studio.properties(name: "Approved message QA").object("settings").string("font") == "Georgia")
        precondition(studio.selected == nil || studio.error == nil)
        let saved = copied(dante_engine_save(engine))
        precondition(saved.contains("dante_superchat") && !saved.contains("Marina") && !saved.contains("experiência") && !saved.contains("R$ 25"))
        precondition(dante_chat_frame("Approved message QA", nil, 0, 0, 0, false)) // Clear succeeds.
        chat.reset(); studio.refresh()
        precondition(dante_engine_load(engine, saved)); studio.chatRenderer.invalidate(); studio.refresh()
        precondition(studio.items.contains { $0.string("type") == "dante_superchat" && $0.number("width") == 1100 })
        studio.shutdown()
        print("PASS: native overlay source, empty session, source persistence without message data, reload and teardown")
    }
}
