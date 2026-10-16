import Foundation

struct YouTubeAPIError: LocalizedError {
    let reason: String
    var statusCode: Int = 0
    var definitelyRejected: Bool { (400..<500).contains(statusCode) && statusCode != 408 }
    var errorDescription: String? {
        switch reason {
        case "quotaExceeded", "dailyLimitExceeded": "A cota da API do YouTube foi atingida. Tente mais tarde."
        case "liveStreamingNotEnabled", "livePermissionBlocked", "insufficientLivePermissions": "O YouTube ainda não permite lives neste canal. Confira a habilitação no YouTube Studio."
        case "invalid_grant", "unauthorized": "A autorização do YouTube expirou ou foi revogada. Conecte o canal novamente."
        case "forbidden", "insufficientPermissions": "O YouTube não autorizou esta ação. Confira a conta e as permissões."
        default: "O YouTube não concluiu a operação (\(reason)). Confira o estado da live antes de tentar novamente."
        }
    }
}
struct YouTubeOAuthClient: Codable {
    let clientID: String
    let clientSecret: String
    static func parse(_ data: Data) throws -> Self {
        guard data.count < 65_536, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let installed = root["installed"] as? [String: Any],
              let id = installed["client_id"] as? String, id.hasSuffix(".apps.googleusercontent.com"), id.count < 512,
              let secret = installed["client_secret"] as? String, !secret.isEmpty else { throw StudioError.message("Escolha o JSON de um cliente OAuth Google do tipo Aplicativo para computador.") }
        return Self(clientID: id, clientSecret: secret)
    }
}
struct YouTubeTokens: Codable { var access: String; var refresh: String; var expires: Date }
struct YouTubeAccount: Codable, Identifiable { var id: String; var name: String; var tokenAccount: String; var clientID: String }
struct YouTubeDraft: Codable, Equatable {
    var title = ""
    var description = ""
    var tags = ""
    var privacy = "unlisted"
    var category = "22"
    var madeForKids = false
    var latency = "normal"
    var scheduledAt = Date().addingTimeInterval(3600)
    var thumbnailFile: String?
    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 100, description.utf8.count <= 5000,
              tags.count <= 500, ["public","unlisted","private"].contains(privacy), ["normal","low","ultraLow"].contains(latency), Int(category) != nil else {
            throw StudioError.message("Informe título (até 100 caracteres), descrição (até 5.000 bytes) e palavras-chave (até 500 caracteres), com visibilidade e latência válidas.")
        }
    }
}
struct YouTubeBroadcast: Codable, Identifiable {
    var id: String
    var title: String
    var description: String
    var privacy: String
    var scheduledAt: String
    var thumbnailURL: String?
    var boundStreamID: String
    var lifeCycle: String
    var autoStart: Bool
    init(_ json: [String: Any]) {
        id = json.string("id"); let snippet = json.object("snippet"); let status = json.object("status"); let content = json.object("contentDetails")
        title = snippet.string("title"); description = snippet.string("description"); privacy = status.string("privacyStatus")
        scheduledAt = snippet.string("scheduledStartTime"); boundStreamID = content.string("boundStreamId"); lifeCycle = status.string("lifeCycleStatus")
        autoStart = content.flag("enableAutoStart")
        thumbnailURL = snippet.object("thumbnails").object("medium")["url"] as? String
    }
    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}
struct YouTubeDraftState: Codable {
    var draft = YouTubeDraft()
    var selectedBroadcast: String?
    /// Journal successful remote creations before continuing the next API step.
    var createdBroadcast: String?
    var submittedDraft: YouTubeDraft?
    var createdStream: String?
    var creationUncertain = false
    var streamCreationUncertain = false
    var preparationComplete: Bool?
}
struct YouTubeSavedLive: Codable, Identifiable {
    var id: String = UUID().uuidString
    var state: YouTubeDraftState
}
struct YouTubePreferences: Codable {
    var accounts: [YouTubeAccount] = []
    var selectedAccount: String?
    var states: [String: YouTubeDraftState] = [:]
    // Optional for compatibility with preferences saved before local library cleanup.
    var hiddenBroadcasts: [String: Set<String>]?
    // Optional additions migrate older files without dropping their current draft/journal.
    var savedLives: [String: [YouTubeSavedLive]]?
    var currentLiveIDs: [String: String]?
    var cachedBroadcasts: [String: [YouTubeBroadcast]]?
}

