import AppKit

@MainActor func runYouTubeChatTests() async throws {
    func fixture(_ id: String, paid: Bool = false, text: String = "Pergunta de teste", channel: String = "viewer") -> [String: Any] {
        ["id": id, "authorDetails": ["channelId": channel, "displayName": "Canal de teste"],
         "snippet": ["type": paid ? "superChatEvent" : "textMessageEvent", "textMessageDetails": ["messageText": text], "superChatDetails": ["userComment": text, "amountDisplayString": "R$ 10,00"]]]
    }
    let chat = YouTubeChat(preferences: UserDefaults(suiteName: UUID().uuidString)!)
    chat.ingest([fixture("normal"), fixture("paid", paid: true), fixture("paid", paid: true)])
    precondition(chat.messages.count == 1 && chat.donations.count == 1 && chat.featured == nil)
    chat.show(chat.donations[0]); chat.hide(); precondition(chat.donations.isEmpty && chat.hiddenBeforeAirIDs.contains("paid"))
    chat.dismiss("paid"); chat.ingest([fixture("paid", paid: true)])
    precondition(chat.donations.isEmpty && chat.featured == nil)
    let long = String(repeating: "Texto com acentuação e 👩🏽‍💻. ", count: 50)
    let message = ChatMessage(fixture("long", paid: true, text: long))!
    precondition(message.pages.count > 1 && message.pages.joined() == long)
    let multiline = ChatMessage(fixture("lines", text: String(repeating: "linha\n", count: 100)))!
    precondition(multiline.pages.count >= 20 && multiline.pages.joined() == multiline.text)
    chat.show(message); chat.advance(10000); precondition(chat.page == message.pages.count - 1)
    chat.advance(-10000); precondition(chat.page == 0)
    chat.ingest([fixture("del", paid: true)]); chat.show(chat.donations[0])
    chat.ingest([["id": "delete-event", "snippet": ["type": "messageDeletedEvent", "messageDeletedDetails": ["deletedMessageId": "del"]]]])
    precondition(chat.featured == nil && chat.donations.isEmpty && !chat.wasDisplayed("del"))
    chat.ingest([fixture("banned", paid: true)]); chat.show(chat.donations[0])
    chat.ingest([["id": "ban-event", "snippet": ["type": "userBannedEvent", "userBannedDetails": ["bannedUserDetails": ["channelId": "viewer"]]]]])
    precondition(chat.messages.isEmpty && chat.donations.isEmpty && chat.featured == nil && !chat.wasDisplayed("banned"))
    chat.ingest((0..<550).map { fixture("paid-\($0)", paid: true) })
    precondition(chat.donations.count == 500 && chat.overflow == 50)
    chat.ingest((0..<200).map { fixture("text-\($0)") }); precondition(chat.messages.count == 200)
    chat.ingest((200..<1_200).map { fixture("text-\($0)") })
    precondition(chat.messages.count == 1000 && chat.messageOverflow == 200)
    chat.reset(); precondition(chat.messages.isEmpty && chat.donations.isEmpty && chat.featured == nil && chat.overflow == 0)
    let installedFonts = ChatFontCatalog.availableFamilies()
    precondition(installedFonts.contains("Menlo") && installedFonts.count > 6)
    let formerlyMissing = installedFonts.first { !["Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Trebuchet MS", "Verdana"].contains($0) }!
    precondition(ChatFontCatalog.font(named: formerlyMissing, size: 24).familyName == formerlyMissing)
    precondition(ChatFontCatalog.isInstalled("Menlo"))
    precondition(ChatFontCatalog.font(named: "Menlo", size: 24).familyName == "Menlo")
    precondition(!ChatFontCatalog.isInstalled("Dante Missing Font Fixture"))
    precondition(ChatFontCatalog.font(named: "Dante Missing Font Fixture", size: 24).familyName == NSFont.systemFont(ofSize: 24).familyName)
    // Remote HTML remains literal, and empty paid comments remain valid.
    precondition(ChatMessage(fixture("html", text: "<script>alert(1)</script>"))?.text == "<script>alert(1)</script>")
    precondition(ChatMessage(fixture("empty", paid: true, text: ""))?.pages == ["Obrigado pelo apoio!"])
    precondition(ChatMessage(fixture("oversize", text: String(repeating: "x", count: 20000))) == nil)
    for style in ChatStyle.all {
        let bitmap = ChatRaster.render(messages: [], featured: message, page: 0, lower: true, settings: ["style": style.id])!
        precondition(bitmap.pixelsWide == 1100 && bitmap.pixelsHigh == 420)
        precondition(bitmap.bitmapData![3] == 0) // Outer corner is transparent.
    }
    let visualDirectory = URL(fileURLWithPath:"build/chat-qa",isDirectory:true)
    try FileManager.default.createDirectory(at:visualDirectory,withIntermediateDirectories:true)
    let visualMessage = ChatMessage(fixture("visual",paid:true,
        text:"Obrigado por apoiar a live! Qual será o próximo tema?"))!
    for style in [0, 3, 7] {
        for (name, width, height) in [("compact",480,180),("wide",1100,300)] {
            let visualSettings: [String: Any] = ["style":style,"layoutWidth":width,"layoutHeight":height]
            precondition(ChatRaster.pages(for:visualMessage,settings:visualSettings).count == 1,
                         "A short highlighted message must not be split in a compact card")
            let bitmap = ChatRaster.render(messages:[],featured:visualMessage,page:0,lower:true,
                settings:visualSettings)!
            try bitmap.representation(using:.png,properties:[:])!.write(
                to:visualDirectory.appendingPathComponent("featured-\(style)-\(name).png"))
        }
    }
    let normalHighlight = ChatMessage(fixture("normal-visual",text:"Como você prepara as cenas antes da live?"))!
    let normalBitmap = ChatRaster.render(messages:[],featured:normalHighlight,page:0,lower:true,
        settings:["style":0,"layoutWidth":480,"layoutHeight":180])!
    try normalBitmap.representation(using:.png,properties:[:])!.write(
        to:visualDirectory.appendingPathComponent("featured-comment-compact.png"))
    func pixels(_ bitmap: NSBitmapImageRep) -> Data { Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
    let comment = ChatMessage(fixture("typography", text:"Mensagem de teste"))!
    let commentBase: [String: Any] = ["font":"Menlo", "layoutWidth":620, "layoutHeight":260]
    let commentOriginal = pixels(ChatRaster.render(messages:[comment],featured:nil,page:0,lower:false,settings:commentBase)!)
    for role in ["name", "body"] {
        var changed = commentBase
        changed[role + "Font"] = "Georgia"
        precondition(pixels(ChatRaster.render(messages:[comment],featured:nil,page:0,lower:false,settings:changed)!) != commentOriginal)
        changed = commentBase
        changed[role + "Underline"] = true
        precondition(pixels(ChatRaster.render(messages:[comment],featured:nil,page:0,lower:false,settings:changed)!) != commentOriginal)
    }
    var explicitLegacy = commentBase
    explicitLegacy["nameFont"] = "Menlo"; explicitLegacy["bodyFont"] = "Menlo"
    precondition(pixels(ChatRaster.render(messages:[comment],featured:nil,page:0,lower:false,settings:explicitLegacy)!) == commentOriginal)
    let highlightBase: [String: Any] = ["font":"Menlo", "layoutWidth":1100, "layoutHeight":420]
    let highlightOriginal = pixels(ChatRaster.render(messages:[],featured:message,page:0,lower:true,settings:highlightBase)!)
    for role in ["badge", "amount"] {
        var changed = highlightBase
        changed[role + "Font"] = "Georgia"
        precondition(pixels(ChatRaster.render(messages:[],featured:message,page:0,lower:true,settings:changed)!) != highlightOriginal)
    }
    print("PASS: paid approval, dedup, dismissal, complete pagination, moderation, bounds, reset and 12 RGBA styles")

    // An explicit Hide finishes the operator queue, but never claims that a
    // preview-only message was actually transmitted.
    chat.reset(); chat.ingest([fixture("one",text:"Olá, Marina"),fixture("two",paid:true,text:"Outro apoio")])
    let first = chat.messages[0], second = chat.donations[0]
    chat.show(first); chat.updatePresentation(visible:false,now:0); chat.hide(); chat.updatePresentation(visible:false,now:40)
    precondition(chat.displayed == [first] && chat.pendingMessages.isEmpty && chat.hiddenBeforeAirIDs.contains("one"))
    chat.reset(); chat.ingest([fixture("one",text:"Olá, Marina"),fixture("two",paid:true,text:"Outro apoio")])
    chat.show(first); chat.updatePresentation(visible:true,now:50)
    precondition(chat.onAirID == "one")
    chat.updatePresentation(visible:false,now:60) // The source eye was hidden, not the explicit Hide action.
    chat.updatePresentation(visible:false,now:89.99)
    precondition(chat.displayed.isEmpty && chat.retiringIDs.contains("one"))
    chat.updatePresentation(visible:false,now:90)
    precondition(chat.displayed == [first] && chat.pendingMessages.isEmpty && !chat.hiddenBeforeAirIDs.contains("one"))
    precondition(chat.messages.count == 1) // Automatic chat feed is independent of operator queue.
    chat.show(second); chat.updatePresentation(visible:true,now:100)
    chat.updatePresentation(visible:false,now:110) // Eye/source hidden while still selected.
    chat.updatePresentation(visible:true,now:120) // Re-show cancels the old deadline.
    chat.updatePresentation(visible:true,now:145)
    precondition(chat.displayed == [first] && chat.retiringIDs.isEmpty)
    chat.hide(); chat.updatePresentation(visible:false,now:150)
    precondition(chat.displayed.count == 2 && chat.donations.isEmpty)
    precondition(chat.entries(in:"displayed",query:"MARINA",newestFirst:true) == [first])
    precondition(chat.entries(in:"displayed",query:"canal",newestFirst:false) == [first,second])
    precondition(chat.entries(in:"displayed",query:"",newestFirst:true) == [second,first])
    chat.ingest([["id":"delete-history","snippet":["type":"messageDeletedEvent","messageDeletedDetails":["deletedMessageId":"one"]]]])
    precondition(chat.displayed == [second])
    chat.reset(); precondition(chat.displayed.isEmpty && chat.hiddenBeforeAirIDs.isEmpty && chat.retiringIDs.isEmpty && chat.onAirID == nil)
    print("PASS: explicit Hide archives immediately with truthful preview status, source-eye retirement waits 30 seconds, search/order, moderation and reset")

    let preview: [[String: Any]] = [["name": "Programa", "items": [
        ["name": "Chat", "type": "dante_youtube_chat", "visible": true, "sourceActive": false]
    ]]]
    precondition(!ProgramChatVisibility.containsActiveChat(scenes: preview))
    let published: [[String: Any]] = [["name": "Programa", "items": [
        ["name": "Chat", "type": "dante_youtube_chat", "visible": false, "sourceActive": true]
    ]]]
    precondition(ProgramChatVisibility.containsActiveChat(scenes: published))
    let nestedProgram: [[String: Any]] = preview + [["name": "Cena aninhada", "items": [
        ["name": "Chat aninhado", "type": "dante_youtube_chat", "visible": true, "sourceActive": true]
    ]]]
    precondition(ProgramChatVisibility.containsActiveChat(scenes: nestedProgram))
    chat.updateDemand(programVisible: false, panelOpen: false)
    precondition(chat.automaticInterval == nil)
    chat.updateDemand(programVisible: false, panelOpen: true)
    precondition(chat.automaticInterval == 30)
    chat.setPanelAutomatic(false)
    precondition(chat.automaticInterval == nil)
    chat.updateDemand(programVisible: true, panelOpen: false)
    precondition(chat.automaticInterval == 10)
    chat.setOnAirInterval(15)
    precondition(chat.automaticInterval == 15)
    chat.updateDemand(programVisible: false, panelOpen: false)
    print("PASS: program-active source follows published snapshot, nested chat, panel/manual/on-air demand")

    // Fake transport verifies auth/query, late responses after reset, and server pacing.
    var calls = 0
    let api = YouTubeAPI { request in
        calls += 1
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        let json: [String: Any]
        if request.url!.path.hasSuffix("liveBroadcasts") {
            json = ["items": [["id": "live", "snippet": ["liveChatId": "chat-fixture"]]]]
        } else {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains { $0.name == "liveChatId" && $0.value == "chat-fixture" })
            json = ["items": [fixture("network", paid: true)], "nextPageToken": "next", "pollingIntervalMillis": 60000]
        }
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    chat.start(broadcast: "live", api: api, access: { "fixture" }, isSending: { true })
    try await Task.sleep(for: .milliseconds(120))
    precondition(calls == 0 && chat.donations.isEmpty)
    chat.refreshNow()
    for _ in 0..<150 { if !chat.donations.isEmpty { break }; try await Task.sleep(for: .milliseconds(10)) }
    precondition(chat.donations.count == 1 && calls == 2)
    try await Task.sleep(for: .milliseconds(80)); precondition(calls == 2)
    chat.reset(); precondition(chat.donations.isEmpty && !chat.running)
    let limitedPreferences = UserDefaults(suiteName: UUID().uuidString)!
    limitedPreferences.set(Array(repeating: Date().timeIntervalSince1970, count: 1200), forKey: "DanteLive.chatRequestTimes")
    let limitedChat = YouTubeChat(preferences: limitedPreferences)
    limitedChat.start(broadcast: "live", api: api, access: { "fixture" }, isSending: { true })
    limitedChat.refreshNow()
    for _ in 0..<150 { if !limitedChat.running { break }; try await Task.sleep(for: .milliseconds(10)) }
    precondition(!limitedChat.running && limitedChat.status.contains("Limite local") && calls == 2)
    limitedChat.reset()
    let slow = YouTubeAPI { request in
        try? await Task.sleep(for: .milliseconds(100))
        return (try JSONSerialization.data(withJSONObject: ["items": [["id": "live", "snippet": ["liveChatId": "late"]]]]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    chat.start(broadcast: "old", api: slow, access: { "fixture" }, isSending: { true })
    try await Task.sleep(for: .milliseconds(10)); chat.reset()
    try await Task.sleep(for: .milliseconds(140)); precondition(chat.messages.isEmpty && !chat.running)
    print("PASS: chat transport auth, idle/manual polling, server pacing, local quota guard, cancellation and stale response isolation")
}
