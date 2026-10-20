import AppKit
import SwiftUI
let appVersion = "Chat QA"
@main struct ChatQA {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        try await runStudioPanelTests()
        try await runYouTubeChatTests()
        try await runYouTubeActivityTests()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/chat-qa")
        let fixture = directory.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try await runYouTubeTests(directory: fixture)
        precondition(ChatCanvasExamples.allowed(active:false,preparing:false,countdown:nil,session:false))
        precondition(!ChatCanvasExamples.allowed(active:true,preparing:false,countdown:nil,session:false))
        precondition(!ChatCanvasExamples.allowed(active:false,preparing:true,countdown:nil,session:false))
        precondition(!ChatCanvasExamples.allowed(active:false,preparing:false,countdown:3,session:false))
        precondition(!ChatCanvasExamples.allowed(active:false,preparing:false,countdown:nil,session:true))
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
        let scaledFeed = ChatRaster.render(messages: chat.messages, featured: nil, page: 0, lower: false,
                                           settings: ["layoutWidth":480,"layoutHeight":720,"componentScale":1.5])!
        precondition(scaledFeed.pixelsWide == 720 && scaledFeed.pixelsHigh == 1080)
        precondition(ChatRaster.pages(for: chat.featured!, settings: ["componentScale":1.5]) ==
                     ChatRaster.pages(for: chat.featured!, settings: [:]))
        // Actual feed + highlight renders, not a mock design.
        let people=[("Marina","Boa noite, pessoal!"),("Lucas","Dante, mostra esse código?"),("Bia","Agora entendi! Muito bom.")]
        let feedMessages=people.enumerated().map { index,pair in ChatMessage(["id":"visual-\(index)","authorDetails":["displayName":pair.0],"snippet":["type":"textMessageEvent","textMessageDetails":["messageText":pair.1]]])! }
        func spans(_ settings:[String:Any])->[Range<Int>] {
            let bitmap=ChatRaster.render(messages:Array(feedMessages.prefix(2)),featured:nil,page:0,lower:false,settings:settings)!
            var result:[Range<Int>]=[],start:Int?
            for y in 0..<bitmap.pixelsHigh {
                let alpha=bitmap.bitmapData![y*bitmap.bytesPerRow+bitmap.pixelsWide/2*4+3]
                if alpha>180 {if start==nil{start=y}}
                else if let first=start{result.append(first..<y);start=nil}
            }
            if let start{result.append(start..<bitmap.pixelsHigh)}
            return result
        }
        let compact=spans(["messageGap":10]),spaced=spans(["messageGap":30])
        precondition(compact.count==2 && spaced.count==2)
        precondition(spaced[1].lowerBound-compact[1].lowerBound==20)
        let largeName=spans(["nameSize":48]);precondition(largeName[0].count>compact[0].count)
        let largerText=spans(["fontSize":40]);precondition(largerText[0].count>compact[0].count)
        let largerAvatar=spans(["avatarSize":128]);precondition(largerAvatar[0].count>compact[0].count)
        let wideSettings:[String:Any]=["layoutWidth":3840,"layoutHeight":320,"avatarSize":96]
        precondition(ChatLayout(lower:true,settings:wideSettings).width==3840)
        let wideHighlight=ChatRaster.render(messages:[],featured:chat.featured,page:0,lower:true,settings:wideSettings)!
        precondition(wideHighlight.pixelsWide==3840)
        try wideHighlight.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("highlight-wide-avatar.png"))
        print("PASS: card spacing, independent font and avatar sizes, full-canvas highlight width; samples gated before live")
        for style in ChatStyle.all.prefix(6) {
            let settings:[String:Any]=["style":style.id,"layoutWidth":480,"layoutHeight":360,"nameSize":22,"fontSize":25,"messageGap":10]
            let bitmap=ChatRaster.render(messages:feedMessages,featured:nil,page:0,lower:false,settings:settings)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("feed-\(style.id).png"))
            var narrow=settings;narrow["layoutHeight"]=360
            let highlight=ChatRaster.render(messages:[],featured:chat.featured,page:0,lower:true,settings:narrow)!
            try highlight.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("highlight-\(style.id).png"))
        }
        for width in [240,480,1100] {
            for height in [140,420,720] {
                let settings:[String:Any]=["layoutWidth":width,"layoutHeight":height,"fontSize":32,"nameSize":24]
                let pages=ChatRaster.pages(for:chat.featured!,settings:settings)
                precondition(pages.joined()==chat.featured!.text)
                let bitmap=ChatRaster.render(messages:feedMessages,featured:chat.featured,page:100,lower:true,settings:settings)!
                precondition(bitmap.pixelsWide==width && bitmap.pixelsHigh==ChatLayout(lower:true,settings:settings).height)
            }
        }
        for (name,event,total) in [("likes",YouTubeActivityEvent(id:"likes",kind:.likes,name:"",total:1250),UInt64(1250)),("subscriber",YouTubeActivityEvent(id:"subscriber",kind:.subscriber,name:"Marina",total:nil),UInt64(1250))] {
            let bitmap=YouTubeActivityRaster.render(event:event,total:total,settings:[:])!
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("alert-\(name).png"))
        }
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
        let reference = NSHostingView(rootView: VStack(alignment:.leading,spacing:18) {
            Text("Chat e Super Chat • seis estilos").font(.title.bold())
            Text("Renderização real • mensagens fictícias").foregroundStyle(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:16),count:3),spacing:20) {
                ForEach(Array(ChatStyle.all.prefix(6))) { style in
                    VStack(alignment:.leading,spacing:8) {
                        Text(style.name).font(.headline)
                        Image(nsImage:NSImage(contentsOf:directory.appendingPathComponent("feed-\(style.id).png"))!).resizable().scaledToFit()
                        Image(nsImage:NSImage(contentsOf:directory.appendingPathComponent("highlight-\(style.id).png"))!).resizable().scaledToFit()
                    }.padding(12).background(Color(red:0.12,green:0.16,blue:0.22),in:RoundedRectangle(cornerRadius:14))
                }
            }
        }.padding(24).frame(width:1250).background(Color(red:0.055,green:0.07,blue:0.10)).environment(\.colorScheme,.dark))
        window.contentView=reference;window.setContentSize(reference.fittingSize)
        try await Task.sleep(for:.milliseconds(100));reference.layoutSubtreeIfNeeded()
        let rendered=reference.bitmapImageRepForCachingDisplay(in:reference.bounds)!
        reference.cacheDisplay(in:reference.bounds,to:rendered)
        try rendered.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("six-styles-revised.png"))
        struct SettingsQA:View {
            @LegacyState var settings:[String:Any]=[:]
            var body:some View {ScrollView{ChatStylePicker(settings:$settings){}.padding(16)}.frame(width:380,height:1000)}
        }
        let settingsHost=NSHostingView(rootView:SettingsQA().environment(\.colorScheme,.dark))
        window.contentView=settingsHost;window.setContentSize(settingsHost.fittingSize)
        try await Task.sleep(for:.milliseconds(100));settingsHost.layoutSubtreeIfNeeded()
        let settingsBitmap=settingsHost.bitmapImageRepForCachingDisplay(in:settingsHost.bounds)!
        settingsHost.cacheDisplay(in:settingsHost.bounds,to:settingsBitmap)
        try settingsBitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("chat-settings-revised.png"))
        struct MarqueeQA: View {
            @LegacyState var settings: [String: Any]
            var body: some View {
                ScrollView { MarqueeSettingsView(settings: $settings, onEdit: { _ in }).padding(16) }
                    .frame(width: 420, height: 1060)
            }
        }
        for (name, settings) in [
            ("marquee-controls", ["text": "Acesse: academy.dantetesta.com.br", "gradientEnabled": true, "gradientEndColor": 0x354CA0, "backgroundOpacity": 0.8, "gradientEndOpacity": 0.35] as [String: Any]),
            ("phrase-controls", ["displayMode": 1, "text": "Primeira frase\nSegunda frase", "phraseInterval": 5, "slideDirection": 1] as [String: Any])
        ] {
            let host = NSHostingView(rootView: MarqueeQA(settings: settings).environment(\.colorScheme, .dark))
            window.contentView = host; window.setContentSize(host.fittingSize)
            try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name).png"))
        }
        let libraryDirectory=directory.appendingPathComponent("library-visual")
        try FileManager.default.createDirectory(at:libraryDirectory,withIntermediateDirectories:true)
        var libraryPrefs=YouTubePreferences()
        let libraryAccount=YouTubeAccount(id:"visual",name:"Canal de exemplo",tokenAccount:"unused",clientID:"unused")
        libraryPrefs.accounts=[libraryAccount];libraryPrefs.selectedAccount=libraryAccount.id
        var libraryDraft=YouTubeDraftState();libraryDraft.draft.title="Conversa com a comunidade"
        libraryPrefs.states[libraryAccount.id]=libraryDraft
        try JSONEncoder().encode(libraryPrefs).write(to:libraryDirectory.appendingPathComponent("youtube.json"))
        let libraryModel=YouTubeModel(directory:libraryDirectory,api:YouTubeAPI { _ in throw URLError(.notConnectedToInternet) },vault:LiveKeyVault(read:{ _ in "" },save:{ _,_ in },delete:{ _ in }))
        let libraryHost=NSHostingView(rootView:YouTubeLibraryView(youtube:libraryModel,forTransmission:false,onTransmit:{}) {}.environment(\.colorScheme,.dark))
        window.contentView=libraryHost;window.setContentSize(libraryHost.fittingSize)
        try await Task.sleep(for:.milliseconds(150));libraryHost.layoutSubtreeIfNeeded()
        let libraryBitmap=libraryHost.bitmapImageRepForCachingDisplay(in:libraryHost.bounds)!
        libraryHost.cacheDisplay(in:libraryHost.bounds,to:libraryBitmap)
        try libraryBitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("library-tabs.png"))
        libraryModel.shutdown()
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
        let editor=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:360),styleMask:[.borderless],backing:.buffered,defer:false)
        editor.isReleasedWhenClosed=false
        studio.refresh();studio.selectedItem=studio.items.first!.sceneItemID
        let editorHost=NSHostingView(rootView:CanvasView(model:studio).frame(width:640,height:360).environment(\.colorScheme,.dark))
        editor.contentView=editorHost;editor.orderBack(nil)
        try await Task.sleep(for:.milliseconds(200));editorHost.layoutSubtreeIfNeeded()
        let editorBitmap=editorHost.bitmapImageRepForCachingDisplay(in:editorHost.bounds)!
        editorHost.cacheDisplay(in:editorHost.bounds,to:editorBitmap)
        try editorBitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("editor-example.png"))
        precondition((editorBitmap.colorAt(x:300,y:250)?.redComponent ?? 0)>0.1,"Editor must display sample pixels")
        func send(_ type:NSEvent.EventType,_ point:CGPoint) {
            let event=NSEvent.mouseEvent(with:type,location:CGPoint(x:point.x,y:360-point.y),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:editor.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            editor.sendEvent(event)
        }
        func drag(_ from:CGPoint,_ to:CGPoint) async throws {
            send(.leftMouseDown,from)
            for n in 1...8 {send(.leftMouseDragged,CGPoint(x:from.x+(to.x-from.x)*Double(n)/8,y:from.y+(to.y-from.y)*Double(n)/8));try await Task.sleep(for:.milliseconds(30))}
            send(.leftMouseUp,to);try await Task.sleep(for:.milliseconds(120));studio.refresh()
        }
        try await drag(CGPoint(x:595,y:180),CGPoint(x:495,y:180))
        precondition(abs(studio.selected!.number("width")-900)<=2 && studio.selected!.number("height")==420)
        precondition(studio.selected!.number("scaleX")==1 && studio.selected!.number("scaleY")==1)
        try await drag(CGPoint(x:270,y:285),CGPoint(x:270,y:245))
        precondition(abs(studio.selected!.number("height")-340)<=2 && abs(studio.selected!.number("width")-900)<=2)
        print("PASS: actual SwiftUI side handles reflow width and height independently without changing text scale; editor sample pixels visible")
        editor.orderOut(nil);editor.contentView=nil;editor.close()
        studio.shutdown()
        print("PASS: native overlay source, empty session, source persistence without message data, reload and teardown")
    }
}