@MainActor final class YouTubeAPI {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    let transport: Transport
    init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StudioError.message("Resposta inválida do YouTube.") }
        return (data, http)
    }) { self.transport = transport }
    static func form(_ values: [String: String]) -> Data {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map { ($0.key.addingPercentEncoding(withAllowedCharacters: safe) ?? "") + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: safe) ?? "") }.joined(separator: "&").utf8)
    }
    func tokens(client: YouTubeOAuthClient, fields: [String: String], previousRefresh: String = "") async throws -> YouTubeTokens {
        var values = fields; values["client_id"] = client.clientID; values["client_secret"] = client.clientSecret
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = Self.form(values)
        let json = try await send(request)
        guard !json.string("access_token").isEmpty else { throw YouTubeAPIError(reason: "unauthorized") }
        return YouTubeTokens(access: json.string("access_token"), refresh: json.string("refresh_token", previousRefresh), expires: Date().addingTimeInterval(json.number("expires_in", 3600)))
    }
    func call(_ path: String, token: String, method: String = "GET", query: [String: String] = [:], body: [String: Any]? = nil, image: Data? = nil) async throws -> [String: Any] {
        var components = URLComponents(string: image == nil ? "https://www.googleapis.com/youtube/v3/\(path)" : "https://www.googleapis.com/upload/youtube/v3/\(path)")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let image { request.httpBody = image; request.setValue(image.starts(with: [0x89,0x50,0x4e,0x47]) ? "image/png" : "image/jpeg", forHTTPHeaderField: "Content-Type") }
        else if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await send(request)
    }
    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            // Never surface response bodies or URLs: they may contain credentials.
            let reason = json.object("error").array("errors").first?.string("reason") ?? (json["error"] as? String) ?? (response.statusCode == 401 ? "unauthorized" : "HTTP \(response.statusCode)")
            let known: Set<String> = ["quotaExceeded", "dailyLimitExceeded", "liveStreamingNotEnabled", "livePermissionBlocked", "insufficientLivePermissions", "invalid_grant", "unauthorized", "forbidden", "insufficientPermissions", "redundantTransition"]
            throw YouTubeAPIError(reason: known.contains(reason) ? reason : "HTTP \(response.statusCode)", statusCode: response.statusCode)
        }
        return json
    }
    func broadcasts(token: String) async throws -> [YouTubeBroadcast] {
        var result: [YouTubeBroadcast] = []; var page = ""; var seen = Set<String>()
        repeat {
            var query = ["part":"snippet,status,contentDetails", "broadcastStatus":"upcoming", "broadcastType":"all", "maxResults":"50"]
            if !page.isEmpty { query["pageToken"] = page }
            let json = try await call("liveBroadcasts", token: token, query: query)
            result += json.array("items").map(YouTubeBroadcast.init)
            page = json.string("nextPageToken")
            if !page.isEmpty && !seen.insert(page).inserted { throw StudioError.message("O YouTube repetiu a página de resultados. Atualize a lista novamente.") }
        } while !page.isEmpty
        return result
    }
    func broadcast(_ id: String, token: String) async throws -> YouTubeBroadcast {
        let json = try await call("liveBroadcasts", token: token, query: ["part":"snippet,status,contentDetails", "id":id])
        guard let item = json.array("items").first else { throw StudioError.message("A live não foi encontrada neste canal. Atualize a lista.") }
        return YouTubeBroadcast(item)
    }
    func createBroadcast(_ draft: YouTubeDraft, at date: Date, token: String) async throws -> YouTubeBroadcast {
        try draft.validate()
        let json = try await call("liveBroadcasts", token: token, method: "POST", query: ["part":"snippet,status,contentDetails"], body: [
            "snippet":["title":draft.title,"description":draft.description,"scheduledStartTime":ISO8601DateFormatter().string(from: date)],
            "status":["privacyStatus":draft.privacy,"selfDeclaredMadeForKids":draft.madeForKids],
            "contentDetails":["enableAutoStart":true,"enableAutoStop":false,"enableDvr":true,"latencyPreference":draft.latency,"monitorStream":["enableMonitorStream":false]]
        ])
        guard !json.string("id").isEmpty else { throw StudioError.message("O YouTube não devolveu o identificador da live. Confira o YouTube Studio antes de repetir.") }
        return YouTubeBroadcast(json)
    }
    func createStream(title: String, token: String) async throws -> String {
        let json = try await call("liveStreams", token: token, method: "POST", query: ["part":"snippet,cdn,contentDetails"], body: ["snippet":["title":title],"cdn":["frameRate":"variable","resolution":"variable","ingestionType":"rtmp"],"contentDetails":["isReusable":true]])
        guard !json.string("id").isEmpty else { throw StudioError.message("Stream sem identificador. Confira o YouTube Studio antes de repetir.") }; return json.string("id")
    }
    func bind(_ broadcast: String, stream: String, token: String) async throws {
        _ = try await call("liveBroadcasts/bind", token: token, method: "POST", query: ["id":broadcast,"streamId":stream,"part":"id,contentDetails"])
    }
    func updateVideo(_ id: String, draft: YouTubeDraft, token: String) async throws {
        // Read/merge snippet so unrelated video metadata is not discarded by videos.update.
        let old = try await call("videos", token: token, query: ["id":id,"part":"snippet"])
        var snippet = old.array("items").first?.object("snippet") ?? [:]
        for key in ["publishedAt","channelId","thumbnails","channelTitle","liveBroadcastContent","localized"] { snippet[key] = nil }
        snippet["title"] = draft.title; snippet["description"] = draft.description; snippet["categoryId"] = draft.category
        snippet["tags"] = draft.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        _ = try await call("videos", token: token, method: "PUT", query: ["part":"snippet"], body: ["id":id,"snippet":snippet])
    }
    func thumbnail(_ id: String, data: Data, token: String) async throws {
        guard data.count <= 2 * 1024 * 1024, data.starts(with: [0xff,0xd8]) || data.starts(with: [0x89,0x50,0x4e,0x47]) else { throw StudioError.message("Use uma capa JPEG ou PNG de até 2 MB.") }
        _ = try await call("thumbnails/set", token: token, method: "POST", query: ["videoId":id,"uploadType":"media"], image: data)
    }
    func stream(_ id: String, token: String) async throws -> (server: String, key: String, active: Bool) {
        let json = try await call("liveStreams", token: token, query: ["id":id,"part":"cdn,status"])
        guard let item = json.array("items").first else { throw StudioError.message("Stream do YouTube não encontrado.") }
        let info = item.object("cdn").object("ingestionInfo")
        let server = info.string("rtmpsIngestionAddress", info.string("ingestionAddress")); let key = info.string("streamName")
        guard let url = URLComponents(string: server), ["rtmp","rtmps"].contains(url.scheme ?? ""), url.host != nil, !key.isEmpty else { throw StudioError.message("O YouTube não forneceu uma conexão RTMP válida.") }
        return (server, key, item.object("status").string("streamStatus") == "active")
    }
    func transition(_ id: String, status: String, token: String) async throws {
        do { _ = try await call("liveBroadcasts/transition", token: token, method: "POST", query: ["id":id,"broadcastStatus":status,"part":"status"]) }
        catch let error as YouTubeAPIError where error.reason == "redundantTransition" { return }
    }
}
