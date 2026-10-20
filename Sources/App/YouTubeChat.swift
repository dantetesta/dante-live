import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let channelID: String
    let author: String
    let text: String
    let amount: String
    let paid: Bool
    let publishedAt: Date?
    // Plain strings only: never evaluate remote HTML, URLs or scripts in overlays.
    init?(_ item: [String: Any]) {
        let snippet = item.object("snippet"), author = item.object("authorDetails")
        let type = snippet.string("type")
        guard ["textMessageEvent", "superChatEvent", "superStickerEvent"].contains(type), !item.string("id").isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalDate = formatter.date(from: snippet.string("publishedAt"))
        formatter.formatOptions = [.withInternetDateTime]
        publishedAt = fractionalDate ?? formatter.date(from: snippet.string("publishedAt"))
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

/// The engine reports activity for the source actually shown by the program.
/// In Studio Mode the editable scene may differ from the published snapshot.
enum ProgramChatVisibility {
    static func containsActiveChat(scenes: [[String: Any]]) -> Bool {
        scenes.contains { scene in
            scene.array("items").contains { $0.string("type") == "dante_youtube_chat" && $0.flag("sourceActive") }
        }
    }
}

/// Messages are session-only. Only the operator's polling choices are stored.
@MainActor final class YouTubeChat: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var donations: [ChatMessage] = []
    @Published private(set) var featured: ChatMessage?
    @Published private(set) var page = 0
    @Published private(set) var displayed: [ChatMessage] = []
    @Published private(set) var hiddenBeforeAirIDs = Set<String>()
    @Published private(set) var onAirID: String?
    @Published private(set) var retiringIDs = Set<String>()
    private var onAir: ChatMessage?
    private var retirements: [String: (message: ChatMessage, deadline: TimeInterval)] = [:]
    var pendingMessages: [ChatMessage] { let shown = Set(displayed.map(\.id)); return messages.filter { !shown.contains($0.id) } }
    var pendingDonations: [ChatMessage] { let shown = Set(displayed.map(\.id)); return donations.filter { !shown.contains($0.id) } }
    func wasDisplayed(_ id: String) -> Bool { displayed.contains { $0.id == id } }
    /// Called from the program-source state, not from selecting a row in the UI.
    func updatePresentation(visible: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let current = visible ? featured : nil
        if current?.id != onAir?.id {
            if let previous = onAir { retirements[previous.id] = (previous, now + 30) }
            onAir = current; onAirID = current?.id
            if let current { retirements[current.id] = nil }
        }
        let completed = retirements.values.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
        for entry in completed { archive(entry.message, aired: true) }
        let ids = Set(retirements.keys)
        if retiringIDs != ids { retiringIDs = ids }
    }
    func entries(in section: String, query: String, newestFirst: Bool) -> [ChatMessage] {
        let values = section == "displayed" ? displayed : section == "conversation" ? pendingMessages : pendingDonations
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = values.enumerated().filter { search.isEmpty || $0.element.author.localizedStandardContains(search) || $0.element.text.localizedStandardContains(search) }
        return filtered.sorted { a, b in
            let left = a.element.publishedAt ?? .distantPast, right = b.element.publishedAt ?? .distantPast
            if left != right { return newestFirst ? left > right : left < right }
            return newestFirst ? a.offset > b.offset : a.offset < b.offset
        }.map(\.element)
    }
    @Published private(set) var status = "O chat será conectado quando a live do YouTube começar."
    @Published private(set) var running = false
    @Published private(set) var fetching = false
    @Published private(set) var refreshQueued = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var quotaBlocked = false
    @Published private(set) var panelAutomatic: Bool
    @Published private(set) var panelIntervalSeconds: Int
    @Published private(set) var onAirIntervalSeconds: Int
    private(set) var sessionActive = false
    @Published private(set) var overflow = 0
    @Published private(set) var messageOverflow = 0
    @Published private(set) var revision = 0
    private var seen = Set<String>(), seenOrder: [String] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var resumeCursor = ""
    private var liveChatID = ""
    var resolvedLiveChatID: String? { sessionActive && !liveChatID.isEmpty ? liveChatID : nil }
    private var nextRequestAt = Date.distantPast
    private var lastRequestAt: Date?
    private var panelOpen = false
    private var programChatVisible = false
    private let preferences: UserDefaults
    private var chatRequestTimes: [TimeInterval]
    private let chatRequestLimit = 1200 // 6,000 units for chat in any rolling 24 hours on this Mac.
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        chatRequestTimes = preferences.array(forKey: "DanteLive.chatRequestTimes") as? [TimeInterval] ?? []
        panelAutomatic = preferences.object(forKey: "DanteLive.chatPanelAutomatic") as? Bool ?? true
        let panel = preferences.integer(forKey: "DanteLive.chatPanelInterval")
        panelIntervalSeconds = [30, 60].contains(panel) ? panel : 30
        let onAir = preferences.integer(forKey: "DanteLive.chatOnAirInterval")
        onAirIntervalSeconds = [10, 15, 30].contains(onAir) ? onAir : 10
    }
    var automaticInterval: TimeInterval? {
        if programChatVisible { return TimeInterval(onAirIntervalSeconds) }
        if panelOpen && panelAutomatic { return TimeInterval(panelIntervalSeconds) }
        return nil
    }
    func updateDemand(programVisible: Bool, panelOpen: Bool) {
        programChatVisible = programVisible
        self.panelOpen = panelOpen
    }
    func setPanelAutomatic(_ value: Bool) {
        panelAutomatic = value
        preferences.set(value, forKey: "DanteLive.chatPanelAutomatic")
    }
    func setPanelInterval(_ seconds: Int) {
        guard [30, 60].contains(seconds) else { return }
        panelIntervalSeconds = seconds
        preferences.set(seconds, forKey: "DanteLive.chatPanelInterval")
    }
    func setOnAirInterval(_ seconds: Int) {
        guard [10, 15, 30].contains(seconds) else { return }
        onAirIntervalSeconds = seconds
        preferences.set(seconds, forKey: "DanteLive.chatOnAirInterval")
    }
    func refreshNow() {
        guard sessionActive, running, !quotaBlocked else { return }
        refreshQueued = true
    }
    private func registerChatRequest(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        chatRequestTimes.removeAll { $0 <= now - 86_400 || $0 > now }
        guard chatRequestTimes.count < chatRequestLimit else { return false }
        chatRequestTimes.append(now)
        preferences.set(chatRequestTimes, forKey: "DanteLive.chatRequestTimes")
        return true
    }
    private var hasLocalChatBudget: Bool {
        let now = Date().timeIntervalSince1970
        return chatRequestTimes.filter { $0 > now - 86_400 && $0 <= now }.count < chatRequestLimit
    }
    private func pauseForLocalBudget() {
        fetching = false; running = false
        status = "Limite local de 6.000 unidades do chat em 24 horas atingido. Aguarde a janela móvel liberar consultas; a cota real do projeto pode ser diferente."
    }
    var featureText: String { featured.map { $0.pages[min(page, $0.pages.count - 1)] } ?? "" }
    func show(_ message: ChatMessage) { featured = message; page = 0; revision += 1 }
    private func archive(_ message: ChatMessage, aired: Bool) {
        displayed.removeAll { $0.id == message.id }
        displayed.append(message)
        donations.removeAll { $0.id == message.id }
        retirements[message.id] = nil
        retiringIDs.remove(message.id)
        if aired { hiddenBeforeAirIDs.remove(message.id) }
        else { hiddenBeforeAirIDs.insert(message.id) }
        if displayed.count > 500 {
            let expired = displayed.prefix(displayed.count - 500)
            for entry in expired { hiddenBeforeAirIDs.remove(entry.id) }
            displayed.removeFirst(displayed.count - 500)
        }
    }
    /// Hiding a row finishes its operator queue immediately. Keep a truthful
    /// label when it was reviewed in preview but never reached the program.
    func hide(_ message: ChatMessage) {
        let aired = onAirID == message.id || (wasDisplayed(message.id) && !hiddenBeforeAirIDs.contains(message.id))
        archive(message, aired: aired)
        if featured?.id == message.id { featured = nil; page = 0 }
        if onAirID == message.id { onAir = nil; onAirID = nil }
        revision += 1
    }
    func hide() {
        guard let featured else { return }
        hide(featured)
    }
    func advance(_ direction: Int, pageCount: Int? = nil) {
        guard let featured else { return }; let count = max(1, pageCount ?? featured.pages.count)
        page = min(count - 1, max(0, min(page, count - 1) + direction)); revision += 1
    }
    func dismiss(_ id: String) { removeMessage(id) }
    func reset() {
        task?.cancel(); task = nil; generation = UUID(); running = false; sessionActive = false; resumeCursor = ""; liveChatID = ""
        fetching = false; refreshQueued = false; lastUpdatedAt = nil; quotaBlocked = false
        nextRequestAt = .distantPast; lastRequestAt = nil; panelOpen = false; programChatVisible = false
        displayed.removeAll(); hiddenBeforeAirIDs.removeAll(); retirements.removeAll(); retiringIDs.removeAll(); onAir = nil; onAirID = nil
        messages.removeAll(); donations.removeAll(); seen.removeAll(); seenOrder.removeAll(); featured = nil; page = 0; overflow = 0; messageOverflow = 0; revision += 1
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
                let affected = messages + donations + displayed + retirements.values.map(\.message) + [featured, onAir].compactMap { $0 }
                for message in affected where message.channelID == channel { removeMessage(message.id) }
            } else if let message = ChatMessage(item) {
                // Paid messages never enter the automatic public feed before approval.
                if message.paid {
                    if donations.count < 500 { donations.append(message) }
                    else { overflow += 1 }
                } else { messages.append(message) }
            }
        }
        if messages.count > 1000 { let removed = messages.count - 1000; messages.removeFirst(removed); messageOverflow += removed }
        if seenOrder.count > 10_000 {
            for id in seenOrder.prefix(seenOrder.count - 10_000) { seen.remove(id) }
            seenOrder.removeFirst(seenOrder.count - 10_000)
        }
        revision += 1
    }
    private func removeMessage(_ id: String) {
        messages.removeAll { $0.id == id }; donations.removeAll { $0.id == id }; displayed.removeAll { $0.id == id }; hiddenBeforeAirIDs.remove(id)
        retirements[id] = nil; retiringIDs.remove(id)
        if onAir?.id == id { onAir = nil; onAirID = nil }
        if featured?.id == id { featured = nil; page = 0; revision += 1 }
    }
    func start(broadcast: String, api: YouTubeAPI, access: @escaping @MainActor () async throws -> String, isSending: @escaping @MainActor () -> Bool, preserveQueue: Bool = false) {
        if preserveQueue { task?.cancel(); generation = UUID() } else { reset() }
        running = true; sessionActive = true; fetching = false; quotaBlocked = false
        status = "Chat pronto. As consultas começam quando o chat estiver no Programa ou esta janela solicitar atualização."
        let session = generation
        task = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.generation == session else { return }
                guard isSending() else { self.reset(); return }
                let interval = self.automaticInterval
                if interval == nil && !self.refreshQueued {
                    let paused = "Consultas pausadas • abra a janela com atualização automática, consulte manualmente ou exiba o chat no Programa."
                    if self.status != paused { self.status = paused }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    continue
                }
                let automaticDue = self.lastRequestAt?.addingTimeInterval(interval ?? 0) ?? .distantPast
                let due = max(self.nextRequestAt, self.refreshQueued ? .distantPast : automaticDue)
                let wait = due.timeIntervalSinceNow
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(min(1, wait))) } catch { return }
                    continue
                }
                self.refreshQueued = false
                guard self.hasLocalChatBudget else { self.pauseForLocalBudget(); return }
                self.fetching = true
                do {
                    let token = try await access()
                    if self.liveChatID.isEmpty {
                        let event = try await api.broadcast(broadcast, token: token)
                        try Task.checkCancellation()
                        guard self.generation == session else { return }
                        self.liveChatID = event.liveChatID ?? ""
                        if self.liveChatID.isEmpty {
                            self.fetching = false
                            self.status = "Aguardando o chat da live. Confira se ele está habilitado no YouTube."
                            try await Task.sleep(for: .seconds(10)); continue
                        }
                    }
                    var query = ["liveChatId": self.liveChatID, "part": "snippet,authorDetails", "maxResults": "500", "hl": "pt-BR"]
                    if !self.resumeCursor.isEmpty { query["pageToken"] = self.resumeCursor }
                    guard self.registerChatRequest() else {
                        self.pauseForLocalBudget()
                        return
                    }
                    self.lastRequestAt = Date()
                    let response = try await api.call("liveChat/messages", token: token, query: query)
                    try Task.checkCancellation()
                    guard self.generation == session else { return }
                    self.fetching = false
                    self.ingest(response.array("items")); self.resumeCursor = response.string("nextPageToken")
                    self.lastUpdatedAt = Date()
                    self.nextRequestAt = Date().addingTimeInterval(max(5, response.number("pollingIntervalMillis", 5000) / 1000))
                    if response["offlineAt"] != nil { self.reset(); self.status = "Chat encerrado pelo YouTube."; return }
                    guard !self.resumeCursor.isEmpty else {
                        self.running = false; self.status = "O YouTube não forneceu a próxima página do chat. A fila foi preservada."; return
                    }
                    self.status = "Chat atualizado • destaques sob seu controle"; failures = 0
                } catch is CancellationError { self.fetching = false; return }
                catch {
                    guard self.generation == session, !Task.isCancelled else { return }
                    self.fetching = false
                    if let apiError = error as? YouTubeAPIError,
                       ["quotaExceeded", "dailyLimitExceeded", "liveChatDisabled", "liveChatEnded", "liveChatNotFound", "forbidden", "insufficientPermissions", "unauthorized", "invalid_grant"].contains(apiError.reason) {
                        self.running = false
                        self.quotaBlocked = ["quotaExceeded", "dailyLimitExceeded"].contains(apiError.reason)
                        self.status = "Chat indisponível: \(error.localizedDescription)"
                        if apiError.reason == "liveChatEnded" { self.reset(); self.status = "Chat encerrado pelo YouTube." }
                        return
                    }
                    if let apiError = error as? YouTubeAPIError, apiError.reason == "pageTokenInvalid" {
                        self.resumeCursor = ""
                        self.nextRequestAt = Date().addingTimeInterval(5)
                        self.status = "O YouTube invalidou o ponto de retomada. A próxima consulta trará mensagens recentes; parte do intervalo pode faltar."
                        continue
                    }
                    failures += 1; self.status = "Reconectando ao chat… A fila foi preservada."
                    let isRateLimited = (error as? YouTubeAPIError)?.reason == "rateLimitExceeded"
                    self.nextRequestAt = Date().addingTimeInterval(isRateLimited ? 60 : min(60, pow(2, Double(min(failures, 5))) * 2))
                }
            }
        }
    }
}
