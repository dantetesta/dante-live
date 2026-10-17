import AppKit

@MainActor func runYouTubeChatTests() async throws {
    func fixture(_ id: String, paid: Bool = false, text: String = "Pergunta de teste", channel: String = "viewer") -> [String: Any] {
        ["id": id, "authorDetails": ["channelId": channel, "displayName": "Canal de teste"],
         "snippet": ["type": paid ? "superChatEvent" : "textMessageEvent", "textMessageDetails": ["messageText": text], "superChatDetails": ["userComment": text, "amountDisplayString": "R$ 10,00"]]]
    }
    let chat = YouTubeChat()
    chat.ingest([fixture("normal"), fixture("paid", paid: true), fixture("paid", paid: true)])
    precondition(chat.messages.count == 1 && chat.donations.count == 1 && chat.featured == nil)
    chat.show(chat.donations[0]); chat.hide(); precondition(chat.donations.count == 1)
    chat.show(chat.donations[0]); chat.dismiss("paid"); chat.ingest([fixture("paid", paid: true)])
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
    precondition(chat.featured == nil && chat.donations.isEmpty)
    chat.ingest([fixture("banned", paid: true)]); chat.show(chat.donations[0])
    chat.ingest([["id": "ban-event", "snippet": ["type": "userBannedEvent", "userBannedDetails": ["bannedUserDetails": ["channelId": "viewer"]]]]])
    precondition(chat.messages.isEmpty && chat.donations.isEmpty && chat.featured == nil)
    chat.ingest((0..<550).map { fixture("paid-\($0)", paid: true) })
    precondition(chat.donations.count == 500 && chat.overflow == 50)
    chat.ingest((0..<200).map { fixture("text-\($0)") }); precondition(chat.messages.count == 100)
    chat.reset(); precondition(chat.messages.isEmpty && chat.donations.isEmpty && chat.featured == nil && chat.overflow == 0)
    // Remote HTML remains literal, and empty paid comments remain valid.
    precondition(ChatMessage(fixture("html", text: "<script>alert(1)</script>"))?.text == "<script>alert(1)</script>")
    precondition(ChatMessage(fixture("empty", paid: true, text: ""))?.pages == ["Obrigado pelo apoio!"])
    precondition(ChatMessage(fixture("oversize", text: String(repeating: "x", count: 20000))) == nil)
    for style in ChatStyle.all {
        let bitmap = ChatRaster.render(messages: [], featured: message, page: 0, lower: true, settings: ["style": style.id])!
        precondition(bitmap.pixelsWide == 1100 && bitmap.pixelsHigh == 420)
        precondition(bitmap.bitmapData![3] == 0) // Outer corner is transparent.
    }
    print("PASS: paid approval, dedup, dismissal, complete pagination, moderation, bounds, reset and 12 RGBA styles")

    // Selecting alone does not count. Only a program-visible highlight starts the lifecycle.
    chat.reset(); chat.ingest([fixture("one",text:"Olá, Marina"),fixture("two",paid:true,text:"Outro apoio")])
    let first = chat.messages[0], second = chat.donations[0]
    chat.show(first); chat.updatePresentation(visible:false,now:0); chat.hide(); chat.updatePresentation(visible:false,now:40)
    precondition(chat.displayed.isEmpty && chat.pendingMessages.count == 1)
    chat.show(first); chat.updatePresentation(visible:true,now:50)
    precondition(chat.onAirID == "one")
    chat.hide(); chat.updatePresentation(visible:false,now:60)
    chat.updatePresentation(visible:false,now:89.99)
    precondition(chat.displayed.isEmpty && chat.retiringIDs.contains("one"))
    chat.updatePresentation(visible:false,now:90)
    precondition(chat.displayed == [first] && chat.pendingMessages.isEmpty)
    precondition(chat.messages.count == 1) // Automatic chat feed is independent of operator queue.
    chat.show(second); chat.updatePresentation(visible:true,now:100)
    chat.updatePresentation(visible:false,now:110) // Eye/source hidden while still selected.
    chat.updatePresentation(visible:true,now:120) // Re-show cancels the old deadline.
    chat.updatePresentation(visible:true,now:145)
    precondition(chat.displayed == [first] && chat.retiringIDs.isEmpty)
    chat.hide(); chat.updatePresentation(visible:false,now:150); chat.updatePresentation(visible:false,now:180)
    precondition(chat.displayed.count == 2 && chat.donations.isEmpty)
    precondition(chat.entries(in:"displayed",query:"MARINA",newestFirst:true) == [first])
    precondition(chat.entries(in:"displayed",query:"canal",newestFirst:false) == [first,second])
    precondition(chat.entries(in:"displayed",query:"",newestFirst:true) == [second,first])
    chat.ingest([["id":"delete-history","snippet":["type":"messageDeletedEvent","messageDeletedDetails":["deletedMessageId":"one"]]]])
    precondition(chat.displayed == [second])
    chat.reset(); precondition(chat.displayed.isEmpty && chat.retiringIDs.isEmpty && chat.onAirID == nil)
    print("PASS: program-visible history, exact 30-second retirement, hidden source, re-show cancellation, search/order, moderation and session reset")

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
    for _ in 0..<50 { if !chat.donations.isEmpty { break }; try await Task.sleep(for: .milliseconds(10)) }
    precondition(chat.donations.count == 1 && calls == 2)
    try await Task.sleep(for: .milliseconds(80)); precondition(calls == 2)
    chat.reset(); precondition(chat.donations.isEmpty && !chat.running)
    let slow = YouTubeAPI { request in
        try? await Task.sleep(for: .milliseconds(100))
        return (try JSONSerialization.data(withJSONObject: ["items": [["id": "live", "snippet": ["liveChatId": "late"]]]]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    chat.start(broadcast: "old", api: slow, access: { "fixture" }, isSending: { true })
    try await Task.sleep(for: .milliseconds(10)); chat.reset()
    try await Task.sleep(for: .milliseconds(140)); precondition(chat.messages.isEmpty && !chat.running)
    print("PASS: chat transport auth, chat ID, server pacing, cancellation and stale response isolation")
}
