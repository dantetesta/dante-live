import AppKit
import SwiftUI
import Darwin

var appVersion: String { "test" }

@main enum EditorInteractionTests {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        // SwiftUI can finish scheduled rendering after a cacheDisplay call. Keep
        // preview windows alive through the test process to avoid tearing down
        // their view graphs while those jobs still reference them.
        var thumbnailWindows: [NSWindow] = []
        for style in 0..<10 {
            let thumbnail = NSHostingView(rootView: VisualizerStyleThumbnail(
                style: style, primary: 0x48D8E8, secondary: 0x986BFF
            ).frame(width: 144, height: 54))
            thumbnail.frame = NSRect(x: 0, y: 0, width: 144, height: 54)
            let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 144, height: 54),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = thumbnail
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(30))
            let bitmap = thumbnail.bitmapImageRepForCachingDisplay(in: thumbnail.bounds)!
            thumbnail.cacheDisplay(in: thumbnail.bounds, to: bitmap)
            precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
            window.orderOut(nil)
            thumbnailWindows.append(window)
        }
        print("PASS: all ten audio visualizer thumbnails render without crashing")
        fflush(stdout)
        let queue = PropertyEditQueue()
        var edits: [String] = []
        queue.submit(immediate: false) { edits.append("old") }
        queue.submit(immediate: false) { edits.append("latest") }
        // Wait for the asynchronous debounce result with a bounded deadline. A fixed
        // 400 ms sleep races the task's initial scheduling under build load.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while edits.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        precondition(edits == ["latest"], "debounced edit must execute once")
        queue.submit(immediate: false) { edits.append("canceled") }; queue.cancel()
        try await Task.sleep(for: .milliseconds(350))
        precondition(edits == ["latest"])
        queue.submit(immediate: false) { edits.append("source-A") }; queue.flush()
        queue.submit(immediate: true) { edits.append("source-B") }
        try await Task.sleep(for: .milliseconds(350))
        precondition(edits == ["latest", "source-A", "source-B"])
        print("PASS: coalesced typing, immediate selections, cancellation and flush exactly once")

        let ids: [Int64] = [3,2,1]
        precondition(SourceOrder.moving(ids, from: [0], to: 3) == [2,1,3])
        precondition(SourceOrder.moving(ids, from: [2], to: 0) == [1,3,2])
        precondition(SourceOrder.moving(ids, from: [0,1], to: 3) == [1,3,2])
        precondition(SourceOrder.moving(ids, from: [1], to: 1) == ids)
        precondition(SourceOrder.moving(ids, from: [4], to: 0) == nil)
        precondition(SourceOrder.moving(ids, from: [0], to: -1) == nil)
        precondition(SourceOrder.moving([1,1], from: [0], to: 1) == nil)

        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("dante-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StudioModel(projectDirectory: directory)
        guard let engine = dante_engine_create_with_config(CommandLine.arguments[1], 640, 360, 10, directory.path) else { fatalError(copied(dante_engine_last_error(nil))) }
        model.engine = engine; model.restoreProfile(); model.refresh()
        for name in ["A", "B", "C"] {
            precondition(model.command("source.add", ["scene":model.sceneName,"type":"color_source_v3","name":name,"settings":["width":640,"height":360,"color":0xFF112233]]))
        }
        if CommandLine.arguments.count > 2 {
            let target = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Data(copied(dante_engine_save(engine)).utf8).write(to: target.appendingPathComponent("studio.json"))
        }
        let displayed = model.items.reversed().map(\.sceneItemID)
        let selected = displayed[0]; model.selectedItem = selected
        let history = model.undoCount
        model.moveSources(in: model.sceneName, ids: displayed, from: [0], to: 3)
        precondition(model.items.reversed().map { $0.string("name") } == ["B","A","C"])
        precondition(model.undoCount == history + 1 && model.selectedItem == selected)
        let reordered = model.items.map(\.sceneItemID)
        let saved = copied(dante_engine_save(engine))
        model.undo(); precondition(model.items.reversed().map(\.sceneItemID) == displayed)
        model.redo(); precondition(model.items.map(\.sceneItemID) == reordered)
        model.moveSources(in: "wrong-scene", ids: displayed, from: [0], to: 2)
        model.moveSources(in: model.sceneName, ids: displayed, from: [0], to: 2)
        precondition(model.items.map(\.sceneItemID) == reordered)
        precondition(!model.command("scene.reorderSources", ["scene":model.sceneName,"ids":[reordered[0],reordered[0],reordered[2]]]))
        precondition(!model.command("scene.reorderSources", ["scene":model.sceneName,"ids":[reordered[0]]]))
        precondition(model.items.map(\.sceneItemID) == reordered)
        precondition(dante_engine_load(engine,saved)); model.refresh()
        precondition(model.items.map(\.sceneItemID) == reordered)
        let table = NSTableView(); table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("source")))
        let controller = SourceListView.Coordinator(model:model); controller.table = table; controller.update(model)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = controller.tableView(table,pasteboardWriterForRow:0)!
        precondition(board.writeObjects([writer]))
        precondition(!controller.valid(source:NSTableView(),pasteboard:board))
        precondition(controller.valid(source:table,pasteboard:board))
        precondition(!controller.drop(source:table,pasteboard:board,row:99))
        let beforeDrop = model.items.reversed().map(\.sceneItemID)
        precondition(controller.drop(source:table,pasteboard:board,row:3))
        precondition(model.items.reversed().map(\.sceneItemID) == [beforeDrop[1],beforeDrop[2],beforeDrop[0]])
        precondition(!controller.valid(source:table,pasteboard:board))
        controller.update(model)
        let contextMenu = controller.menu(row:1)!
        let contextName = controller.rows[1].string("name")
        contextMenu.performActionForItem(at:0)
        precondition(model.showingProperties && model.selectedName == contextName)
        model.showingProperties = false
        print("PASS: AppKit drag pasteboard, foreign/invalid drop rejection, accepted drop updates engine, consumed token, clicked-row properties action")
        let originalName = "A"
        queue.submit(immediate: false) { precondition(model.command("source.update", ["name":originalName,"settings":["width":321]])) }
        model.selectedItem = model.items.first { $0.string("name") == "B" }!.sceneItemID
        queue.flush()
        precondition(model.properties(name:"A").object("settings").number("width") == 321)
        precondition(model.properties(name:"B").object("settings").number("width") == 640)
        let currentScene=model.sceneName
        precondition(!model.reusableSourceNames.contains(currentScene))
        precondition(model.command("scene.create",["name":"Parent QA"]))
        precondition(model.command("scene.create",["name":"Ancestor QA"]))
        precondition(model.command("source.reuse",["scene":"Parent QA","name":currentScene]))
        precondition(model.command("source.reuse",["scene":"Ancestor QA","name":"Parent QA"]))
        precondition(!model.reusableSourceNames.contains("Parent QA") && !model.reusableSourceNames.contains("Ancestor QA"))
        precondition(model.reusableSourceNames.contains("A"))
        precondition(!model.command("source.reuse",["scene":currentScene,"name":currentScene]))
        precondition(!model.command("source.reuse",["scene":currentScene,"name":"Ancestor QA"]))
        precondition(model.command("scene.delete",["scene":"Ancestor QA"]))
        precondition(model.command("scene.delete",["scene":"Parent QA"]))
        print("PASS: reusable choices exclude current scene and direct/indirect ancestors; engine rejects cycles")
        try await runCanvasGestureTests(model:model)
        try await runLiveSettingsTests(model: model, directory: directory)
        try await runGuestSecurityTests(model:model,directory:directory)
        let overview = try AgentTools.execute("studio_overview", arguments: [:], model: model)
        precondition((overview["scenes"] as? [[String: Any]])?.isEmpty == false)
        let mcpScene = "MCP QA"
        _ = try AgentTools.execute("scene_create", arguments: ["name": mcpScene], model: model)
        let added = try AgentTools.execute("source_add", arguments: ["scene": mcpScene, "type": "color_source_v3", "name": "Fundo MCP", "settings": ["width": 320, "height": 180, "color": 0xFF112233]], model: model)
        let mcpID = added["id"] as! Int64
        _ = try AgentTools.execute("item_transform", arguments: ["scene": mcpScene, "id": mcpID, "x": 42, "y": 64], model: model)
        _ = try AgentTools.execute("item_visibility", arguments: ["scene": mcpScene, "id": mcpID, "visible": false], model: model)
        let mcpItems = try AgentTools.execute("scene_items", arguments: ["scene": mcpScene], model: model)["items"] as! [[String: Any]]
        precondition(mcpItems.count == 1 && mcpItems[0].number("x") == 42 && !mcpItems[0].flag("visible"))
        precondition(mcpItems[0]["settings"] == nil && !mcpItems[0].string("sourceUUID").isEmpty)
        let reused = try AgentTools.execute("source_reuse", arguments: ["scene": mcpScene, "name": "A"], model: model)
        precondition((reused["id"] as? Int64 ?? 0) > 0)
        _ = try AgentTools.execute("item_order", arguments: ["scene": mcpScene, "id": mcpID, "index": 0], model: model)
        let savedState = model.state
        model.state["streaming"] = true
        do {
            _ = try AgentTools.execute("scene_create", arguments: ["name": "Must not exist"], model: model)
            preconditionFailure("MCP must not edit while streaming")
        } catch { precondition(!model.scenes.contains(where: { $0.string("name") == "Must not exist" })) }
        model.state = savedState
        do {
            _ = try AgentTools.execute("stream.start", arguments: [:], model: model)
            preconditionFailure("MCP must not expose stream operations")
        } catch { }
        UserDefaults.standard.set(true, forKey: AgentSocket.enabledKey)
        let agent = AgentSocket(model: model)
        agent.applyPreference()
        precondition(agent.running, agent.problem ?? "MCP socket failed")
        let response = try await Task.detached { () throws -> [String: Any] in
            let fd = try AgentWire.socket()
            defer { Darwin.close(fd) }
            var address = AgentWire.address(try AgentWire.path(directory))
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
            }
            precondition(connected)
            try AgentWire.writeLine(JSONSerialization.data(withJSONObject: ["tool": "studio_overview", "arguments": [:] as [String: Any]]), to: fd)
            return try JSONSerialization.jsonObject(with: AgentWire.readLine(fd)) as! [String: Any]
        }.value
        precondition(response["ok"] as? Bool == true)
        agent.stop()
        UserDefaults.standard.removeObject(forKey: AgentSocket.enabledKey)
        print("PASS: MCP allowlist, layout edits, redacted reads, live guard, local socket")
        let previousProfile = model.selectedProfileID
        precondition(previousProfile == "default")
        model.createProfile(name: "Entrevistas")
        let interviewsID = model.selectedProfileID
        precondition(interviewsID != previousProfile && model.profiles.count == 2)
        precondition(!model.scenes.contains(where: { $0.string("name") == mcpScene }))
        precondition(model.command("scene.create", ["name": "Cenário entrevista"]))
        model.selectProfile(previousProfile)
        precondition(model.selectedProfileID == previousProfile && model.scenes.contains(where: { $0.string("name") == mcpScene }))
        precondition(!model.scenes.contains(where: { $0.string("name") == "Cenário entrevista" }))
        model.selectProfile(interviewsID)
        precondition(model.scenes.contains(where: { $0.string("name") == "Cenário entrevista" }))
        model.renameProfile(interviewsID, to: "Conversas")
        precondition(model.selectedProfileName == "Conversas")
        let reopened = try ProductionProfiles(directory: directory)
        precondition(reopened.selectedID == interviewsID && reopened.selected.name == "Conversas")
        precondition(model.undoCount == 0 && model.redoCount == 0)
        print("PASS: production profiles isolate scene collections, persist last selection and rename, clear cross-profile history")
        model.shutdown()
        print("PASS: actual engine reorder, one-step undo/redo, stable selection, stale/invalid order rejection, save/load and source-bound edits; no physical devices or public output")
    }
}
