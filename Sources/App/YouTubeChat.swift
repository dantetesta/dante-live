import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let channelID: String
    let author: String
    let text: String
    let amount: String
    let paid: Bool
    // Plain strings only: never evaluate remote HTML, URLs or scripts in overlays.
    init?(_ item: [String: Any]) {
        let snippet = item.object("snippet"), author = item.object("authorDetails")
        let type = snippet.string("type")
        guard ["textMessageEvent", "superChatEvent", "superStickerEvent"].contains(type), !item.string("id").isEmpty else { return nil }
        id = item.string("id"); channelID = author.string("channelId")
        self.author = String(author.string("displayName", "Participante").prefix(200))
        paid = type != "textMessageEvent"
        let details = snippet.object(type == "superChatEvent" ? "superChatDetails" : "superStickerDetails")
        amount = String(details.string("amountDisplayString").prefix(80))
        if type == "superChatEvent" { text = details.string("userComment") }
        else if type == "superStickerEvent" { text = details.object("superStickerMetadata").string("altText", "Super Sticker") }
        else { text = snippet.object("textMessageDetails").string("messageText", snippet.string("displayMessage")) }
        // Reject anomalous oversized payloads instead of silently cutting donations.
        guard text.utf8.count <= 16_384 else { return nil }
    }
    var pages: [String] {
        if text.isEmpty { return ["Obrigado pelo apoio!"] }
        var remaining = text[...], result: [String] = []
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(380, remaining.count))
            var split = end
            var breaks = 0
            for index in remaining[..<end].indices where remaining[index].isNewline {
                breaks += 1
                if breaks == 5 { split = remaining.index(after: index); break }
            }
            if split == end, end != remaining.endIndex, let space = remaining[..<end].lastIndex(where: { $0.isWhitespace }), remaining.distance(from: remaining.startIndex, to: space) > 240 {
                split = remaining.index(after: space)
            }
            result.append(String(remaining[..<split])); remaining = remaining[split...]
        }
        return result
    }
}

