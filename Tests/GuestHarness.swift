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
        Task { @MainActor in
            do {
                try await studio.guests.startServer(resources:URL(fileURLWithPath:app).appendingPathComponent("Contents/Resources/GuestWeb"))
                let publicTest=CommandLine.arguments.contains("--public")
                if publicTest {
                    for _ in 0..<2 {
                        studio.guests.createInvite()
                        while studio.guests.busy { try await Task.sleep(for:.milliseconds(200)) }
                    }
                    guard studio.guests.invites.count==2,studio.guests.publicURL != nil else { throw StudioError.message(studio.guests.message ?? "Public tunnel failed") }
                } else { _=try studio.guests.makeInvite();_=try studio.guests.makeInvite() }
                let a=studio.guests.invites[0],b=studio.guests.invites[1]
                let data=try JSONSerialization.data(withJSONObject:["base":(publicTest ? studio.guests.publicURL! : studio.guests.localURL!).absoluteString,"tokens":[a.token,b.token]])
                let config=root.appendingPathComponent("connection.json");try data.write(to:config,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:config.path)
                print("READY: isolated synthetic guest test");fflush(stdout)
                while !FileManager.default.fileExists(atPath:root.appendingPathComponent("stop").path) {
                    studio.refresh()
                    for guest in studio.guests.invites where guest.peer != nil && !guest.admitted {
                        studio.guests.admit(guest.id);studio.guests.insertScreen(guest.id)
                        _=studio.command("audio.set",["name":guest.microphone,"monitoring":0],undo:false)
                    }
                    if let raw=try? Data(contentsOf:root.appendingPathComponent("revoke")),let index=Int(String(decoding:raw,as:UTF8.self)),studio.guests.invites.indices.contains(index) {
                        studio.guests.revoke(studio.guests.invites[index].id);try? FileManager.default.removeItem(at:root.appendingPathComponent("revoke"))
                    }
                    let state=studio.state;let levels=jsonObject(copied(dante_engine_audio_levels(studio.engine)))
                    let snapshot:[String:Any]=["state":state,"levels":levels,"guests":studio.guests.invites.map{["name":$0.name,"status":$0.status,"media":$0.peer?.mediaDiagnostics ?? [:]]}]
                    try JSONSerialization.data(withJSONObject:snapshot).write(to:root.appendingPathComponent("state.json"),options:.atomic)
                    try await Task.sleep(for:.milliseconds(200))
                }
                studio.guests.stop();studio.shutdown();try? FileManager.default.removeItem(at:config);print("PASS: guest engine shutdown");exit(0)
            } catch {print("FAIL: guest harness \(error)");studio.guests.stop();studio.shutdown();exit(1)}
        }
        NSApp.run()
    }
}
