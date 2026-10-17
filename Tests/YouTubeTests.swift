import Foundation
import CryptoKit

@MainActor func runYouTubeTests(directory: URL) async throws {
    func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); precondition(result) }
    try check(try YouTubeOAuth.callbackCode(target: "/?state=good&code=abc%2Bdef", state: "good") == "abc+def")
    try check(try YouTubeOAuth.callbackCode(target: "/?state=wrong&code=abc", state: "good") == nil)
    try check(try YouTubeOAuth.callbackCode(target: "/?state=good&code=a&code=b", state: "good") == nil)
    try check(try YouTubeOAuth.callbackCode(target: "/?state=good&state=good&code=a", state: "good") == nil)
    let random = try YouTubeOAuth.randomToken()
    try check(random.count == 43 && !random.contains("="))
    try check(String(decoding: YouTubeAPI.form(["key":"a+b&c=d"]), as: UTF8.self) == "key=a%2Bb%26c%3Dd")
    var draft = YouTubeDraft(); draft.title = "Contrato de teste"; draft.description = "Descrição"; draft.tags = "câmera, aula"; draft.privacy = "private"
    try draft.validate()
    let fixtureDirectory = directory.appendingPathComponent("youtube-fixture")
    try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    let prefix = "youtube-" + SHA256.hash(data: Data(fixtureDirectory.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    let client = YouTubeOAuthClient(clientID: "test.apps.googleusercontent.com", clientSecret: "fixture-client-secret")
    let account = YouTubeAccount(id: "test-channel", name: "Canal teste", tokenAccount: prefix + "-account-test-channel", clientID: client.clientID)
    var prefs = YouTubePreferences(); prefs.accounts = [account]; prefs.selectedAccount = account.id
    var state = YouTubeDraftState(); state.draft = draft; prefs.states[account.id] = state
    let file = fixtureDirectory.appendingPathComponent("youtube.json")
    try JSONEncoder().encode(prefs).write(to: file)
    var vaultData = [prefix + "-client":String(decoding: try JSONEncoder().encode(client), as: UTF8.self), account.tokenAccount:String(decoding: try JSONEncoder().encode(YouTubeTokens(access: "fixture-access", refresh: "fixture-refresh", expires: Date().addingTimeInterval(3600))), as: UTF8.self)]
    let vault = LiveKeyVault(read: { vaultData[$0] ?? "" }, save: { vaultData[$1] = $0 }, delete: { vaultData[$0] = nil })
    var requests: [URLRequest] = []; var bound = false; var creates = 0; var failStreamOnce = true; var ambiguous = false; var eventExists = false
    func event() -> [String:Any] { ["id":"video-1", "snippet":["title":draft.title,"description":draft.description,"scheduledStartTime":"2026-12-01T12:00:00Z"],"status":["privacyStatus":"private","lifeCycleStatus":"ready"],"contentDetails":["boundStreamId":bound ? "stream-1" : "","enableAutoStart":true]] }
    let api = YouTubeAPI { request in
        requests.append(request)
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
        let path = request.url!.path; let method = request.httpMethod!; var response: [String:Any] = [:]; var status = 200
        if path.hasSuffix("liveBroadcasts"), method == "POST" {
            creates += 1
            if ambiguous { throw URLError(.timedOut) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
            precondition(body.object("status").string("privacyStatus") == "private")
            precondition(body.object("contentDetails").flag("enableAutoStart"))
            eventExists = true; response = event()
        } else if path.hasSuffix("liveBroadcasts/bind") {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains { $0.name == "id" && $0.value == "video-1" }); precondition(query.contains { $0.name == "streamId" && $0.value == "stream-1" })
            bound = true; response = event()
        } else if path.hasSuffix("liveBroadcasts") { response = ["items":eventExists ? [event()] : []] }
        else if path.hasSuffix("liveStreams"), method == "POST" {
            if failStreamOnce { failStreamOnce = false; status = 403; response = ["error":["errors":[["reason":"quotaExceeded"]]]] }
            else { response = ["id":"stream-1"] }
        } else if path.hasSuffix("liveStreams") { response = ["items":[["cdn":["ingestionInfo":["rtmpsIngestionAddress":"rtmps://example.test/live","streamName":"fixture-stream-secret"]],"status":["streamStatus":"inactive"]]]] }
        else if path.hasSuffix("videos"), method == "GET" { response = ["items":[["snippet":["title":"Old", "categoryId":"22", "defaultLanguage":"pt-BR"]]]] }
        else if path.hasSuffix("videos"), method == "PUT" {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
            precondition(body.string("id") == "video-1" && body.object("snippet").string("defaultLanguage") == "pt-BR")
            precondition((body.object("snippet")["tags"] as? [String]) == ["câmera", "aula"])
        }
        return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    let model = YouTubeModel(directory: fixtureDirectory, api: api, vault: vault)
    func wait() async throws { for _ in 0..<100 { if !model.busy { return }; try await Task.sleep(for: .milliseconds(10)) }; preconditionFailure("YouTube fixture did not finish") }
    var dated = YouTubeBroadcast(event())
    dated.scheduledAt = "2026-10-17T02:30:46Z"
    let localLabel = dated.scheduleLabel(timeZone: TimeZone(identifier: "America/Sao_Paulo")!)
    try check(localLabel.contains("16") && localLabel.contains("23:30") && !localLabel.contains("T02"))
    let wholeDate = dated.scheduledDate
    dated.scheduledAt = "2026-10-17T02:30:46.000Z"
    try check(dated.scheduledDate == wholeDate)
    dated.scheduledAt = "invalid"; try check(dated.scheduleLabel() == "Data não informada")
    for status in ["live", "liveStarting", "complete", "revoked"] { dated.lifeCycle = status; try check(!dated.canTransmit) }
    dated.lifeCycle = "ready"; try check(dated.canTransmit)
    let studio = StudioModel(projectDirectory: fixtureDirectory)
    studio.youtube = model
    studio.liveSettings = LiveSettingsModel(model: studio, vault: vault)
    studio.liveSettings.edit({ $0.youtubeMode = true }, immediate: true)
    let beforeOpen = requests.count
    studio.beginLive(); studio.beginLive()
    try check(studio.showingLiveLibrary && studio.pendingLive == nil && !studio.preparingLive && studio.countdown.remaining == nil)
    try check(studio.liveOperationInProgress && requests.count == beforeOpen)
    studio.showingLiveLibrary = false; studio.liveLibraryDismissed()
    try check(studio.pendingLive == nil && !studio.preparingLive && requests.count == beforeOpen)
    model.schedule(); try await wait()
    try check(creates == 1 && model.state.createdBroadcast == "video-1" && !model.state.streamCreationUncertain)
    model.schedule(); try await wait()
    try check(creates == 1 && model.state.selectedBroadcast == "video-1" && bound)
    let refreshStart = requests.count
    model.refresh(); try await wait()
    try check(model.broadcasts.count == 1 && requests.dropFirst(refreshStart).allSatisfy { $0.httpMethod == "GET" })
    try check(model.selectBroadcast("video-1"))
    let beforeHide = requests.count
    try check(model.setBroadcastHidden("video-1", hidden: true))
    try check(model.visibleBroadcasts.isEmpty && model.state.selectedBroadcast == nil)
    try check(!model.selectBroadcast("video-1") && requests.count == beforeHide)
    let hiddenReload = YouTubeModel(directory: fixtureDirectory, api: api, vault: vault)
    try check(hiddenReload.hiddenBroadcastIDs == ["video-1"])
    hiddenReload.shutdown()
    model.refresh(); try await wait()
    try check(model.broadcasts.count == 1 && model.visibleBroadcasts.isEmpty)
    let beforeRestore = requests.count
    try check(model.setBroadcastHidden("video-1", hidden: false))
    try check(model.visibleBroadcasts.count == 1 && requests.count == beforeRestore)
    try check(model.selectBroadcast("video-1"))
    let preserved = try Data(contentsOf: file)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    try check(!model.setBroadcastHidden("video-1", hidden: true))
    try check(model.hiddenBroadcastIDs.isEmpty && model.state.selectedBroadcast == "video-1")
    try check(!model.selectBroadcast("") && model.state.selectedBroadcast == "video-1")
    try FileManager.default.removeItem(at: file); try preserved.write(to: file)
    let launch = try await model.confirmation()
    let prepared = try await model.prepare(launch)
    try check(prepared.broadcastID == "video-1" && prepared.key == "fixture-stream-secret")
    try check(creates == 1)
    let json = try String(contentsOf: file, encoding: .utf8)
    for secret in ["fixture-access","fixture-refresh","fixture-stream-secret","fixture-client-secret"] { try check(!json.contains(secret)) }
    let reloaded = YouTubeModel(directory: fixtureDirectory, api: api, vault: vault)
    try check(reloaded.state.selectedBroadcast == "video-1" && reloaded.broadcasts.first?.id == "video-1")
    try check(reloaded.state.preparationComplete == true)
    // Leaving a scheduled event retains its creation journal; selecting it again reuses the same video.
    try check(reloaded.newDraft())
    reloaded.editDraft { $0.title = "Outra live local" }; try check(reloaded.saveDraftForLater())
    let otherLocalID = reloaded.currentLiveID!
    try check(reloaded.selectBroadcast("video-1") && reloaded.state.createdBroadcast == "video-1")
    try check(reloaded.selectLocalLive(otherLocalID) && reloaded.state.draft.title == "Outra live local")
    // Hidden IDs are channel scoped, survive a new draft, and old files without the field load.
    var otherPrefs = try JSONDecoder().decode(YouTubePreferences.self, from: Data(contentsOf: file))
    otherPrefs.hiddenBroadcasts = ["other-channel": ["video-1"]]
    try JSONEncoder().encode(otherPrefs).write(to: file)
    let isolated = YouTubeModel(directory: fixtureDirectory, api: api, vault: vault)
    try check(isolated.hiddenBroadcastIDs.isEmpty)
    try check(isolated.setBroadcastHidden("video-1", hidden: true))
    isolated.newDraft()
    try check(isolated.hiddenBroadcastIDs == ["video-1"] && isolated.preferences.hiddenBroadcasts?["other-channel"] == ["video-1"])
    isolated.shutdown()
    model.newDraft(); model.editDraft { $0 = draft }; ambiguous = true
    model.schedule(); try await wait()
    try check(creates == 2 && model.state.creationUncertain)
    model.schedule(); try await wait()
    try check(creates == 2) // Lost response never causes an automatic duplicate insert.
    let errors = YouTubeAPI { request in (Data("{\"error\":{\"errors\":[{\"reason\":\"fixture-secret\"}]}}".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!) }
    do { _ = try await errors.call("videos", token: "fixture"); preconditionFailure("Expected failure") }
    catch let error as YouTubeAPIError { try check(!error.localizedDescription.contains("fixture-secret") && !error.definitelyRejected) }
    var thumbnailSent = false
    let thumbnailAPI = YouTubeAPI { request in
        precondition(request.url!.path == "/upload/youtube/v3/thumbnails/set" && request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
        precondition(request.httpBody == Data([0x89,0x50,0x4e,0x47]))
        thumbnailSent = true
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    try await thumbnailAPI.thumbnail("video-1", data: Data([0x89,0x50,0x4e,0x47]), token: "fixture")
    try check(thumbnailSent)
    do { try await thumbnailAPI.thumbnail("video-1", data: Data(repeating: 0, count: 2 * 1024 * 1024 + 1), token: "fixture"); preconditionFailure("Expected size validation") } catch is StudioError { }
    // Multiple local preparations retain distinct metadata, survive restarts and never POST on save/select.
    let localDirectory = directory.appendingPathComponent("youtube-multiple-live-fixture")
    try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
    var legacy = YouTubePreferences(); legacy.accounts = [account]; legacy.selectedAccount = account.id
    var legacyState = YouTubeDraftState(); legacyState.draft = draft
    legacy.states[account.id] = legacyState
    let localFile = localDirectory.appendingPathComponent("youtube.json")
    try JSONEncoder().encode(legacy).write(to: localFile)
    let local = YouTubeModel(directory: localDirectory, api: api, vault: vault)
    let requestCount = requests.count
    try check(local.localLives.count == 1 && local.state.draft == draft)
    let firstID = local.currentLiveID!
    try check(local.saveDraftForLater())
    try check(local.newDraft() && local.state.draft.title.isEmpty)
    local.editDraft { $0.title = "Conversa de amanhã"; $0.description = "Outra descrição"; $0.thumbnailFile = "segunda-capa.png"; $0.privacy = "public" }
    try check(local.saveDraftForLater())
    let secondID = local.currentLiveID!
    try check(firstID != secondID && local.localLives.count == 2)
    try check(local.selectLocalLive(firstID) && local.state.draft == draft)
    local.editDraft { $0.description = "Primeira preparação editada" }; local.flush()
    try check(local.selectLocalLive(secondID) && local.state.draft.title == "Conversa de amanhã" && local.state.draft.thumbnailFile == "segunda-capa.png")
    let localReload = YouTubeModel(directory: localDirectory, api: api, vault: vault)
    try check(localReload.localLives.count == 2 && localReload.currentLiveID == secondID)
    try check(localReload.selectLocalLive(firstID) && localReload.state.draft.description == "Primeira preparação editada")
    let localLaunch = try await local.confirmation()
    local.editDraft { $0.description = "Changed after confirmation" }
    do { _ = try await local.prepare(localLaunch); preconditionFailure("Changed draft must require new confirmation") } catch is StudioError { }
    try check(requests.count == requestCount)
    // A disk error must not switch away from the user's current preparation.
    local.flush()
    let localBytes = try Data(contentsOf: localFile)
    try FileManager.default.removeItem(at: localFile)
    try FileManager.default.createDirectory(at: localFile, withIntermediateDirectories: false)
    let beforeFailure = local.currentLiveID
    try check(!local.newDraft() && local.currentLiveID == beforeFailure)
    try check(!local.selectLocalLive(firstID) && local.currentLiveID == beforeFailure)
    try FileManager.default.removeItem(at: localFile); try localBytes.write(to: localFile)
    // Separate channels cannot see or select each other's local preparations.
    var multiple = try JSONDecoder().decode(YouTubePreferences.self, from: localBytes)
    let otherAccount = YouTubeAccount(id: "other", name: "Other", tokenAccount: "fixture-other", clientID: client.clientID)
    multiple.accounts.append(otherAccount); multiple.selectedAccount = otherAccount.id
    try JSONEncoder().encode(multiple).write(to: localFile)
    let other = YouTubeModel(directory: localDirectory, api: api, vault: vault)
    try check(other.localLives.count == 1 && other.state.draft.title.isEmpty && !other.selectLocalLive(firstID))
    other.shutdown(); local.shutdown(); localReload.shutdown()
    legacy.states[account.id]?.selectedBroadcast = "legacy-remote"
    try JSONEncoder().encode(legacy).write(to: localFile)
    let migratedSelection = YouTubeModel(directory: localDirectory, api: api, vault: vault)
    try check(migratedSelection.state.selectedBroadcast == "legacy-remote")
    try check(migratedSelection.localLives.count == 1 && migratedSelection.localLives[0].state.draft == draft)
    migratedSelection.shutdown()
    // Local deletion stays deleted across save/restart, rolls back on disk errors and never calls the API.
    try JSONEncoder().encode(legacy).write(to: localFile)
    let cleanup = YouTubeModel(directory: localDirectory, api: api, vault: vault)
    try check(cleanup.newDraft())
    cleanup.editDraft { $0.title = "Excluir somente local" }; cleanup.flush()
    let cleanupID = cleanup.currentLiveID!
    let requestsBeforeRemoval = requests.count
    let cleanupBytes = try Data(contentsOf: localFile)
    try FileManager.default.removeItem(at: localFile)
    try FileManager.default.createDirectory(at: localFile, withIntermediateDirectories: false)
    try check(!cleanup.removeLocalLive(cleanupID) && cleanup.currentLiveID == cleanupID)
    try check(cleanup.localLives.contains { $0.id == cleanupID })
    try FileManager.default.removeItem(at: localFile); try cleanupBytes.write(to: localFile)
    try check(cleanup.removeLocalLive(cleanupID))
    for item in cleanup.localLives { try check(cleanup.removeLocalLive(item.id)) }
    try check(cleanup.localLives.isEmpty && cleanup.currentLiveID == nil)
    try cleanup.prepareForApplicationUpdate()
    let cleanReload = YouTubeModel(directory: localDirectory, api: api, vault: vault)
    try check(cleanReload.localLives.isEmpty && cleanReload.currentLiveID == nil)
    try check(!cleanReload.removeLocalLive(firstID))
    cleanReload.editDraft { $0.title = "Nova após limpeza" }; cleanReload.flush()
    try check(cleanReload.localLives.count == 1 && cleanReload.currentLiveID != cleanupID)
    try check(requests.count == requestsBeforeRemoval)
    cleanReload.shutdown(); cleanup.shutdown()
    let shortcut = StudioModel(projectDirectory: directory.appendingPathComponent("shortcut-fixture"))
    shortcut.youtube = cleanReload
    shortcut.liveSettings = LiveSettingsModel(model: shortcut, vault: vault)
    shortcut.showingOutput = true
    shortcut.transmitSelectedFromSettings()
    try check(!shortcut.showingOutput && shortcut.liveSettings.document.youtubeMode == true)
    try check(shortcut.pendingLive == nil && shortcut.countdown.remaining == nil)
    // Routing only closes settings; confirmation waits for sheet dismissal, no output/API side effect.
    try check(requests.count == requestsBeforeRemoval)
    print("PASS: local deletion persistence, empty library, disk rollback, fresh draft after deletion and zero remote requests")
    print("PASS: legacy draft migration, multiple saved preparations, independent metadata/covers, restart persistence, channel isolation, no API mutation on save/select, disk failure preservation and confirmation snapshot")
    // Share the actual launched video, never another selected draft or a stream key.
    let launched = LiveLaunch(channel: "QA", title: "Live em andamento", thumbnailURL: nil, server: "rtmps://example.invalid", key: "test-key-not-for-sharing", youtubeAccount: account.id, broadcastID: "video-test", privacy: "private")
    try check(YouTubeDraft().latency == "ultraLow")
    var interactive = launched; interactive.latency = "ultraLow"
    var output = LiveVideoSettings(); output.width = 3840; output.height = 2160
    do { try interactive.validateVideoLatency(output); preconditionFailure("4K must require Normal latency") } catch is StudioError { }
    interactive.latency = "normal"; try interactive.validateVideoLatency(output)
    output.width = 2560; output.height = 1440; interactive.latency = "ultraLow"; try interactive.validateVideoLatency(output)
    model.watchStarted(launched, isSending: { false })
    try check(model.liveShare?.url.absoluteString == "https://www.youtube.com/watch?v=video-test")
    try check(model.liveShare?.title == launched.title && model.liveShare?.privacy == "private")
    let rtmp = LiveLaunch(channel: "RTMP", title: "RTMP", thumbnailURL: nil, server: "rtmps://example.invalid", key: "test-key-not-for-sharing")
    try check(LiveShareInfo(rtmp) == nil)
    var unprepared = launched; unprepared.broadcastID = nil
    try check(LiveShareInfo(unprepared) == nil)
    model.endActive(); try check(model.liveShare == nil)
    print("PASS: live share uses launched broadcast, keeps privacy, excludes keys and unprepared/RTMP destinations, clears on stop")
    model.shutdown(); reloaded.shutdown()
    print("PASS: local hide/restore without API requests, persistence across refresh/reload/new draft, channel isolation, selection clearing and save failure rollback")
    print("PASS: live library routing/cancel without output or API mutations, read-only refresh, selected-video persistence rollback, local schedule date including fractional ISO and non-startable states")
    print("PASS: YouTube OAuth state/duplicate rejection, PKCE entropy/form encoding, schedule-bind-retry preserving video ID, metadata merge, secret-free persistence, lost-response duplicate prevention, sanitized errors (offline transport only)")
}