/// Session-only state. Nothing in this model is Codable or written to disk.
@MainActor final class YouTubeChat: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var donations: [ChatMessage] = []
    @Published private(set) var featured: ChatMessage?
    @Published private(set) var page = 0
    @Published private(set) var status = "O chat será conectado quando a live do YouTube começar."
    @Published private(set) var running = false
    private(set) var sessionActive = false
    @Published private(set) var overflow = 0
    @Published private(set) var revision = 0
    private var seen = Set<String>(), seenOrder: [String] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var resumeCursor = ""
    var featureText: String { featured.map { $0.pages[min(page, $0.pages.count - 1)] } ?? "" }
    func show(_ message: ChatMessage) { featured = message; page = 0; revision += 1 }
    func hide() { featured = nil; page = 0; revision += 1 }
    func advance(_ direction: Int, pageCount: Int? = nil) {
        guard let featured else { return }; let count = max(1, pageCount ?? featured.pages.count)
        page = min(count - 1, max(0, min(page, count - 1) + direction)); revision += 1
    }
    func dismiss(_ id: String) { donations.removeAll { $0.id == id }; if featured?.id == id { hide() } }
    func reset() {
        task?.cancel(); task = nil; generation = UUID(); running = false; sessionActive = false; resumeCursor = ""
        messages.removeAll(); donations.removeAll(); seen.removeAll(); seenOrder.removeAll(); featured = nil; page = 0; overflow = 0; revision += 1
        status = "O chat será conectado quando a live do YouTube começar."
    }
    func ingest(_ items: [[String: Any]]) {
        for item in items {
            let id = item.string("id")
            if item.object("snippet").string("type") == "tombstone" { removeMessage(id); continue }
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            seenOrder.append(id)
            let snippet = item.object("snippet"), type = snippet.string("type")
            if type == "messageDeletedEvent" {
                removeMessage(snippet.object("messageDeletedDetails").string("deletedMessageId"))
            } else if type == "userBannedEvent" {
                let channel = snippet.object("userBannedDetails").object("bannedUserDetails").string("channelId")
                messages.removeAll { $0.channelID == channel }; donations.removeAll { $0.channelID == channel }
                if featured?.channelID == channel { hide() }
            } else if let message = ChatMessage(item) {
                // Paid messages never enter the automatic public feed before approval.
                if message.paid {
                    if donations.count < 500 { donations.append(message) }
                    else { overflow += 1 }
                } else { messages.append(message) }
            }
        }
        if messages.count > 100 { messages.removeFirst(messages.count - 100) }
        if seenOrder.count > 10_000 {
            for id in seenOrder.prefix(seenOrder.count - 10_000) { seen.remove(id) }
            seenOrder.removeFirst(seenOrder.count - 10_000)
        }
        revision += 1
    }
    private func removeMessage(_ id: String) {
        messages.removeAll { $0.id == id }; donations.removeAll { $0.id == id }
        if featured?.id == id { hide() }
    }
    func start(broadcast: String, api: YouTubeAPI, access: @escaping @MainActor () async throws -> String, isSending: @escaping @MainActor () -> Bool, preserveQueue: Bool = false) {
        if preserveQueue { task?.cancel(); generation = UUID() } else { reset() }
        running = true; sessionActive = true; status = "Conectando ao chat…"; let session = generation
        task = Task { [weak self] in
            var chatID = "", cursor = self?.resumeCursor ?? "", failures = 0
            while !Task.isCancelled {
                guard let self, self.generation == session else { return }
                guard isSending() else { self.reset(); return }
                do {
                    let token = try await access()
                    if chatID.isEmpty {
                        let event = try await api.broadcast(broadcast, token: token)
                        chatID = event.liveChatID ?? ""
                        if chatID.isEmpty {
                            self.status = "Aguardando o chat da live. Confira se ele está habilitado no YouTube."
                            try await Task.sleep(for: .seconds(10)); continue
                        }
                    }
                    var query = ["liveChatId": chatID, "part": "snippet,authorDetails", "maxResults": "200", "hl": "pt-BR"]
                    if !cursor.isEmpty { query["pageToken"] = cursor }
                    let response = try await api.call("liveChat/messages", token: token, query: query)
                    try Task.checkCancellation()
                    guard self.generation == session else { return }
                    self.ingest(response.array("items")); cursor = response.string("nextPageToken"); self.resumeCursor = cursor
                    if response["offlineAt"] != nil { self.reset(); self.status = "Chat encerrado pelo YouTube."; return }
                    guard !cursor.isEmpty else {
                        self.running = false; self.status = "O YouTube não forneceu a próxima página do chat. A fila foi preservada."; return
                    }
                    self.status = "Chat conectado • destaques sob seu controle"; failures = 0
                    // Respect the server cadence, with a floor to limit quota consumption.
                    let seconds = max(5, response.number("pollingIntervalMillis", 5000) / 1000)
                    try await Task.sleep(for: .seconds(seconds))
                } catch is CancellationError { return }
                catch {
                    guard self.generation == session, !Task.isCancelled else { return }
                    if let apiError = error as? YouTubeAPIError,
                       ["quotaExceeded", "dailyLimitExceeded", "liveChatDisabled", "liveChatEnded", "liveChatNotFound", "forbidden", "insufficientPermissions", "unauthorized", "invalid_grant"].contains(apiError.reason) {
                        self.running = false
                        self.status = "Chat indisponível: \(error.localizedDescription)"
                        if apiError.reason == "liveChatEnded" { self.reset(); self.status = "Chat encerrado pelo YouTube." }
                        return
                    }
                    failures += 1; self.status = "Reconectando ao chat… A fila foi preservada."
                    do { try await Task.sleep(for: .seconds(min(60, pow(2, Double(min(failures, 5))) * 2))) } catch { return }
                }
            }
        }
    }
}
