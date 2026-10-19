import AppKit
let appVersion = "0.1.9 QA"
@main struct GuestHarness {
    @MainActor static func main() {
        let app=CommandLine.arguments[1], root=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let studio=StudioModel(projectDirectory:root.appendingPathComponent("project"))
        studio.engine=dante_engine_create_with_config(app,640,360,30,root.appendingPathComponent("engine").path)
        guard studio.engine != nil else {fatalError("Engine startup failed")}
        studio.refresh()
        let guests = CommandLine.arguments.contains("--blocked-stun")
            ? GuestModel(studio:studio, discoveryServers:["stun:192.0.2.1:3478"])
            : studio.guests
        Task { @MainActor in
            var echoFixture: UnsafeMutableRawPointer?
            do {
                let resources = ProcessInfo.processInfo.environment["DANTE_GUEST_WEB"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath:app).appendingPathComponent("Contents/Resources/GuestWeb")
                let vpsIndex=CommandLine.arguments.firstIndex(of:"--vps-profile")
                if let vpsIndex,CommandLine.arguments.indices.contains(vpsIndex+1) {
                    try guests.importVPSProfile(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[vpsIndex+1])))
                    await guests.testVPS()
                    guard guests.vpsStatus?.hasPrefix("Servidor conectado") == true else { throw StudioError.message("VPS de teste indisponível.") }
                } else { try await guests.startServer(resources: resources) }
                let publicTest=CommandLine.arguments.contains("--public") || vpsIndex != nil
                if publicTest {
                    for _ in 0..<2 {
                        guests.createInvite()
                        while guests.busy { try await Task.sleep(for:.milliseconds(200)) }
                    }
                    guard guests.invites.count==2,guests.publicURL != nil else { throw StudioError.message(guests.message ?? "Public tunnel failed") }
                } else { _=try guests.makeInvite();_=try guests.makeInvite() }
                let a=guests.invites[0],b=guests.invites[1]
                let data=try JSONSerialization.data(withJSONObject:["base":(publicTest ? guests.publicURL! : guests.localURL!).absoluteString,"tokens":[a.token,b.token]])
                let config=root.appendingPathComponent("connection.json");try data.write(to:config,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:config.path)
                print("READY: isolated synthetic guest test");fflush(stdout)
                while !FileManager.default.fileExists(atPath:root.appendingPathComponent("stop").path) {
                    studio.refresh()
                    let echoRequest=root.appendingPathComponent("echo-start")
                    if FileManager.default.fileExists(atPath:echoRequest.path),echoFixture == nil,let guest=guests.invites.first,guest.admitted {
                        echoFixture=guest_echo_fixture_start(guest.microphone,studio.sceneName)
                        precondition(echoFixture != nil)
                        try FileManager.default.removeItem(at:echoRequest)
                        try Data("ready".utf8).write(to:root.appendingPathComponent("echo-ready"))
                    }
                    let echoStop=root.appendingPathComponent("echo-stop")
                    if FileManager.default.fileExists(atPath:echoStop.path) {
                        guest_echo_fixture_stop(echoFixture);echoFixture=nil
                        try FileManager.default.removeItem(at:echoStop)
                        try Data("stopped".utf8).write(to:root.appendingPathComponent("echo-stopped"))
                        studio.refresh()
                    }
                    for guest in guests.invites where guest.peer != nil && !guest.admitted {
                        guests.admit(guest.id);guests.insertScreen(guest.id)
                        _=studio.command("audio.set",["name":guest.microphone,"monitoring":0],undo:false)
                    }
                    if let raw=try? Data(contentsOf:root.appendingPathComponent("revoke")),let index=Int(String(decoding:raw,as:UTF8.self)),guests.invites.indices.contains(index) {
                        guests.revoke(guests.invites[index].id);try? FileManager.default.removeItem(at:root.appendingPathComponent("revoke"))
                    }
                    let panelRequest=root.appendingPathComponent("panel-checks")
                    if FileManager.default.fileExists(atPath:panelRequest.path),guests === studio.guests,let guest=guests.invites.first,guests.invites.count==2 {
                        try FileManager.default.removeItem(at:panelRequest)
                        let filterName = "Dante • Redução de ruído"
                        let microphoneBefore = guests.item(guest.microphone, in: studio.sceneName)!
                        let properties = jsonObject(copied(dante_engine_type_properties(studio.engine, "noise_suppress_filter_v2")))
                        let methods = properties.array("properties").first { $0.string("name") == "method" }?.array("items").map { $0.string("value") } ?? []
                        precondition(methods.contains("rnnoise") && methods.contains("speex"))
                        precondition(studio.command("filter.add", ["name": guest.microphone, "type": "noise_suppress_filter_v2", "filter": filterName, "settings": ["method": "rnnoise"]], undo: false))
                        for enabled in [false, true] {
                            precondition(studio.command("filter.update", ["name": guest.microphone, "filter": filterName, "enabled": enabled, "settings": ["method": "speex", "suppress_level": -24]], undo: false))
                            let settings = jsonObject(copied(dante_engine_filter_properties(studio.engine, guest.microphone, filterName))).object("settings")
                            precondition(settings.string("method") == "speex" && settings.number("suppress_level") == -24)
                            let microphone = guests.item(guest.microphone, in: studio.sceneName)!
                            precondition(microphone.array("filters").first { $0.string("name") == filterName }?.flag("enabled") == enabled)
                            precondition(microphone.number("tracks") == microphoneBefore.number("tracks") && microphone.flag("muted") == microphoneBefore.flag("muted"))
                        }
                        precondition(studio.command("filter.remove", ["name": guest.microphone, "filter": filterName], undo: false))
                        precondition(guests.item(guest.microphone, in: studio.sceneName)!.array("filters").count == microphoneBefore.array("filters").count)
                        print("PASS: optional RNNoise/Speex, strength, bypass and routing preservation")
                        let original=studio.sceneName
                        precondition(studio.listedSources.isEmpty)
                        precondition(guests.displayName(for:guest.camera).hasPrefix(guest.firstName))
                        precondition(guests.participantSlot(for:guest.camera) != guests.participantSlot(for:guests.invites[1].camera))
                        guests.toggleMicrophone(guest.id);guests.toggleVideo(guest.id,screen:false)
                        precondition(studio.command("scene.create",["name":"Participantes QA"]))
                        guests.admit(guest.id,to:"Participantes QA")
                        precondition(guests.scene(for:guest)=="Participantes QA")
                        precondition(guests.item(guest.microphone,in:"Participantes QA")!.flag("muted"))
                        precondition(!guests.item(guest.camera,in:"Participantes QA")!.flag("visible"))
                        precondition(studio.command("scene.rename",["scene":"Participantes QA","name":"Renomeada QA"]))
                        precondition(guests.scene(for:guest)=="Renomeada QA")
                        guests.admit(guest.id,to:original);studio.selectScene(original)
                        guests.toggleMicrophone(guest.id);guests.toggleVideo(guest.id,screen:false)
                        for name in ["Layer QA 1","Layer QA 2"] { precondition(studio.command("source.add",["scene":original,"type":"color_source_v3","name":name,"settings":["width":10,"height":10]])) }
                        let hiddenBefore=studio.items.enumerated().filter {guests.managedSourceNames.contains($0.element.string("name"))}.map {[$0.offset,Int($0.element.sceneItemID)]}
                        let ids=studio.listedSources.reversed().map(\.sceneItemID)
                        precondition(ids.count==2);studio.moveSources(in:original,ids:ids,from:[0],to:2)
                        precondition(studio.listedSources.reversed().map(\.sceneItemID)==Array(ids.reversed()))
                        let hiddenAfter=studio.items.enumerated().filter {guests.managedSourceNames.contains($0.element.string("name"))}.map {[$0.offset,Int($0.element.sceneItemID)]}
                        precondition(hiddenBefore==hiddenAfter)
                        for component in studio.listedSources { _=studio.command("source.remove",["scene":original,"id":component.sceneItemID]) }
                        guests.select(guest.camera,guest:guest);precondition(studio.selectedName==guest.camera)
                        try Data("passed".utf8).write(to:root.appendingPathComponent("panel-checks-passed"))
                    }
                    let state=studio.state;let levels=jsonObject(copied(dante_engine_audio_levels(studio.engine)))
                    let snapshot:[String:Any]=["state":state,"levels":levels,"guests":guests.invites.map{["name":$0.name,"status":$0.status,"media":$0.peer?.mediaDiagnostics ?? [:]]}]
                    try JSONSerialization.data(withJSONObject:snapshot).write(to:root.appendingPathComponent("state.json"),options:.atomic)
                    try await Task.sleep(for:.milliseconds(200))
                }
                guest_echo_fixture_stop(echoFixture);guests.stop();studio.shutdown();try? FileManager.default.removeItem(at:config);print("PASS: guest engine shutdown");exit(0)
            } catch {print("FAIL: guest harness \(error)");guest_echo_fixture_stop(echoFixture);guests.stop();studio.shutdown();exit(1)}
        }
        NSApp.run()
    }
}
