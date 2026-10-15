import Foundation

@MainActor func runLiveSettingsTests(model: StudioModel, directory: URL) async throws {
    func verify(_ condition: @autoclosure () throws -> Bool) throws { let result = try condition(); precondition(result) }
    let savedEngine = copied(dante_engine_save(model.engine))
    model.catalog = jsonObject(copied(dante_engine_catalog(model.engine)))
    model.outputConfiguration.encoder = model.catalog.string("defaultEncoder")
    let store = LiveSettingsStore(url: directory.appendingPathComponent("settings-test.json"))
    var secrets: [String: String] = [:]
    let vault = LiveKeyVault(read: { secrets[$0] ?? "" }, save: { secrets[$1] = $0 }, delete: { secrets[$0] = nil })
    let settings = LiveSettingsModel(model: model, store: store, vault: vault)
    settings.edit({ $0.server = "rtmp://127.0.0.1:1935/test" }, immediate: true)
    settings.editKey("fixture-private-key")
    settings.editVideo(\.bitrate, 8500); settings.editVideo(\.bitrate, 9200)
    settings.flush()
    try verify(try store.load()!.video.bitrate == 9200)
    try verify(secrets[settings.document.keyAccount] == "fixture-private-key")
    let serialized = try String(contentsOf: store.url, encoding: .utf8)
    try verify(!serialized.contains("fixture-private-key"))
    let reopened = LiveSettingsModel(model: model, store: store, vault: vault)
    reopened.loadKey()
    try verify(reopened.document.server == "rtmp://127.0.0.1:1935/test" && reopened.key == "fixture-private-key")
    try verify(reopened.video.bitrate == 9200)
    try verify(reopened.savePreset(name: "Minha live"))
    let custom = reopened.document.presets[0]
    try verify(!reopened.savePreset(name: "MINHA LIVE"))
    let channelStore = LiveSettingsStore(url: directory.appendingPathComponent("channels.json"))
    var channelSecrets: [String:String] = [:]; var rejectedAccount = ""
    let channelVault = LiveKeyVault(read: { if $0 == rejectedAccount { throw StudioError.message("Denied fixture") }; return channelSecrets[$0] ?? "" }, save: { channelSecrets[$1] = $0 }, delete: { channelSecrets[$0] = nil })
    let channels = LiveSettingsModel(model: model, store: channelStore, vault: channelVault)
    channels.edit({ $0.server = "rtmps://example.test/live" }, immediate: true); channels.editKey("key-one"); channels.flush()
    try verify(channels.saveChannel(name: "Canal um")); let one = channels.selectedChannel!
    channels.selectChannel(nil)
    channels.edit({ $0.server = "rtmps://example.test/live" }, immediate: true); channels.editKey("key-two"); channels.flush()
    try verify(channels.saveChannel(name: "Canal dois")); let two = channels.selectedChannel!
    try verify(one.keyAccount != two.keyAccount)
    channels.selectChannel(one.id); try verify(channels.key == "key-one")
    channels.editKey("key-one-updated"); channels.flush()
    rejectedAccount = two.keyAccount; channels.selectChannel(two.id)
    try verify(channels.document.selectedChannelID == one.id && channels.key == "key-one-updated")
    rejectedAccount = ""; channels.selectChannel(two.id); try verify(channels.key == "key-two")
    channels.renameChannel(two.id, name: "Segundo canal")
    let channelReload = LiveSettingsModel(model: model, store: channelStore, vault: channelVault); channelReload.loadKey()
    try verify(channelReload.selectedChannel?.name == "Segundo canal" && channelReload.key == "key-two")
    channels.deleteChannel(one.id); try verify(channelSecrets[one.keyAccount] == nil && channelSecrets[two.keyAccount] == "key-two")
    let channelJSON = try String(contentsOf: channelStore.url, encoding: .utf8)
    try verify(!channelJSON.contains("key-one") && !channelJSON.contains("key-two"))
    var legacy = jsonObject(channelJSON); legacy["channels"] = nil; legacy["selectedChannelID"] = nil; legacy["youtubeMode"] = nil
    let migrated = try JSONDecoder().decode(LiveSettingsDocument.self, from: Data(jsonString(legacy).utf8))
    try verify(migrated.channels == nil && migrated.youtubeMode == nil)
    try verify(channels.suggestedPresetName == "Preset personalizado 1")
    try verify(channels.savePreset(name: channels.suggestedPresetName)); try verify(channels.suggestedPresetName == "Preset personalizado 2")
    channels.renamePreset(channels.selectedPreset!.id, name: "Minha qualidade")
    try verify(channels.selectedPreset?.name == "Minha qualidade")
    print("PASS: named channels on same server keep independent keys, denied key access preserves selection, rename/reopen/delete isolation, no plaintext keys, legacy migration, automatic preset names")
    // Simulate an active transmission: configuration must persist without resetting video.
    let width = model.canvasWidth
    model.state["streaming"] = true
    reopened.choose(LiveQuality.qhd.rawValue)
    try verify(model.canvasWidth == width && reopened.video.width == 2560)
    try verify(try store.load()!.video.width == 2560)
    reopened.choose(custom.id.uuidString)
    try verify(reopened.video == custom.video)
    reopened.setUpload(2, immediate: true)
    try verify(reopened.video == custom.video) // custom bitrate is not overwritten by a speed test.
    reopened.editVideo(\.bitrate, 9300); reopened.flush()
    try verify(reopened.document.selection == "custom" && reopened.document.presets[0].video == custom.video)
    reopened.rememberKey(false)
    try verify(secrets.isEmpty)
    let noKey = LiveSettingsModel(model: model, store: store, vault: vault); noKey.loadKey()
    try verify(noKey.key.isEmpty)
    let beforeInvalid = try Data(contentsOf: store.url)
    reopened.editVideo(\.width, 13); reopened.flush()
    try verify(reopened.problem != nil && (try Data(contentsOf: store.url)) == beforeInvalid)
    reopened.choose(custom.id.uuidString)
    reopened.removePreset(custom.id)
    try verify(reopened.document.presets.isEmpty)
    let badURL = directory.appendingPathComponent("broken-settings.json")
    try Data("broken".utf8).write(to: badURL)
    let broken = LiveSettingsModel(model: model, store: LiveSettingsStore(url: badURL), vault: vault)
    broken.editVideo(\.bitrate, 20000, immediate: true)
    try verify(try String(contentsOf: badURL, encoding: .utf8) == "broken")
    model.state["streaming"] = false
    model.refresh()
    // Apply desired video on the real engine, still without starting a network output.
    reopened.editKey("fixture-private-key"); reopened.flush()
    try verify(reopened.prepareStream())
    try verify(Int(model.canvasWidth) == reopened.video.width)
    try verify(!model.command("recording.start", ["path":"/tmp/not-created.mkv"]))
    try verify(!model.command("replay.start"))
    try verify(dante_engine_load(model.engine, savedEngine)); model.refresh()
    print("PASS: autosave/reopen, isolated vault, no plaintext key, preset creation/selection/duplicate rejection/deletion, custom preservation, active-output deferral, invalid/corrupt file preservation, real video apply, recording/replay rejected")

    // Exercise the real libobs audio callback with synthetic PCM, not a physical microphone.
    var wav = Data()
    func ascii(_ value: String) { wav.append(contentsOf: value.utf8) }
    func le<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
    ascii("RIFF"); le(UInt32(36 + 192000)); ascii("WAVEfmt "); le(UInt32(16)); le(UInt16(1)); le(UInt16(2)); le(UInt32(48000)); le(UInt32(192000)); le(UInt16(4)); le(UInt16(16)); ascii("data"); le(UInt32(192000))
    for frame in 0..<48000 { let sample = Int16(sin(Double(frame) * 2 * Double.pi * 440 / 48000) * 10000); le(sample); le(sample) }
    let tone = directory.appendingPathComponent("signal.wav"); try wav.write(to: tone)
    try verify(model.command("source.add", ["type":"ffmpeg_source", "name":"Signal fixture", "settings":["local_file":tone.path,"is_local_file":true,"looping":true]]))
    try verify(model.command("audio.set", ["name":"Signal fixture", "monitoring":0]))
    var observed = false
    for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(100)); model.refresh()
        let source = model.items.first { $0.string("name") == "Signal fixture" }!
        if source.number("signalAge", -1) >= 0 && source.number("signalAge") < 1 { observed = true; break }
    }
    try verify(observed)
    try verify(model.command("media.stop", ["name":"Signal fixture"]))
    try await Task.sleep(for: .milliseconds(1300)); model.refresh()
    try verify(model.items.first { $0.string("name") == "Signal fixture" }!.number("signalAge") > 0.5)
    try verify(dante_engine_load(model.engine, savedEngine)); model.refresh()
    print("PASS: real libobs synthetic PCM updates signal timestamp; stopped media ages out without stale-level false recovery")

    var watch = MicrophoneSilenceWatch()
    func mic(_ age: Double?, enabled: Bool = true) -> [MicrophoneSample] { [MicrophoneSample(id: "mic", name: "Microfone", enabled: enabled, signalAge: age)] }
    try verify(watch.update(mic(nil), live: true, now: 0).isEmpty)
    try verify(watch.update(mic(nil), live: true, now: 29.9).isEmpty)
    try verify(watch.update(mic(nil), live: true, now: 30) == ["Microfone"])
    try verify(watch.update(mic(nil), live: true, now: 90) == ["Microfone"])
    try verify(watch.update(mic(0), live: true, now: 90.1).isEmpty)
    try verify(watch.update(mic(29.9), live: true, now: 120).isEmpty)
    try verify(watch.update(mic(30), live: true, now: 120.1) == ["Microfone"])
    try verify(watch.update(mic(nil, enabled: false), live: true, now: 121).isEmpty)
    try verify(watch.update(mic(nil), live: true, now: 122).isEmpty)
    try verify(watch.update(mic(nil), live: false, now: 200).isEmpty)
    try verify(watch.update(mic(nil), live: true, now: 201).isEmpty)
    try verify(watch.update([], live: true, now: 250).isEmpty)
    print("PASS: microphone 30-second threshold, persistent silence, recovery, renewed silence, intentional mute/inactive reset, removed source and live lifecycle")

    try await runYouTubeTests(directory: directory)
    try await runUpdateTests(model: model)

    let countdown = LiveCountdown(); var starts = 0
    countdown.start(interval: .milliseconds(20)) { starts += 1 }
    try verify(countdown.remaining == 3)
    countdown.start(interval: .milliseconds(1)) { starts += 100 }
    countdown.cancel()
    try await Task.sleep(for: .milliseconds(90))
    try verify(starts == 0 && countdown.remaining == nil)
    countdown.start(interval: .milliseconds(20)) { starts += 1 }
    try await Task.sleep(for: .milliseconds(100))
    try verify(starts == 1 && countdown.remaining == nil)
    print("PASS: countdown duplicate start rejection, cancellation and exactly one start; no network output")
}
